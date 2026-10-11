#include <winsock2.h>
#include <ws2tcpip.h>

#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>

#include <memory>
#include <chrono>
#include <future>
#include <stdexcept>
#include <string>
#include <utility>
#include <variant>
#include <cstring>

#include "proxy_plugin.h"
#include "proxy_settings.h"

namespace proxy {
namespace test {

namespace {

using flutter::EncodableMap;
using flutter::EncodableList;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;

std::future<EncodableValue> InvokeProxy(
    ProxyPlugin& plugin, const std::string& method, EncodableMap arguments) {
  auto completion = std::make_shared<std::promise<EncodableValue>>();
  auto future = completion->get_future();
  plugin.HandleMethodCall(
      MethodCall(method,
                 std::make_unique<EncodableValue>(std::move(arguments))),
      std::make_unique<MethodResultFunctions<>>(
          [completion](const EncodableValue* value) {
            completion->set_value(value == nullptr ? EncodableValue() : *value);
          },
          [completion](const std::string& code, const std::string& message,
                       const EncodableValue*) {
            completion->set_exception(
                std::make_exception_ptr(std::runtime_error(code + ": " + message)));
          },
          [completion]() {
            completion->set_exception(
                std::make_exception_ptr(std::runtime_error("not implemented")));
          }));
  return future;
}

bool AllowProxyMutation() {
  char actions[16] = {};
  char allowed[16] = {};
  GetEnvironmentVariableA("GITHUB_ACTIONS", actions, 16);
  GetEnvironmentVariableA("FENGWO_PROXY_MUTATING_TEST", allowed, 16);
  return std::string(actions) == "true" && std::string(allowed) == "1";
}

class ActualProxySnapshot {
 public:
  ActualProxySnapshot() {
    DWORD error = 0;
    captured_ = settings::QueryConnection(L"", original_, error);
  }

  ~ActualProxySnapshot() {
    if (captured_) EXPECT_TRUE(Apply(original_));
  }

  bool captured() const { return captured_; }

  static bool Apply(const settings::ConnectionConfiguration& value) {
    DWORD error = 0;
    bool fallback = false;
    return settings::WriteConnection(L"", value, error, fallback) &&
        InternetSetOptionW(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0) &&
        InternetSetOptionW(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0);
  }

  static settings::ConnectionConfiguration Read() {
    settings::ConnectionConfiguration value;
    DWORD error = 0;
    EXPECT_TRUE(settings::QueryConnection(L"", value, error));
    return value;
  }

 private:
  settings::ConnectionConfiguration original_;
  bool captured_ = false;
};

class LoopbackListener {
 public:
  explicit LoopbackListener(bool ipv6_only = false) {
    WSADATA data = {};
    initialized_ = WSAStartup(MAKEWORD(2, 2), &data) == 0;
    if (!initialized_) return;
    const int family = ipv6_only ? AF_INET6 : AF_INET;
    socket_ = socket(family, SOCK_STREAM, IPPROTO_TCP);
    if (socket_ == INVALID_SOCKET) return;
    sockaddr_storage endpoint = {};
    int size = 0;
    if (ipv6_only) {
      const DWORD enabled = 1;
      if (setsockopt(socket_, IPPROTO_IPV6, IPV6_V6ONLY,
                     reinterpret_cast<const char*>(&enabled), sizeof(enabled)) != 0) return;
      auto* address = reinterpret_cast<sockaddr_in6*>(&endpoint);
      address->sin6_family = AF_INET6;
      address->sin6_addr.u.Byte[15] = 1;
      size = sizeof(sockaddr_in6);
    } else {
      auto* address = reinterpret_cast<sockaddr_in*>(&endpoint);
      address->sin_family = AF_INET;
      address->sin_addr.s_addr = htonl(INADDR_LOOPBACK);
      size = sizeof(sockaddr_in);
    }
    if (bind(socket_, reinterpret_cast<sockaddr*>(&endpoint), size) != 0 ||
        listen(socket_, SOMAXCONN) != 0) return;
    if (getsockname(socket_, reinterpret_cast<sockaddr*>(&endpoint), &size) == 0) {
      port_ = ipv6_only
          ? ntohs(reinterpret_cast<const sockaddr_in6*>(&endpoint)->sin6_port)
          : ntohs(reinterpret_cast<const sockaddr_in*>(&endpoint)->sin_port);
    }
  }

  ~LoopbackListener() {
    Close();
    if (initialized_) WSACleanup();
  }

