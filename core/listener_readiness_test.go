package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/listener"
)

func prepareListenerTest(t *testing.T) {
	t.Helper()
	handleStopListener()
	previousConfig := currentConfig
	previousInit := isInit.Load()
	currentConfig = nil
	t.Cleanup(func() {
		handleStopListener()
		currentConfig = previousConfig
		isInit.Store(previousInit)
	})
}

func setListenerTestConfig(port int) {
	currentConfig = &config.Config{
		General: &config.General{
			Inbound: config.Inbound{
				MixedPort:   port,
				BindAddress: "*",
			},
		},
	}
}

func bindTestTCP(t *testing.T, port int) net.Listener {
	t.Helper()
	server, err := net.Listen("tcp4", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = server.Close() })
	return server
}

func unusedMixedPort(t *testing.T) int {
	t.Helper()
	for attempt := 0; attempt < 10; attempt++ {
		server := bindTestTCP(t, 0)
		port := server.Addr().(*net.TCPAddr).Port
		packet, err := net.ListenPacket("udp4", fmt.Sprintf("127.0.0.1:%d", port))
		_ = server.Close()
		if err == nil {
			_ = packet.Close()
			return port
		}
	}
	t.Fatal("could not allocate a free TCP and UDP port")
	return 0
}

func requireListenerFailure(t *testing.T, err error, protocol string) *listenerFailure {
	t.Helper()
	var failure *listenerFailure
	if !errors.As(err, &failure) {
		t.Fatalf("expected listener failure, got %v", err)
	}
	if failure.Protocol != protocol {
		t.Fatalf("expected protocol %s, got %+v", protocol, failure)
	}
	if isRunning {
		t.Fatal("failed listeners must not remain running")
	}
	if failure.TCPReady || failure.UDPReady {
		t.Fatalf("failed listener must not claim readiness after rollback: %+v", failure)
	}
	return failure
}

func TestListenerMissingConfigFailsWithoutRunning(t *testing.T) {
	prepareListenerTest(t)
	failure := requireListenerFailure(t, startListenerWithResult(), "config")
	if failure.Stage != "config_unavailable" || handleStartListener() {
		t.Fatal("missing config reported success")
	}
	isRunning = true
	requireListenerFailure(t, updateConfig(&UpdateParams{}), "config")
}

func TestListenerRejectsForeignTCPPort(t *testing.T) {
	prepareListenerTest(t)
	foreign := bindTestTCP(t, 0)
	port := foreign.Addr().(*net.TCPAddr).Port
	setListenerTestConfig(port)
	failure := requireListenerFailure(t, startListenerWithResult(), "tcp")
	if failure.OSErrorCode == 0 || failure.Port != port || failure.BindAddress != "127.0.0.1" {
		t.Fatalf("missing safe bind diagnostics: %+v", failure)
	}
	if listener.GetPorts().MixedPort != 0 {
		t.Fatal("foreign listener was treated as owned")
	}
	connection, err := net.DialTimeout("tcp4", foreign.Addr().String(), time.Second)
	if err != nil {
		t.Fatalf("foreign listener must not be stopped: %v", err)
	}
	_ = connection.Close()
}

func TestListenerRejectsForeignUDPPortAndCleansTCP(t *testing.T) {
	prepareListenerTest(t)
	port := unusedMixedPort(t)
	foreign, err := net.ListenPacket("udp4", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = foreign.Close() })
	setListenerTestConfig(port)
	failure := requireListenerFailure(t, startListenerWithResult(), "udp")
	if failure.OSErrorCode == 0 {
		t.Fatalf("UDP bind error missing OS error: %+v", failure)
	}
	if listener.GetPorts().MixedPort != 0 {
		t.Fatal("UDP failure retained a stale closed TCP listener")
	}
	probe := bindTestTCP(t, port)
	_ = probe.Close()
	_ = foreign.Close()
	if err := startListenerWithResult(); err != nil {
		t.Fatalf("retry after releasing UDP conflict failed: %v", err)
	}
}

