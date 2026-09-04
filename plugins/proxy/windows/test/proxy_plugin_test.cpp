#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>

#include <memory>
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

TEST(ProxyPlugin, DetailedStartAndStopRoundTripCurrentUserProxy) {
  if (GetEnvironmentVariableA("FENGWO_PROXY_MUTATING_TEST", nullptr, 0) == 0) {
    GTEST_SKIP() << "Requires an isolated Windows account with no existing proxy";
  }
  ProxyPlugin plugin;
  bool start_called = false;
  bool start_success = false;
  bool start_enabled = false;
  std::string start_server;
  EncodableMap start_arguments = {
      {EncodableValue("port"), EncodableValue(7890)},
      {EncodableValue("bypassDomain"),
       EncodableValue(EncodableList{EncodableValue("localhost")})}};

  plugin.HandleMethodCall(
      MethodCall(
          "StartProxyDetailed",
          std::make_unique<EncodableValue>(std::move(start_arguments))),
      std::make_unique<MethodResultFunctions<>>(
          [&start_called, &start_success, &start_enabled, &start_server](
              const EncodableValue* value) {
            start_called = true;
            const auto* map = std::get_if<EncodableMap>(value);
            if (map == nullptr) {
              return;
            }
            const auto success = map->find(EncodableValue("success"));
            const auto enabled = map->find(EncodableValue("enabled"));
            const auto server = map->find(EncodableValue("server"));
            if (success != map->end()) {
              start_success = std::get<bool>(success->second);
            }
            if (enabled != map->end()) {
              start_enabled = std::get<bool>(enabled->second);
            }
            if (server != map->end()) {
              start_server = std::get<std::string>(server->second);
            }
          },
          nullptr,
          nullptr));

  bool stop_called = false;
  bool stop_success = false;
  bool stop_enabled = true;
  EncodableMap stop_arguments = {
      {EncodableValue("expectedPort"), EncodableValue(7890)}};
  plugin.HandleMethodCall(
      MethodCall(
          "StopProxyDetailed",
          std::make_unique<EncodableValue>(std::move(stop_arguments))),
      std::make_unique<MethodResultFunctions<>>(
          [&stop_called, &stop_success, &stop_enabled](
              const EncodableValue* value) {
            stop_called = true;
            const auto* map = std::get_if<EncodableMap>(value);
            if (map == nullptr) {
              return;
            }
            const auto success = map->find(EncodableValue("success"));
            const auto enabled = map->find(EncodableValue("enabled"));
            if (success != map->end()) {
              stop_success = std::get<bool>(success->second);
            }
            if (enabled != map->end()) {
              stop_enabled = std::get<bool>(enabled->second);
            }
          },
          nullptr,
          nullptr));

  EXPECT_TRUE(start_called);
  EXPECT_TRUE(start_success);
  EXPECT_TRUE(start_enabled);
  EXPECT_EQ(start_server, "127.0.0.1:7890");
  EXPECT_TRUE(stop_called);
  EXPECT_TRUE(stop_success);
  EXPECT_FALSE(stop_enabled);
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
