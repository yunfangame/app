package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"reflect"
	"testing"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

func assertReferenceRange(t *testing.T, value int32) {
	t.Helper()
	if value < 120 || value > 150 {
		t.Errorf("reference result = %d, want inclusive range 120..150", value)
	}
}

func TestURLTestPolicyRunsOnceBeforeEventHistoryAndRPC(t *testing.T) {
	if reflect.ValueOf(adapter.UrlTestDelayTransform).Pointer() != reflect.ValueOf(referenceDelayValue).Pointer() {
		t.Fatal("reference delay policy is not installed on native URLTest ingress")
	}
	previousTransform := adapter.UrlTestDelayTransform
	previousHook := adapter.UrlTestHook
	transformCalls := 0
	var eventDelay uint16
	adapter.UrlTestDelayTransform = func(raw uint16, probeErr error) uint16 {
		transformCalls++
		return 137
	}
	adapter.UrlTestHook = func(url, name string, delay uint16) {
		eventDelay = delay
	}
	t.Cleanup(func() {
		adapter.UrlTestDelayTransform = previousTransform
		adapter.UrlTestHook = previousHook
		tunnel.UpdateProxies(nil, nil)
	})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()
	proxy := namedProxy("reference-policy").(*adapter.Proxy)
	tunnel.UpdateProxies(map[string]constant.Proxy{proxy.Name(): proxy}, nil)
	result := handleTestDelay(&TestDelayParams{ProxyName: proxy.Name(), TestUrl: server.URL, Timeout: 5000})
	if transformCalls != 1 {
		t.Fatalf("policy calls = %d, want one per completed probe", transformCalls)
	}
	if result.Value != 137 || eventDelay != 137 {
		t.Fatalf("RPC/event = %d/%d, want the same once-adjusted 137", result.Value, eventDelay)
	}
	if result.Successful == nil || !*result.Successful {
		t.Fatal("actual successful probe lost its success flag")
	}
	if history := proxy.DelayHistory(); len(history) != 1 || history[0].Delay != 137 {
		t.Fatalf("native history = %+v, want only adjusted value", history)
	}
	if history := proxy.DelayHistoryForTestUrl(server.URL); len(history) != 1 || history[0].Delay != 137 {
		t.Fatalf("per-URL native history = %+v, want only adjusted value", history)
	}
	if got := proxy.LastDelayForTestUrl(server.URL); got != 137 {
		t.Errorf("last URL delay = %d, want adjusted value", got)
	}
	encoded, err := proxy.MarshalJSON()
	if err != nil {
		t.Fatal(err)
	}
	var snapshot struct {
		History []struct{ Delay int } `json:"history"`
		Extra   map[string]struct {
			History []struct{ Delay int } `json:"history"`
		} `json:"extra"`
	}
	if err := json.Unmarshal(encoded, &snapshot); err != nil {
		t.Fatal(err)
	}
	if len(snapshot.History) != 1 || snapshot.History[0].Delay != 137 || snapshot.Extra[server.URL].History[0].Delay != 137 {
		t.Fatalf("JSON proxy histories did not retain only the adjusted result: %s", encoded)
	}
}

func TestFailedURLTestKeepsItsErrorAndHealthWhileReturningReferenceDelay(t *testing.T) {
	previousHook := adapter.UrlTestHook
	var eventDelay uint16
	adapter.UrlTestHook = func(url, name string, delay uint16) { eventDelay = delay }
	t.Cleanup(func() { adapter.UrlTestHook = previousHook })
	proxy := namedProxy("failed-reference-policy")
	const testURL = "invalid://example.test"
	value, err := proxy.URLTest(context.Background(), testURL, nil)
	if err == nil {
		t.Fatal("reference conversion must not turn an actual URLTest error into success")
	}
	assertReferenceRange(t, int32(value))
	if eventDelay != value {
		t.Errorf("failed probe event = %d, want the same reference result %d", eventDelay, value)
	}
	if proxy.AliveForTestUrl(testURL) {
		t.Error("failed probe must retain actual internal health")
	}
	if history := proxy.DelayHistory(); len(history) != 1 || history[0].Delay != 0 {
		t.Errorf("failed probe retained an actual numerical measurement: %+v", history)
	}
}

func TestCompletedFailedRPCPublishesReferenceDelayAndFailureFlag(t *testing.T) {
	proxy := namedProxy("failed-rpc-policy")
	tunnel.UpdateProxies(map[string]constant.Proxy{proxy.Name(): proxy}, nil)
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })
	result := handleTestDelay(&TestDelayParams{ProxyName: proxy.Name(), TestUrl: "invalid://example.test", Timeout: 5000})
	assertReferenceRange(t, result.Value)
	if result.Successful == nil || *result.Successful {
		t.Fatal("completed failed RPC must keep successful=false")
	}
	encoded, err := json.Marshal(result)
	if err != nil {
		t.Fatal(err)
	}
	var response map[string]any
	if err := json.Unmarshal(encoded, &response); err != nil {
		t.Fatal(err)
	}
	if response["successful"] != false || len(response) != 4 {
		t.Fatalf("RPC must expose only name, url, adjusted value and success flag: %s", encoded)
	}
}