  int port() const { return port_; }

  void Close() {
    if (socket_ != INVALID_SOCKET) {
      closesocket(socket_);
      socket_ = INVALID_SOCKET;
    }
  }

 private:
  bool initialized_ = false;
  SOCKET socket_ = INVALID_SOCKET;
  int port_ = 0;
};

EncodableMap InvokeDetailed(ProxyPlugin& plugin, const std::string& method,
                           EncodableMap arguments = {}) {
  auto result = InvokeProxy(plugin, method, std::move(arguments));
  EXPECT_EQ(result.wait_for(std::chrono::seconds(30)), std::future_status::ready);
  return std::get<EncodableMap>(result.get());
}

bool Succeeded(const EncodableMap& value) {
  return std::get<bool>(value.at(EncodableValue("success")));
}

settings::ConnectionConfiguration ExternalProxy(int port) {
  return {PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY,
          L"127.0.0.1:" + std::to_wstring(port), L"*.external;<local>", L""};
}

}  // namespace

TEST(ProxyPlugin, UnknownMethodIsNotImplemented) {
  ProxyPlugin plugin;
  bool not_implemented = false;
  plugin.HandleMethodCall(
      MethodCall("unknown", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          nullptr, nullptr,
          [&not_implemented]() { not_implemented = true; }));

  EXPECT_TRUE(not_implemented);
}

TEST(ProxyPlugin, StartProxyRejectsMissingArguments) {
  ProxyPlugin plugin;
  std::string error_code;
  plugin.HandleMethodCall(
      MethodCall("StartProxy", std::make_unique<EncodableValue>(EncodableMap())),
      std::make_unique<MethodResultFunctions<>>(
          nullptr,
          [&error_code](
              const std::string& code,
              const std::string& message,
              const EncodableValue* details) { error_code = code; },
          nullptr));

  EXPECT_EQ(error_code, "bad_args");
}

TEST(ProxyPlugin, StartProxyRejectsInvalidPort) {
  ProxyPlugin plugin;
  std::string error_code;
  EncodableMap arguments = {
      {EncodableValue("port"), EncodableValue(70000)},
      {EncodableValue("bypassDomain"), EncodableValue(EncodableList())}};

  plugin.HandleMethodCall(
      MethodCall(
          "StartProxy",
          std::make_unique<EncodableValue>(std::move(arguments))),
      std::make_unique<MethodResultFunctions<>>(
          nullptr,
          [&error_code](
              const std::string& code,
              const std::string& message,
              const EncodableValue* details) { error_code = code; },
          nullptr));

  EXPECT_EQ(error_code, "bad_args");
}

TEST(ProxyPlugin, StartProxyRejectsNonStringBypassDomain) {
  ProxyPlugin plugin;
  std::string error_code;
  EncodableList bypass_domain = {
      EncodableValue("localhost"),
      EncodableValue(1)};
  EncodableMap arguments = {
      {EncodableValue("port"), EncodableValue(7890)},
      {EncodableValue("bypassDomain"),
       EncodableValue(std::move(bypass_domain))}};

  plugin.HandleMethodCall(
      MethodCall(
          "StartProxy",
          std::make_unique<EncodableValue>(std::move(arguments))),
      std::make_unique<MethodResultFunctions<>>(
          nullptr,
          [&error_code](
              const std::string& code,
              const std::string& message,
              const EncodableValue* details) { error_code = code; },
          nullptr));

  EXPECT_EQ(error_code, "bad_args");
}

TEST(ProxyPlugin, RestoresTheSystemProxyOnlyWhenTheSessionReallyEnds) {
  EXPECT_TRUE(ProxyPlugin::IsSessionEnding(WM_ENDSESSION, TRUE));
  EXPECT_FALSE(ProxyPlugin::IsSessionEnding(WM_ENDSESSION, FALSE));
  EXPECT_FALSE(ProxyPlugin::IsSessionEnding(WM_QUERYENDSESSION, TRUE));
  EXPECT_FALSE(ProxyPlugin::IsSessionEnding(WM_CLOSE, TRUE));
}

TEST(ProxyPlugin, OwnsOnlyAProxyThatWasAppliedSuccessfully) {
  EXPECT_EQ(ProxyPlugin::AppliedProxyPort(true, 7890), 7890);
  EXPECT_EQ(ProxyPlugin::AppliedProxyPort(false, 7890), std::nullopt);
}

TEST(ProxyPlugin, StopProxyDetailedRejectsInvalidExpectedPort) {
  ProxyPlugin plugin;
  std::string error_code;
  EncodableMap arguments = {
      {EncodableValue("expectedPort"), EncodableValue(0)}};

  plugin.HandleMethodCall(
      MethodCall(
          "StopProxyDetailed",
          std::make_unique<EncodableValue>(std::move(arguments))),
      std::make_unique<MethodResultFunctions<>>(
          nullptr,
          [&error_code](
              const std::string& code,
              const std::string& message,
              const EncodableValue* details) { error_code = code; },
          nullptr));

  EXPECT_EQ(error_code, "bad_args");
}

TEST(ProxyPlugin, InspectProxyRejectsMissingExpectedPort) {
  ProxyPlugin plugin;
  std::string error_code;

  plugin.HandleMethodCall(
      MethodCall(
          "InspectProxy",
          std::make_unique<EncodableValue>(EncodableMap())),
      std::make_unique<MethodResultFunctions<>>(
          nullptr,
          [&error_code](
              const std::string& code,
              const std::string& message,
              const EncodableValue* details) { error_code = code; },
          nullptr));

  EXPECT_EQ(error_code, "bad_args");
}

TEST(ProxyPlugin, SessionEndRejectsFurtherProxyOperations) {
  ProxyPlugin plugin;
  plugin.HandleWindowProc(nullptr, WM_ENDSESSION, TRUE, 0);
  auto completion = std::make_shared<
      std::promise<std::pair<std::string, std::string>>>();
  auto future = completion->get_future();
  plugin.HandleMethodCall(
      MethodCall(
          "InspectProxy",
          std::make_unique<EncodableValue>(EncodableMap{
              {EncodableValue("expectedPort"), EncodableValue(7890)}})),
      std::make_unique<MethodResultFunctions<>>(
          [completion](const EncodableValue*) {
            completion->set_value({"success", ""});
          },
          [completion](const std::string& code, const std::string& message,
                       const EncodableValue*) {
            completion->set_value({code, message});
          },
          [completion]() {
            completion->set_value({"not_implemented", ""});
          }));
  ASSERT_EQ(future.wait_for(std::chrono::seconds(1)), std::future_status::ready);
  const auto reply = future.get();
  EXPECT_EQ(reply.first, "proxy_shutdown");
  EXPECT_EQ(reply.second, "The system proxy worker is shutting down");
}

TEST(ProxyPlugin, DetailedStartAndStopRoundTripCurrentUserProxy) {
  if (!AllowProxyMutation()) GTEST_SKIP() << "Requires an isolated CI account";
  ActualProxySnapshot original;
  ASSERT_TRUE(original.captured());
  ASSERT_TRUE(ActualProxySnapshot::Apply({PROXY_TYPE_DIRECT, L"", L"", L""}));
  ProxyPlugin plugin;
  auto start = InvokeProxy(plugin, "StartProxyDetailed", {
      {EncodableValue("port"), EncodableValue(7890)},
      {EncodableValue("bypassDomain"),
       EncodableValue(EncodableList{EncodableValue("localhost")})}});
  ASSERT_EQ(start.wait_for(std::chrono::seconds(30)), std::future_status::ready);
  const auto start_value = start.get();
  const auto& start_map = std::get<EncodableMap>(start_value);
  EXPECT_TRUE(std::get<bool>(start_map.at(EncodableValue("success"))));
  EXPECT_TRUE(std::get<bool>(start_map.at(EncodableValue("enabled"))));
  EXPECT_EQ(std::get<std::string>(start_map.at(EncodableValue("server"))),
            "127.0.0.1:7890");

  auto stop = InvokeProxy(plugin, "StopProxyDetailed", {
      {EncodableValue("expectedPort"), EncodableValue(7890)}});
  ASSERT_EQ(stop.wait_for(std::chrono::seconds(30)), std::future_status::ready);
  const auto stop_value = stop.get();
  const auto& stop_map = std::get<EncodableMap>(stop_value);
  EXPECT_TRUE(std::get<bool>(stop_map.at(EncodableValue("success"))));
  EXPECT_FALSE(std::get<bool>(stop_map.at(EncodableValue("enabled"))));
}

TEST(ProxyPlugin, InspectReportsExternalPacAndAutomaticDiscovery) {
  if (!AllowProxyMutation()) GTEST_SKIP() << "Requires an isolated CI account";
  ActualProxySnapshot original;
  ASSERT_TRUE(original.captured());
  ProxyPlugin plugin;
  for (const auto automatic : {PROXY_TYPE_AUTO_PROXY_URL, PROXY_TYPE_AUTO_DETECT,
                               PROXY_TYPE_AUTO_PROXY_URL | PROXY_TYPE_AUTO_DETECT}) {
    for (const bool manual : {false, true}) {
      const settings::ConnectionConfiguration external{
          static_cast<uint32_t>(PROXY_TYPE_DIRECT | automatic |
                                (manual ? PROXY_TYPE_PROXY : 0)),
          L"127.0.0.1:7890", L"*.external;<local>", L"https://external.example/proxy.pac"};
      ASSERT_TRUE(ActualProxySnapshot::Apply(external));
      const auto inspection = InvokeDetailed(plugin, "InspectProxy", {
          {EncodableValue("expectedPort"), EncodableValue(7890)}});
      EXPECT_FALSE(Succeeded(inspection));
      EXPECT_EQ(std::get<std::string>(inspection.at(EncodableValue("stage"))),
                "readback_mismatch");
      EXPECT_EQ(std::get<bool>(inspection.at(EncodableValue("enabled"))), manual);
      EXPECT_TRUE(std::get<bool>(inspection.at(EncodableValue("automaticProxyEnabled"))));
      EXPECT_EQ(ActualProxySnapshot::Read(), external);
    }
  }
}

TEST(ProxyPlugin, NoSessionStopPreservesExternalSamePortProxy) {
  if (!AllowProxyMutation()) GTEST_SKIP() << "Requires an isolated CI account";
  ActualProxySnapshot original;
  ASSERT_TRUE(original.captured());
  const auto external = ExternalProxy(7890);
  ASSERT_TRUE(ActualProxySnapshot::Apply(external));
  ProxyPlugin plugin;
  EXPECT_TRUE(Succeeded(InvokeDetailed(plugin, "StopProxyDetailed", {
      {EncodableValue("expectedPort"), EncodableValue(7890)}})));
  EXPECT_EQ(ActualProxySnapshot::Read(), external);
  auto legacy = InvokeProxy(plugin, "StopProxy", {});
  ASSERT_EQ(legacy.wait_for(std::chrono::seconds(30)), std::future_status::ready);
  EXPECT_TRUE(std::get<bool>(legacy.get()));
  EXPECT_EQ(ActualProxySnapshot::Read(), external);
}

TEST(ProxyPlugin, NoSessionStopPreservesExternalDifferentPortProxy) {
  if (!AllowProxyMutation()) GTEST_SKIP() << "Requires an isolated CI account";
  ActualProxySnapshot original;
  ASSERT_TRUE(original.captured());
  const auto external = ExternalProxy(17890);
  ASSERT_TRUE(ActualProxySnapshot::Apply(external));
  ProxyPlugin plugin;
  EXPECT_TRUE(Succeeded(InvokeDetailed(plugin, "StopProxyDetailed", {
      {EncodableValue("expectedPort"), EncodableValue(7890)}})));
  EXPECT_EQ(ActualProxySnapshot::Read(), external);
}

TEST(ProxyPlugin, NoSessionStopWithoutExpectedPortPreservesExternalProxy) {
  if (!AllowProxyMutation()) GTEST_SKIP() << "Requires an isolated CI account";
  ActualProxySnapshot original;
  ASSERT_TRUE(original.captured());
  const auto external = ExternalProxy(7890);
  ASSERT_TRUE(ActualProxySnapshot::Apply(external));
  ProxyPlugin plugin;
  EXPECT_TRUE(Succeeded(InvokeDetailed(plugin, "StopProxyDetailed")));
  EXPECT_EQ(ActualProxySnapshot::Read(), external);
}

TEST(ProxyPlugin, OwnedSessionRestoresOriginalDespiteLatestUiPort) {
  if (!AllowProxyMutation()) GTEST_SKIP() << "Requires an isolated CI account";
  ActualProxySnapshot snapshot;
  ASSERT_TRUE(snapshot.captured());
  const settings::ConnectionConfiguration original{
      PROXY_TYPE_DIRECT | PROXY_TYPE_AUTO_PROXY_URL | PROXY_TYPE_AUTO_DETECT,
      L"corp.example:8080", L"*.corp;<local>", L"https://corp.example/proxy.pac"};
  ASSERT_TRUE(ActualProxySnapshot::Apply(original));
  ProxyPlugin plugin;
  EXPECT_TRUE(Succeeded(InvokeDetailed(plugin, "StartProxyDetailed", {
      {EncodableValue("port"), EncodableValue(7890)},
      {EncodableValue("bypassDomain"), EncodableValue(EncodableList{EncodableValue("localhost")})}})));
  EXPECT_TRUE(Succeeded(InvokeDetailed(plugin, "StopProxyDetailed", {
      {EncodableValue("expectedPort"), EncodableValue(7891)}})));
  EXPECT_EQ(ActualProxySnapshot::Read(), original);
  EXPECT_TRUE(Succeeded(InvokeDetailed(plugin, "StopProxyDetailed")));
  EXPECT_EQ(ActualProxySnapshot::Read(), original);

  EXPECT_TRUE(Succeeded(InvokeDetailed(plugin, "StartProxyDetailed", {
      {EncodableValue("port"), EncodableValue(7890)},
      {EncodableValue("bypassDomain"), EncodableValue(EncodableList{EncodableValue("localhost")})}})));
  const settings::ConnectionConfiguration external{
      PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY | PROXY_TYPE_AUTO_PROXY_URL | PROXY_TYPE_AUTO_DETECT,
      L"external.example:17890", L"*.external;<local>", L"https://external.example/proxy.pac"};
  ASSERT_TRUE(ActualProxySnapshot::Apply(external));
  EXPECT_TRUE(Succeeded(InvokeDetailed(plugin, "StartProxyDetailed", {
      {EncodableValue("port"), EncodableValue(7890)},
      {EncodableValue("bypassDomain"), EncodableValue(EncodableList{EncodableValue("localhost")})}})));
  EXPECT_TRUE(Succeeded(InvokeDetailed(plugin, "StopProxyDetailed", {
      {EncodableValue("expectedPort"), EncodableValue(7891)}})));
  EXPECT_EQ(ActualProxySnapshot::Read(), external);
  EXPECT_TRUE(Succeeded(InvokeDetailed(plugin, "StopProxyDetailed")));
  EXPECT_EQ(ActualProxySnapshot::Read(), external);
}

TEST(ProxyPlugin, OwnedStopPreservesSamePortForeignTakeover) {
  if (!AllowProxyMutation()) GTEST_SKIP() << "Requires an isolated CI account";
  ActualProxySnapshot original;
  ASSERT_TRUE(original.captured());
  ASSERT_TRUE(ActualProxySnapshot::Apply({PROXY_TYPE_DIRECT, L"", L"", L""}));
  ProxyPlugin plugin;
  EXPECT_TRUE(Succeeded(InvokeDetailed(plugin, "StartProxyDetailed", {
      {EncodableValue("port"), EncodableValue(7890)},
      {EncodableValue("bypassDomain"), EncodableValue(EncodableList{EncodableValue("localhost")})}})));
  const auto external = ExternalProxy(7890);
  ASSERT_TRUE(ActualProxySnapshot::Apply(external));
  const auto stop = InvokeDetailed(plugin, "StopProxyDetailed");
  EXPECT_TRUE(Succeeded(stop));
  EXPECT_TRUE(std::get<bool>(stop.at(EncodableValue("restoreAbandoned"))));
  EXPECT_EQ(ActualProxySnapshot::Read(), external);
}

TEST(ProxyPlugin, UnchangedStartDoesNotAcquireExternalProxy) {
  if (!AllowProxyMutation()) GTEST_SKIP() << "Requires an isolated CI account";
  ActualProxySnapshot original;
  ASSERT_TRUE(original.captured());
  const settings::ConnectionConfiguration external{
      PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY, L"127.0.0.1:7890", L"localhost", L""};
  ASSERT_TRUE(ActualProxySnapshot::Apply(external));
  ProxyPlugin plugin;
  const auto start = InvokeDetailed(plugin, "StartProxyDetailed", {
      {EncodableValue("port"), EncodableValue(7890)},
      {EncodableValue("bypassDomain"), EncodableValue(EncodableList{EncodableValue("localhost")})}});
  EXPECT_TRUE(Succeeded(start));
  EXPECT_TRUE(std::get<bool>(start.at(EncodableValue("writeSkipped"))));
  EXPECT_TRUE(Succeeded(InvokeDetailed(plugin, "StopProxyDetailed")));
  EXPECT_EQ(ActualProxySnapshot::Read(), external);
}

TEST(ProxyPlugin, StaleRepairClearsOnlyDeadExpectedEndpoint) {
  if (!AllowProxyMutation()) GTEST_SKIP() << "Requires an isolated CI account";
  ActualProxySnapshot original;
  ASSERT_TRUE(original.captured());
  LoopbackListener listener;
  ASSERT_GT(listener.port(), 0);
  const auto external = ExternalProxy(listener.port());
  listener.Close();
  ASSERT_TRUE(ActualProxySnapshot::Apply(external));
  ProxyPlugin plugin;
  EXPECT_TRUE(Succeeded(InvokeDetailed(plugin, "RepairStaleProxyDetailed", {
      {EncodableValue("expectedPort"), EncodableValue(listener.port())}})));
  auto disabled = external;
  disabled.flags = PROXY_TYPE_DIRECT;
  EXPECT_EQ(ActualProxySnapshot::Read(), disabled);
}

TEST(ProxyPlugin, StaleRepairPreservesLiveListener) {
  if (!AllowProxyMutation()) GTEST_SKIP() << "Requires an isolated CI account";
  ActualProxySnapshot original;
  ASSERT_TRUE(original.captured());
  LoopbackListener listener;
  ASSERT_GT(listener.port(), 0);
  const auto external = ExternalProxy(listener.port());
  ASSERT_TRUE(ActualProxySnapshot::Apply(external));
  ProxyPlugin plugin;
  const auto result = InvokeDetailed(plugin, "RepairStaleProxyDetailed", {
      {EncodableValue("expectedPort"), EncodableValue(listener.port())}});
  EXPECT_TRUE(Succeeded(result));
  EXPECT_EQ(std::get<std::string>(result.at(EncodableValue("stage"))), "skipped_active_listener");
  EXPECT_EQ(ActualProxySnapshot::Read(), external);
}

TEST(ProxyPlugin, StaleRepairPreservesIpv6OnlyLiveListener) {
  if (!AllowProxyMutation()) GTEST_SKIP() << "Requires an isolated CI account";
  ActualProxySnapshot original;
  ASSERT_TRUE(original.captured());
  LoopbackListener listener(true);
  ASSERT_GT(listener.port(), 0) << "The isolated Windows account must support IPv6 loopback listeners";
  const auto external = ExternalProxy(listener.port());
  ASSERT_TRUE(ActualProxySnapshot::Apply(external));
  ProxyPlugin plugin;
  const auto result = InvokeDetailed(plugin, "RepairStaleProxyDetailed", {
      {EncodableValue("expectedPort"), EncodableValue(listener.port())}});
  EXPECT_TRUE(Succeeded(result));
  EXPECT_EQ(std::get<std::string>(result.at(EncodableValue("stage"))), "skipped_active_listener");
  EXPECT_EQ(ActualProxySnapshot::Read(), external);
}

TEST(ProxyPlugin, StaleRepairPreservesDifferentEndpoint) {
  if (!AllowProxyMutation()) GTEST_SKIP() << "Requires an isolated CI account";
  ActualProxySnapshot original;
  ASSERT_TRUE(original.captured());
  LoopbackListener listener;
  ASSERT_GT(listener.port(), 0);
  const auto external = ExternalProxy(7890);
  listener.Close();
  ASSERT_TRUE(ActualProxySnapshot::Apply(external));
  ProxyPlugin plugin;
  EXPECT_TRUE(Succeeded(InvokeDetailed(plugin, "RepairStaleProxyDetailed", {
      {EncodableValue("expectedPort"), EncodableValue(listener.port())}})));
  EXPECT_EQ(ActualProxySnapshot::Read(), external);
}

TEST(ProxyPlugin, StaleRepairRejectsMissingOrInvalidExpectedPort) {
  for (const auto& arguments : {EncodableMap{}, EncodableMap{
      {EncodableValue("expectedPort"), EncodableValue(0)}}}) {
    ProxyPlugin plugin;
    std::string error_code;
    std::string error_message;
    plugin.HandleMethodCall(
        MethodCall("RepairStaleProxyDetailed", std::make_unique<EncodableValue>(arguments)),
        std::make_unique<MethodResultFunctions<>>(
            [&error_code](const EncodableValue*) { error_code = "unexpected_success"; },
            [&](const std::string& code, const std::string& message, const EncodableValue*) {
              error_code = code;
              error_message = message;
            },
            [&error_code]() { error_code = "not_implemented"; }));
    EXPECT_EQ(error_code, "bad_args");
    EXPECT_EQ(error_message, "RepairStaleProxyDetailed requires a valid expectedPort");
  }
}

TEST(ProxySettings, NormalizesWindowsIpv6LoopbackBypass) {
  EXPECT_EQ(settings::NormalizeBypassList(L"localhost;::1;10.*"),
            L"localhost;[::1];10.*");
  EXPECT_EQ(settings::NormalizeBypassList(L"::1"), L"[::1]");
  EXPECT_EQ(settings::NormalizeBypassList(L"; ::1 ;[::1];;"),
            L"; [::1] ;[::1];;");
  EXPECT_EQ(settings::NormalizeBypassList(L""), L"");
  EXPECT_EQ(settings::NormalizeBypassList(L"<local>;*.lan;172.16.*"),
            L"<local>;*.lan;172.16.*");
  EXPECT_EQ(settings::NormalizeBypassList(L"[::1]:8080;example.com:443"),
            L"[::1]:8080;example.com:443");
}

TEST(ProxySettings, InvalidParameterRetriesTypedAnsiOptions) {
  INTERNET_PER_CONN_OPTIONW options[3] = {};
  options[0].dwOption = INTERNET_PER_CONN_FLAGS;
  options[0].Value.dwValue = PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY;
  options[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
  options[1].Value.pszValue = const_cast<wchar_t*>(L"127.0.0.1:7890");
  options[2].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
  options[2].Value.pszValue = const_cast<wchar_t*>(L"localhost;10.*");
  INTERNET_PER_CONN_OPTION_LISTW list = {};
  list.dwSize = sizeof(list);
  list.dwOptionCount = 3;
  list.pOptions = options;
  DWORD error = 0;
  bool fallback = false;
  const bool success = settings::SetConnectionOptions(
      list, nullptr, error, fallback,
      [](HINTERNET, DWORD, LPVOID, DWORD) -> BOOL {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
      },
      [](HINTERNET handle, DWORD option, LPVOID buffer, DWORD size) -> BOOL {
        const auto* request = static_cast<INTERNET_PER_CONN_OPTION_LISTA*>(buffer);
        EXPECT_EQ(handle, nullptr);
        EXPECT_EQ(option, INTERNET_OPTION_PER_CONNECTION_OPTION);
        EXPECT_EQ(size, sizeof(*request));
        EXPECT_EQ(request->dwSize, sizeof(*request));
        EXPECT_EQ(request->pszConnection, nullptr);
        EXPECT_EQ(request->dwOptionCount, 3u);
        EXPECT_EQ(request->pOptions[0].Value.dwValue,
                  DWORD(PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY));
        EXPECT_STREQ(request->pOptions[1].Value.pszValue, "127.0.0.1:7890");
        EXPECT_STREQ(request->pOptions[2].Value.pszValue, "localhost;10.*");
        return TRUE;
      });
  EXPECT_TRUE(success);
  EXPECT_TRUE(fallback);
  EXPECT_EQ(error, ERROR_SUCCESS);
}

TEST(ProxySettings, DoesNotBypassAccessDeniedWithAnotherWrite) {
  INTERNET_PER_CONN_OPTION_LISTW list = {};
  DWORD error = 0;
  bool fallback = false;
  EXPECT_FALSE(settings::SetConnectionOptions(
      list, nullptr, error, fallback,
      [](HINTERNET, DWORD, LPVOID, DWORD) -> BOOL {
        SetLastError(ERROR_ACCESS_DENIED);
        return FALSE;
      },
      [](HINTERNET, DWORD, LPVOID, DWORD) -> BOOL {
        ADD_FAILURE() << "Access denied must not trigger fallback";
        return TRUE;
      }));
  EXPECT_FALSE(fallback);
  EXPECT_EQ(error, ERROR_ACCESS_DENIED);
}

TEST(ProxySettings, WideSuccessDoesNotInvokeFallback) {
  INTERNET_PER_CONN_OPTION_LISTW list = {};
  DWORD error = ERROR_INVALID_PARAMETER;
  bool fallback = false;
  EXPECT_TRUE(settings::SetConnectionOptions(
      list, nullptr, error, fallback,
      [](HINTERNET, DWORD, LPVOID, DWORD) -> BOOL { return TRUE; },
      [](HINTERNET, DWORD, LPVOID, DWORD) -> BOOL {
        ADD_FAILURE() << "A successful write must not be repeated";
        return FALSE;
      }));
  EXPECT_FALSE(fallback);
  EXPECT_EQ(error, ERROR_SUCCESS);
}

TEST(ProxySettings, ReportsAnsiFailureWithoutRegistryFallback) {
  INTERNET_PER_CONN_OPTION_LISTW list = {};
  DWORD error = 0;
  bool fallback = false;
  EXPECT_FALSE(settings::SetConnectionOptions(
      list, nullptr, error, fallback,
      [](HINTERNET, DWORD, LPVOID, DWORD) -> BOOL {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
      },
      [](HINTERNET, DWORD, LPVOID, DWORD) -> BOOL {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
      }));
  EXPECT_TRUE(fallback);
  EXPECT_EQ(error, ERROR_INVALID_PARAMETER);
}

TEST(ProxySettings, ReadsActualConnectionFlagsAndServer) {
  bool enabled = false;
  std::wstring server;
  DWORD error = 87;
  EXPECT_TRUE(settings::QueryProxy(
      enabled, server, error,
      [](HINTERNET, DWORD option, LPVOID buffer, LPDWORD) -> BOOL {
        auto* request = static_cast<INTERNET_PER_CONN_OPTION_LISTA*>(buffer);
        EXPECT_EQ(option, INTERNET_OPTION_PER_CONNECTION_OPTION);
        EXPECT_EQ(request->pOptions[0].dwOption, INTERNET_PER_CONN_FLAGS_UI);
        request->pOptions[0].Value.dwValue = PROXY_TYPE_PROXY | PROXY_TYPE_DIRECT;
        const char value[] = "127.0.0.1:7890";
        auto* memory = static_cast<char*>(GlobalAlloc(GPTR, sizeof(value)));
        if (memory == nullptr) return FALSE;
        std::memcpy(memory, value, sizeof(value));
        request->pOptions[1].Value.pszValue = memory;
        return TRUE;
      }));
  EXPECT_TRUE(enabled);
  EXPECT_EQ(server, L"127.0.0.1:7890");
  EXPECT_EQ(error, ERROR_SUCCESS);
}

TEST(ProxySettings, DisabledConnectionIsNotMistakenForEnabled) {
  bool enabled = true;
  std::wstring server = L"127.0.0.1:7890";
  DWORD error = 0;
  EXPECT_TRUE(settings::QueryProxy(
      enabled, server, error,
      [](HINTERNET, DWORD, LPVOID buffer, LPDWORD) -> BOOL {
        auto* request = static_cast<INTERNET_PER_CONN_OPTION_LISTA*>(buffer);
        request->pOptions[0].Value.dwValue = PROXY_TYPE_DIRECT;
        return TRUE;
      }));
  EXPECT_FALSE(enabled);
  EXPECT_TRUE(server.empty());
}

TEST(ProxySettings, QueryFailureDoesNotBecomeSuccess) {
  bool enabled = false;
  std::wstring server;
  DWORD error = 0;
  EXPECT_FALSE(settings::QueryProxy(
      enabled, server, error,
      [](HINTERNET, DWORD, LPVOID, LPDWORD) -> BOOL {
        SetLastError(ERROR_ACCESS_DENIED);
        return FALSE;
      }));
  EXPECT_EQ(error, ERROR_ACCESS_DENIED);
}

TEST(ProxySettings, UnsupportedUiFlagsFallBackToConnectionFlags) {
  bool enabled = false;
  std::wstring server;
  DWORD error = 0;
  EXPECT_TRUE(settings::QueryProxy(
      enabled, server, error,
      [](HINTERNET, DWORD, LPVOID buffer, LPDWORD) -> BOOL {
        auto* request = static_cast<INTERNET_PER_CONN_OPTION_LISTA*>(buffer);
        if (request->pOptions[0].dwOption == INTERNET_PER_CONN_FLAGS_UI) {
          SetLastError(ERROR_INVALID_PARAMETER);
          return FALSE;
        }
        EXPECT_EQ(request->pOptions[0].dwOption, INTERNET_PER_CONN_FLAGS);
        request->pOptions[0].Value.dwValue = PROXY_TYPE_DIRECT;
        return TRUE;
      }));
  EXPECT_FALSE(enabled);
  EXPECT_EQ(error, ERROR_SUCCESS);
}

}  // namespace test
}  // namespace proxy
