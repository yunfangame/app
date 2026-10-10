package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"runtime"
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
	if isRunning.Load() {
		t.Fatal("failed listeners must not remain running")
	}
	if failure.TCPReady || failure.UDPReady {
		t.Fatalf("failed listener must not claim readiness after rollback: %+v", failure)
	}
	return failure
}

func requireConflictReason(t *testing.T, failure *listenerFailure) {
	t.Helper()
	want := "address_in_use"
	if runtime.GOOS == "windows" && failure.OSErrorCode == 10013 {
		want = "access_denied"
	}
	if failure.Reason != want {
		t.Fatalf("conflict reason = %q, want %q: %+v", failure.Reason, want, failure)
	}
}

func TestListenerBindErrorReasonWindowsNativeCodes(t *testing.T) {
	for _, tc := range []struct {
		code syscall.Errno
		want string
	}{
		{10048, "address_in_use"},
		{10013, "access_denied"},
		{10049, "address_not_available"},
		{5, "access_denied"},
		{10022, ""},
	} {
		t.Run(fmt.Sprint(tc.code), func(t *testing.T) {
			err := fmt.Errorf("listener failed: %w", &net.OpError{
				Op:  "listen",
				Net: "tcp",
				Err: &os.SyscallError{Syscall: "bind", Err: tc.code},
			})
			if got := listenerBindErrorReason(err, "windows"); got != tc.want {
				t.Fatalf("Windows error %d reason = %q, want %q", tc.code, got, tc.want)
			}
		})
	}
}

func TestListenerBindErrorReasonDoesNotMapWindowsCodesOnOtherPlatforms(t *testing.T) {
	for _, goos := range []string{"darwin", "linux", "android"} {
		for _, code := range []syscall.Errno{10048, 10013, 10049, 5} {
			t.Run(fmt.Sprintf("%s-%d", goos, code), func(t *testing.T) {
				err := &net.OpError{
					Op:  "listen",
					Net: "udp",
					Err: &os.SyscallError{Syscall: "bind", Err: code},
				}
				if got := listenerBindErrorReason(err, goos); got != "" {
					t.Fatalf("non-Windows error %d reason = %q", code, got)
				}
			})
		}
	}
}

func TestListenerBindErrorReasonPreservesNativeErrnoClassification(t *testing.T) {
	for _, tc := range []struct {
		code syscall.Errno
		want string
	}{
		{syscall.EADDRINUSE, "address_in_use"},
		{syscall.EACCES, "access_denied"},
		{syscall.EPERM, "access_denied"},
		{syscall.EADDRNOTAVAIL, "address_not_available"},
	} {
		t.Run(fmt.Sprint(tc.code), func(t *testing.T) {
			err := &net.OpError{
				Op:  "listen",
				Net: "tcp",
				Err: &os.SyscallError{Syscall: "bind", Err: tc.code},
			}
			if got := listenerBindErrorReason(err, runtime.GOOS); got != tc.want {
				t.Fatalf("native error %d reason = %q, want %q", tc.code, got, tc.want)
			}
		})
	}
}

func TestMixedListenerFailurePreservesNativeCodeAndProtocol(t *testing.T) {
	for _, network := range []string{"tcp", "udp"} {
		for _, code := range []syscall.Errno{10048, 10013, 10049, 5, 10022} {
			t.Run(fmt.Sprintf("%s-%d", network, code), func(t *testing.T) {
				general := &config.General{Inbound: config.Inbound{MixedPort: 7890}}
				err := &net.OpError{
					Op:  "listen",
					Net: network,
					Err: &os.SyscallError{Syscall: "bind", Err: code},
				}
				failure := mixedListenerFailure(general, listener.MixedListenerResult{
					Network: network,
					Error:   err,
				})
				wantReason := listenerBindErrorReason(err, runtime.GOOS)
				if wantReason == "" {
					wantReason = "bind_failed"
				}
				if failure.OSErrorCode != uint64(code) || failure.Protocol != network ||
					failure.Reason != wantReason || failure.Port != 7890 || failure.Stage != "bind_failed" ||
					failure.Listener != "mixed" || failure.TCPReady || failure.UDPReady {
					t.Fatalf("native bind diagnostics changed: %+v", failure)
				}
			})
		}
	}
}

func TestListenerMissingConfigFailsWithoutRunning(t *testing.T) {
	prepareListenerTest(t)
	failure := requireListenerFailure(t, startListenerWithResult(), "config")
	if failure.Stage != "config_unavailable" || handleStartListener() {
		t.Fatal("missing config reported success")
	}
}

func TestListenerRejectsForeignTCPPort(t *testing.T) {
	prepareListenerTest(t)
	foreign := bindTestTCP(t, 0)
	port := foreign.Addr().(*net.TCPAddr).Port
	setListenerTestConfig(port)
	failure := requireListenerFailure(t, startListenerWithResult(), "tcp")
	requireConflictReason(t, failure)
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
	requireConflictReason(t, failure)
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
	if !isRunning.Load() || listener.GetPorts().MixedPort != port {
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
	if !handleStopListener() || isRunning.Load() {
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
	failure := requireListenerFailure(t, updateConfig(&UpdateParams{MixedPort: &blockedPort}), "tcp")
	requireConflictReason(t, failure)
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
	if isRunning.Load() || listener.GetPorts().MixedPort != 0 {
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
}

func TestTunListenerReadiness(t *testing.T) {
	for _, tc := range []struct {
		name        string
		enabled     bool
		result      listener.TunListenerResult
		wantFailure bool
	}{
		{"disabled", false, listener.TunListenerResult{}, false},
		{"ready", true, listener.TunListenerResult{Ready: true}, false},
		{"absent", true, listener.TunListenerResult{}, true},
		{"driver refused", true, listener.TunListenerResult{Error: fmt.Errorf("create adapter: %w", syscall.Errno(5))}, true},
		{"error despite ready", true, listener.TunListenerResult{Ready: true, Error: errors.New("route setup failed")}, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			failure := tunListenerFailure(tc.enabled, tc.result)
			if (failure != nil) != tc.wantFailure {
				t.Fatalf("unexpected failure: %v", failure)
			}
			if failure != nil && (failure.Listener != "tun" || failure.Stage != "adapter_create") {
				t.Fatalf("wrong diagnostic: %+v", failure)
			}
			if tc.name == "driver refused" && (failure.OSErrorCode != 5 || failure.Reason != "access_denied" || failure.ErrorMessage == "") {
				t.Fatalf("native error lost: %+v", failure)
			}
		})
	}
}
