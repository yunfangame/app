#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>

#include <memory>
#include <chrono>
#include <future>
#include <stdexcept>
#include <string>
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
  auto future = InvokeProxy(plugin, "InspectProxy", {
      {EncodableValue("expectedPort"), EncodableValue(7890)}});
  ASSERT_EQ(future.wait_for(std::chrono::seconds(1)), std::future_status::ready);
  try {
    future.get();
    FAIL() << "Proxy operations must be rejected after session end";
  } catch (const std::runtime_error& error) {
    EXPECT_NE(std::string(error.what()).find("proxy_shutdown"), std::string::npos);
  }
}

TEST(ProxyPlugin, DetailedStartAndStopRoundTripCurrentUserProxy) {
  if (GetEnvironmentVariableA("FENGWO_PROXY_MUTATING_TEST", nullptr, 0) == 0) {
    GTEST_SKIP() << "Requires an isolated Windows account with no existing proxy";
  }
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
