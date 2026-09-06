//go:build !cgo

package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"sync"
	"testing"

	"github.com/metacubex/mihomo/constant"
)

type listenerResponseRecorder struct {
	mutex  sync.Mutex
	buffer bytes.Buffer
}

func (recorder *listenerResponseRecorder) Read(data []byte) (int, error) {
	return 0, io.EOF
}

func (recorder *listenerResponseRecorder) Write(data []byte) (int, error) {
	recorder.mutex.Lock()
	defer recorder.mutex.Unlock()
	return recorder.buffer.Write(data)
}

func (recorder *listenerResponseRecorder) Close() error {
	return nil
}

func invokeListenerTestMethod(t *testing.T, method CoreMethod, arguments string) MethodResponse {
	t.Helper()
	previous := conn
	recorder := &listenerResponseRecorder{}
	conn = recorder
	defer func() { conn = previous }()
	handleMethodCall(&MethodCall{
		ID:        "listener-test",
		Method:    method,
		Arguments: json.RawMessage(arguments),
	}, MethodResponse{ID: "listener-test"})
	recorder.mutex.Lock()
	defer recorder.mutex.Unlock()
	for recorder.buffer.Len() > 0 {
		data, err := readFrame(&recorder.buffer)
		if err != nil {
			t.Fatal(err)
		}
		var response MethodResponse
		if err := json.Unmarshal(data, &response); err != nil {
			t.Fatal(err)
		}
		if response.ID == "listener-test" {
			return response
		}
	}
	t.Fatal("listener method response missing")
	return MethodResponse{}
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
	isRunning = true
	requireListenerMethodError(t, invokeListenerTestMethod(t, updateConfigMethod, "{}"), "tcp")
	if isRunning {
		t.Fatal("update method failure left native running state enabled")
	}
}

func TestListenerSetupMethodReportsStructuredFailure(t *testing.T) {
	prepareListenerTest(t)
	previousHome := constant.Path.HomeDir()
	constant.SetHomeDir(t.TempDir())
	t.Cleanup(func() { constant.SetHomeDir(previousHome) })
	foreign := bindTestTCP(t, 0)
	port := foreign.Addr().(*net.TCPAddr).Port
	data := fmt.Sprintf("mixed-port: %d\nallow-lan: false\nmode: direct\ndns:\n  enable: false\nrules: []\n", port)
	if err := os.WriteFile(filepath.Join(constant.Path.HomeDir(), "config.yaml"), []byte(data), 0600); err != nil {
		t.Fatal(err)
	}
	isInit.Store(true)
	isRunning = true
	requireListenerMethodError(t, invokeListenerTestMethod(t, setupConfigMethod, "{}"), "tcp")
	if isRunning {
		t.Fatal("setup method failure left native running state enabled")
	}
}
