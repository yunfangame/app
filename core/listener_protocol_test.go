//go:build !cgo

package main

import (
	"encoding/json"
	"net"
	"testing"
)

func invokeListenerTestMethod(t *testing.T, method CoreMethod, arguments string) MethodResponse {
	t.Helper()
	frame := captureSingleFrame(t, func() {
		handleMethodCall(&MethodCall{
			ID:        "listener-test",
			Method:    method,
			Arguments: json.RawMessage(arguments),
		}, MethodResponse{ID: "listener-test"})
	})
	var response MethodResponse
	if err := json.Unmarshal(frame, &response); err != nil {
		t.Fatal(err)
	}
	return response
}

func requireListenerMethodError(t *testing.T, response MethodResponse, protocol string) {
	t.Helper()
	if response.Result != nil || response.Error == nil || response.Error.Code != "listener_not_ready" {
		t.Fatalf("listener failure was not returned through method error: %+v", response)
	}
	details, ok := response.Error.Details.(map[string]any)
	if !ok || details["protocol"] != protocol || details["listener"] != "mixed" {
		t.Fatalf("listener details missing or double encoded: %+v", response.Error.Details)
	}
}

func TestListenerStartMethodReportsStructuredFailure(t *testing.T) {
	prepareListenerTest(t)
	requireListenerMethodError(t, invokeListenerTestMethod(t, startListenerMethod, "null"), "config")
}

func TestListenerUpdateMethodReportsStructuredFailure(t *testing.T) {
	prepareListenerTest(t)
	foreign := bindTestTCP(t, 0)
	port := foreign.Addr().(*net.TCPAddr).Port
	setListenerTestConfig(port)
	isRunning.Store(true)
	requireListenerMethodError(t, invokeListenerTestMethod(t, updateConfigMethod, "{}"), "tcp")
	if isRunning.Load() {
		t.Fatal("update method failure left native running state enabled")
	}
}

func TestListenerSetupMethodReportsStructuredFailure(t *testing.T) {
	withSetupConfig(t, func(*SetupParams) error {
		return &listenerFailure{
			Stage:    "bind_failed",
			Listener: "mixed",
			Protocol: "tcp",
			Reason:   "address_in_use",
		}
	})
	requireListenerMethodError(t, invokeListenerTestMethod(t, setupConfigMethod, "{}"), "tcp")
}