func TestListenerOwnsTCPAndUDPBeforeSuccess(t *testing.T) {
	prepareListenerTest(t)
	port := unusedMixedPort(t)
	setListenerTestConfig(port)
	if err := startListenerWithResult(); err != nil {
		t.Fatal(err)
	}
	if !isRunning || listener.GetPorts().MixedPort != port {
		t.Fatal("successful listener did not retain owned running state")
	}
	address := fmt.Sprintf("127.0.0.1:%d", port)
	connection, err := net.DialTimeout("tcp4", address, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	_ = connection.Close()
	packet, err := net.ListenPacket("udp4", address)
	if err == nil {
		_ = packet.Close()
		t.Fatal("successful listener did not own its UDP socket")
	}
	if !handleStartListener() {
		t.Fatal("repeated start should preserve existing owned listeners")
	}
	if !handleStopListener() || isRunning {
		t.Fatal("stop did not clear running state")
	}
	probe := bindTestTCP(t, port)
	_ = probe.Close()
	if err := startListenerWithResult(); err != nil {
		t.Fatalf("restart after stop failed: %v", err)
	}
}

func TestListenerPortUpdateFailureStopsOldOwnedPort(t *testing.T) {
	prepareListenerTest(t)
	port := unusedMixedPort(t)
	setListenerTestConfig(port)
	if err := startListenerWithResult(); err != nil {
		t.Fatal(err)
	}
	foreign := bindTestTCP(t, 0)
	blockedPort := foreign.Addr().(*net.TCPAddr).Port
	requireListenerFailure(t, updateConfig(&UpdateParams{MixedPort: &blockedPort}), "tcp")
	if listener.GetPorts().MixedPort != 0 {
		t.Fatal("failed port update retained mixed listener ownership")
	}
	oldPort := bindTestTCP(t, port)
	_ = oldPort.Close()
	_ = foreign.Close()
	if err := startListenerWithResult(); err != nil {
		t.Fatalf("start with corrected port availability failed: %v", err)
	}
}

func TestListenerStoppedConfigUpdateDoesNotOpenSockets(t *testing.T) {
	prepareListenerTest(t)
	port := unusedMixedPort(t)
	setListenerTestConfig(port)
	if err := updateConfig(&UpdateParams{}); err != nil {
		t.Fatal(err)
	}
	if isRunning || listener.GetPorts().MixedPort != 0 {
		t.Fatal("stopped config update started listeners")
	}
	_ = bindTestTCP(t, port)
}

func TestListenerExplicitZeroMixedPortRemainsSupported(t *testing.T) {
	prepareListenerTest(t)
	setListenerTestConfig(0)
	if !handleStartListener() {
		t.Fatal("explicit disabled mixed listener should not prevent non-mixed operation")
	}
}

func TestListenerFailureDiagnosticsAreSafeWithoutLogSubscription(t *testing.T) {
	prepareListenerTest(t)
	if logSubscriber != nil {
		t.Fatal("test must not rely on a runtime log subscription")
	}
	setListenerTestConfig(7890)
	currentConfig.General.AllowLan = true
	currentConfig.General.BindAddress = "private-user:password@example.invalid"
	failure := mixedListenerFailure(currentConfig.General, listener.MixedListenerResult{
		Network: "tcp",
		Error: &net.OpError{
			Op:  "listen private-password",
			Net: "tcp",
			Err: &os.SyscallError{Syscall: "private-token", Err: syscall.EACCES},
		},
	})
	data, err := json.Marshal(MethodResponse{
		Error: &MethodError{Code: "listener_not_ready", Message: "Local mixed listener is not ready", Details: failure},
	})
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	if strings.Contains(text, "private-") || strings.Contains(text, "password") || strings.Contains(text, "example.invalid") {
		t.Fatalf("unsafe listener diagnostic: %s", text)
	}
	if failure.Reason != "access_denied" || failure.OSErrorCode != uint64(syscall.EACCES) || failure.BindAddress != "<non-ip>" {
		t.Fatalf("safe OS error classification missing: %+v", failure)
	}
	var response map[string]any
	if err := json.Unmarshal(data, &response); err != nil {
		t.Fatal(err)
	}
	methodError := response["error"].(map[string]any)
	if _, ok := methodError["details"].(map[string]any); !ok {
		t.Fatal("listener error details must remain a structured JSON object")
	}
}
