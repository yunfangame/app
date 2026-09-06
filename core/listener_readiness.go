package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"syscall"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/listener"
)

type listenerFailure struct {
	Stage       string `json:"stage"`
	Listener    string `json:"listener"`
	Protocol    string `json:"protocol"`
	Port        int    `json:"port"`
	BindAddress string `json:"bind_address"`
	AllowLAN    bool   `json:"allow_lan"`
	TCPReady    bool   `json:"tcp_ready"`
	UDPReady    bool   `json:"udp_ready"`
	Reason      string `json:"reason"`
	OSErrorCode uint64 `json:"os_error_code"`
}

func (failure *listenerFailure) Error() string {
	data, _ := json.Marshal(failure)
	return "listener_not_ready: " + string(data)
}

func missingListenerConfig() *listenerFailure {
	return &listenerFailure{
		Stage:    "config_unavailable",
		Listener: "mixed",
		Protocol: "config",
		Reason:   "config_unavailable",
	}
}

func mixedListenerFailure(general *config.General, result listener.MixedListenerResult) *listenerFailure {
	if result.Error == nil && (general.MixedPort == 0 || result.TCPReady && result.UDPReady) {
		return nil
	}
	failure := &listenerFailure{
		Stage:       "bind_failed",
		Listener:    "mixed",
		Protocol:    result.Network,
		Port:        general.MixedPort,
		BindAddress: safeListenerAddress(general),
		AllowLAN:    general.AllowLan,
		TCPReady:    result.TCPReady,
		UDPReady:    result.UDPReady,
		Reason:      "bind_failed",
	}
	if failure.Protocol == "" {
		failure.Protocol = "config"
		failure.Reason = "invalid_bind_address"
	}
	var errno syscall.Errno
	if errors.As(result.Error, &errno) {
		failure.OSErrorCode = uint64(errno)
	}
	switch {
	case errors.Is(result.Error, syscall.EADDRINUSE):
		failure.Reason = "address_in_use"
	case errors.Is(result.Error, syscall.EACCES), errors.Is(result.Error, syscall.EPERM):
		failure.Reason = "access_denied"
	case errors.Is(result.Error, syscall.EADDRNOTAVAIL):
		failure.Reason = "address_not_available"
	}
	return failure
}

func safeListenerAddress(general *config.General) string {
	if !general.AllowLan {
		return "127.0.0.1"
	}
	if general.BindAddress == "*" || general.BindAddress == "" {
		return "*"
	}
	if ip := net.ParseIP(general.BindAddress); ip != nil {
		return ip.String()
	}
	return "<non-ip>"
}

func respondListenerFailure(response MethodResponse, err error) bool {
	var failure *listenerFailure
	if !errors.As(err, &failure) {
		return false
	}
	response.failure(
		"listener_not_ready",
		fmt.Sprintf("Local %s listener is not ready", failure.Listener),
		failure,
	)
	return true
}
