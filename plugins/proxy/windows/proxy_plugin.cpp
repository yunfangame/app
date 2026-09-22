#include "proxy_plugin.h"

#include <windows.h>

#include <WinInet.h>
#include <Ras.h>
#include <RasError.h>
#include "proxy_settings.h"
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <exception>
#include <memory>
#include <string>
#include <vector>

#pragma comment(lib, "wininet")
#pragma comment(lib, "Rasapi32")
#pragma comment(lib, "Advapi32")

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

namespace
{

constexpr int kMinProxyPort = 1;
constexpr int kMaxProxyPort = 65535;
constexpr wchar_t kInternetSettingsKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings";

struct ProxyReadback
{
  bool enabled = false;
  std::wstring server;
};

struct ProxyOperationDetails
{
  bool success = false;
  std::string operation;
  std::string stage;
  DWORD errorCode = ERROR_SUCCESS;
  std::wstring connectionName;
  bool enabled = false;
  std::wstring server;
  bool fallbackUsed = false;
  int rasFailureCount = 0;
  std::string message;
};

std::wstring Utf8ToWide(const std::string& value)
{
  if (value.empty())
  {
    return {};
  }
  const int size = MultiByteToWideChar(
      CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0)
  {
    return std::wstring(value.begin(), value.end());
  }
  std::wstring result(size, L'\0');
  MultiByteToWideChar(
      CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()),
      result.data(), size);
  return result;
}

std::string WideToUtf8(const std::wstring& value)
{
  if (value.empty())
  {
    return {};
  }
  const int size = WideCharToMultiByte(
      CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), nullptr, 0,
      nullptr, nullptr);
  if (size <= 0)
  {
    return {};
  }
  std::string result(size, '\0');
  WideCharToMultiByte(
      CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()),
      result.data(), size, nullptr, nullptr);
  return result;
}

std::wstring BuildBypassList(const flutter::EncodableList& bypassDomain)
{
  std::wstring bypassList;
  for (const auto& domain : bypassDomain)
  {
    const auto& value = std::get<std::string>(domain);
    if (!bypassList.empty())
    {
      bypassList += L";";
    }
    bypassList += Utf8ToWide(value);
  }
  return proxy::settings::NormalizeBypassList(bypassList);
}

bool IsStringList(const flutter::EncodableList& values)
{
  return std::all_of(
      values.begin(), values.end(), [](const auto& value)
      {
        return std::holds_alternative<std::string>(value);
      });
}

bool ReadStringValue(
    HKEY key,
    const wchar_t* name,
    std::wstring& value,
    DWORD& errorCode)
{
  DWORD type = 0;
  DWORD size = 0;
  auto status = RegQueryValueExW(key, name, nullptr, &type, nullptr, &size);
  if (status == ERROR_FILE_NOT_FOUND)
  {
    value.clear();
    return true;
  }
  if (status != ERROR_SUCCESS ||
      (type != REG_SZ && type != REG_EXPAND_SZ))
  {
    errorCode = status == ERROR_SUCCESS ? ERROR_INVALID_DATA : status;
    return false;
  }
  std::vector<wchar_t> buffer(size / sizeof(wchar_t) + 1, L'\0');
  status = RegQueryValueExW(
      key, name, nullptr, &type,
      reinterpret_cast<LPBYTE>(buffer.data()), &size);
  if (status != ERROR_SUCCESS)
  {
    errorCode = status;
    return false;
  }
  value.assign(buffer.data());
  return true;
}

bool ReadProxyRegistry(ProxyReadback& readback, DWORD& errorCode)
{
  HKEY key = nullptr;
  auto status = RegOpenKeyExW(
      HKEY_CURRENT_USER, kInternetSettingsKey, 0, KEY_QUERY_VALUE, &key);
  if (status != ERROR_SUCCESS)
  {
    errorCode = status;
    return false;
  }
  DWORD enabled = 0;
  DWORD type = 0;
  DWORD size = sizeof(enabled);
  status = RegQueryValueExW(
      key, L"ProxyEnable", nullptr, &type,
      reinterpret_cast<LPBYTE>(&enabled), &size);
  if (status == ERROR_FILE_NOT_FOUND)
  {
    enabled = 0;
  }
  else if (status != ERROR_SUCCESS || type != REG_DWORD)
  {
    RegCloseKey(key);
    errorCode = status == ERROR_SUCCESS ? ERROR_INVALID_DATA : status;
    return false;
  }
  readback.enabled = enabled != 0;
  const bool serverRead =
      ReadStringValue(key, L"ProxyServer", readback.server, errorCode);
  RegCloseKey(key);
  return serverRead;
}

bool ReadProxySettings(ProxyReadback& readback, DWORD& errorCode)
{
  if (!proxy::settings::QueryProxy(
          readback.enabled, readback.server, errorCode))
  {
    return false;
  }
  ProxyReadback registry;
  if (!ReadProxyRegistry(registry, errorCode)) return false;
  if (registry.enabled != readback.enabled ||
      (readback.enabled && registry.server != readback.server))
  {
    errorCode = ERROR_INVALID_DATA;
    return false;
  }
  errorCode = ERROR_SUCCESS;
  return true;
}

bool SetOptionsForConnection(
    INTERNET_PER_CONN_OPTION_LISTW& list,
    LPWSTR connection,
    DWORD& errorCode,
    bool& fallbackUsed)
{
  return proxy::settings::SetConnectionOptions(
      list, connection, errorCode, fallbackUsed);
}

void ApplyOptionsToRasConnections(
    INTERNET_PER_CONN_OPTION_LISTW& list,
    ProxyOperationDetails& details)
{
  DWORD size = 0;
  DWORD count = 0;
  auto ret = RasEnumEntriesW(nullptr, nullptr, nullptr, &size, &count);
  if (ret == ERROR_BUFFER_TOO_SMALL && count > 0)
  {
    std::vector<RASENTRYNAMEW> entries(count);
    for (auto& entry : entries)
    {
      entry.dwSize = sizeof(RASENTRYNAMEW);
    }
    ret = RasEnumEntriesW(nullptr, nullptr, entries.data(), &size, &count);
    if (ret == ERROR_SUCCESS)
    {
      for (DWORD i = 0; i < count; i++)
      {
        DWORD errorCode = ERROR_SUCCESS;
        if (!SetOptionsForConnection(
                list, entries[i].szEntryName, errorCode, details.fallbackUsed))
        {
          details.rasFailureCount++;
          if (details.connectionName.empty())
          {
            details.connectionName = entries[i].szEntryName;
            details.errorCode = errorCode;
          }
        }
      }
    }
    else
    {
      details.rasFailureCount++;
      details.connectionName = L"RAS_ENUM";
      details.errorCode = ret;
    }
  }
  else if (ret != ERROR_SUCCESS)
  {
    details.rasFailureCount++;
    details.connectionName = L"RAS_ENUM";
    details.errorCode = ret;
  }
}

bool NotifySettingsChanged(ProxyOperationDetails& details)
{
  if (InternetSetOption(
          nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0) == FALSE)
  {
    details.stage = "notify_settings_changed";
    details.errorCode = GetLastError();
    return false;
  }
  if (InternetSetOption(
          nullptr, INTERNET_OPTION_REFRESH, nullptr, 0) == FALSE)
  {
    details.stage = "notify_refresh";
    details.errorCode = GetLastError();
    return false;
  }
  return true;
}

bool MatchesExpectedProxy(
    const ProxyReadback& readback,
    bool enabled,
    const std::wstring& server)
{
  return readback.enabled == enabled &&
      (!enabled || readback.server == server);
}

ProxyOperationDetails ApplyProxy(
    bool enabled,
    int port,
    const flutter::EncodableList& bypassDomain)
{
  ProxyOperationDetails details;
  details.operation = enabled ? "start" : "stop";
  const auto server = enabled
      ? Utf8ToWide("127.0.0.1:" + std::to_string(port))
      : std::wstring();
  const auto bypassList = BuildBypassList(bypassDomain);
  std::vector<INTERNET_PER_CONN_OPTIONW> options(enabled ? 3 : 1);

  INTERNET_PER_CONN_OPTION_LISTW list = {};
  list.dwSize = sizeof(list);
  list.dwOptionCount = static_cast<DWORD>(options.size());
  list.pOptions = options.data();

  options[0].dwOption = INTERNET_PER_CONN_FLAGS;
  options[0].Value.dwValue = enabled
      ? PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY
      : PROXY_TYPE_DIRECT;
  if (enabled)
  {
    options[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
    options[1].Value.pszValue = const_cast<LPWSTR>(server.c_str());
    options[2].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
    options[2].Value.pszValue = const_cast<LPWSTR>(bypassList.c_str());
  }

  DWORD applyError = ERROR_SUCCESS;
  const bool defaultApplied =
      SetOptionsForConnection(list, nullptr, applyError, details.fallbackUsed);
  if (!defaultApplied)
  {
    details.stage = "apply_default";
    details.errorCode = applyError;
    return details;
  }
  ApplyOptionsToRasConnections(list, details);

  if (!NotifySettingsChanged(details))
  {
    return details;
  }

  ProxyReadback readback;
  DWORD readError = ERROR_SUCCESS;
  const bool readSucceeded = ReadProxySettings(readback, readError);

  details.enabled = readback.enabled;
  details.server = readback.server;
  if (!readSucceeded)
  {
    details.stage = "readback";
    details.errorCode = readError;
    return details;
  }
  if (!MatchesExpectedProxy(readback, enabled, server))
  {
    details.stage = "readback_mismatch";
    details.errorCode = readError;
    return details;
  }

  if (details.rasFailureCount > 0)
  {
    details.stage = "apply_ras";
    return details;
  }
  details.success = true;
  details.errorCode = ERROR_SUCCESS;
  details.stage = details.fallbackUsed
      ? "verified_ansi_fallback"
      : "verified";
  return details;
}

ProxyOperationDetails StopProxy(const int* expectedPort)
{
  if (expectedPort != nullptr)
  {
    ProxyOperationDetails details;
    details.operation = "stop";
    ProxyReadback readback;
    if (!ReadProxySettings(readback, details.errorCode))
    {
      details.stage = "readback";
      return details;
    }
    details.enabled = readback.enabled;
    details.server = readback.server;
    if (!readback.enabled)
    {
      details.success = true;
      details.stage = "already_disabled";
      return details;
    }
    const auto expected = Utf8ToWide(
        "127.0.0.1:" + std::to_string(*expectedPort));
    if (readback.server != expected)
    {
      details.success = true;
      details.stage = "skipped_foreign_proxy";
      return details;
    }
  }
  const flutter::EncodableList empty;
  return ApplyProxy(false, 0, empty);
}

ProxyOperationDetails InspectProxy(const int expectedPort)
{
  ProxyOperationDetails details;
  details.operation = "inspect";
  ProxyReadback readback;
  if (!ReadProxySettings(readback, details.errorCode))
  {
    details.stage = "readback";
    return details;
  }
  details.enabled = readback.enabled;
  details.server = readback.server;
  const auto expected = Utf8ToWide(
      "127.0.0.1:" + std::to_string(expectedPort));
  details.success = readback.enabled && readback.server == expected;
  details.stage = details.success ? "verified" : "readback_mismatch";
  return details;
}

flutter::EncodableValue EncodeDetails(const ProxyOperationDetails& details)
{
  flutter::EncodableMap value = {
      {flutter::EncodableValue("success"),
       flutter::EncodableValue(details.success)},
      {flutter::EncodableValue("operation"),
       flutter::EncodableValue(details.operation)},
      {flutter::EncodableValue("stage"),
       flutter::EncodableValue(details.stage)},
      {flutter::EncodableValue("errorCode"),
       flutter::EncodableValue(static_cast<int64_t>(details.errorCode))},
      {flutter::EncodableValue("connectionName"),
       flutter::EncodableValue(WideToUtf8(details.connectionName))},
      {flutter::EncodableValue("enabled"),
       flutter::EncodableValue(details.enabled)},
      {flutter::EncodableValue("server"),
       flutter::EncodableValue(WideToUtf8(details.server))},
      {flutter::EncodableValue("fallbackUsed"),
       flutter::EncodableValue(details.fallbackUsed)},
      {flutter::EncodableValue("rasFailureCount"),
       flutter::EncodableValue(details.rasFailureCount)},
      {flutter::EncodableValue("message"),
       flutter::EncodableValue(details.message)}};
  return flutter::EncodableValue(std::move(value));
}

bool ParseStartArguments(
    const flutter::MethodCall<flutter::EncodableValue>& methodCall,
    const int*& port,
    const flutter::EncodableList*& bypassDomain,
    std::string& errorMessage)
{
  auto* arguments =
      std::get_if<flutter::EncodableMap>(methodCall.arguments());
  if (arguments == nullptr)
  {
    errorMessage = "StartProxy requires argument map";
    return false;
  }
  auto portIt = arguments->find(flutter::EncodableValue("port"));
  auto bypassDomainIt =
      arguments->find(flutter::EncodableValue("bypassDomain"));
  if (portIt == arguments->end() || bypassDomainIt == arguments->end())
  {
    errorMessage = "StartProxy requires port and bypassDomain";
    return false;
  }
  port = std::get_if<int>(&portIt->second);
  bypassDomain = std::get_if<flutter::EncodableList>(&bypassDomainIt->second);
  if (port == nullptr || bypassDomain == nullptr)
  {
    errorMessage = "StartProxy argument types are invalid";
    return false;
  }
  if (*port < kMinProxyPort || *port > kMaxProxyPort)
  {
    errorMessage = "StartProxy port must be between 1 and 65535";
    return false;
  }
  if (!IsStringList(*bypassDomain))
  {
    errorMessage = "StartProxy bypassDomain must contain only strings";
    return false;
  }
  return true;
}

bool ParseOptionalExpectedPort(
    const flutter::MethodCall<flutter::EncodableValue>& methodCall,
    const int*& expectedPort,
    std::string& errorMessage)
{
  if (methodCall.arguments() == nullptr)
  {
    return true;
  }
  auto* arguments =
      std::get_if<flutter::EncodableMap>(methodCall.arguments());
  if (arguments == nullptr)
  {
    errorMessage = "StopProxy arguments must be a map";
    return false;
  }
  const auto expectedPortIt =
      arguments->find(flutter::EncodableValue("expectedPort"));
  if (expectedPortIt == arguments->end())
  {
    return true;
  }
  expectedPort = std::get_if<int>(&expectedPortIt->second);
  if (expectedPort == nullptr ||
      *expectedPort < kMinProxyPort || *expectedPort > kMaxProxyPort)
  {
    errorMessage = "StopProxy expectedPort is invalid";
    return false;
  }
  return true;
}

}  // namespace

namespace proxy
{

struct ProxyPlugin::ProxyState
{
  std::optional<int> applied_port;
};

void ProxyPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar)
{
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "proxy",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<ProxyPlugin>(registrar);

  channel->SetMethodCallHandler(
      [pluginPointer = plugin.get()](const auto& call, auto result)
      {
        pluginPointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

ProxyPlugin::ProxyPlugin() : state_(std::make_shared<ProxyState>()) {}

ProxyPlugin::ProxyPlugin(flutter::PluginRegistrarWindows* registrar)
    : ProxyPlugin()
{
  registrar_ = registrar;
  window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [this](HWND window, UINT message, WPARAM wparam, LPARAM lparam)
      {
        return HandleWindowProc(window, message, wparam, lparam);
      });
}

ProxyPlugin::~ProxyPlugin()
{
  Shutdown();
  if (registrar_ != nullptr)
  {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
  }
}

void ProxyPlugin::Dispatch(
    std::function<flutter::EncodableValue()> operation,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
  auto reply =
      std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
          std::move(result));
  const auto cancelled = [reply]()
  {
    reply->Error("proxy_shutdown", "The system proxy worker is shutting down");
  };
  if (!task_runner_.Post(
          [operation = std::move(operation), reply]()
          {
            flutter::EncodableValue value;
            try
            {
              value = operation();
            }
            catch (const std::exception& error)
            {
              reply->Error("proxy_operation_failed", error.what());
              return;
            }
            catch (...)
            {
              reply->Error("proxy_operation_failed", "System proxy operation failed");
              return;
            }
            reply->Success(value);
          },
          cancelled))
  {
    cancelled();
  }
}

void ProxyPlugin::Shutdown()
{
  task_runner_.Shutdown([state = state_]()
  {
    if (!state->applied_port.has_value()) return;
    const int port = *state->applied_port;
    if (StopProxy(&port).success) state->applied_port.reset();
  });
}

bool ProxyPlugin::IsSessionEnding(UINT message, WPARAM wparam)
{
  return message == WM_ENDSESSION && wparam != FALSE;
}

std::optional<int> ProxyPlugin::AppliedProxyPort(bool success, int port)
{
  return success ? std::make_optional(port) : std::nullopt;
}

std::optional<LRESULT> ProxyPlugin::HandleWindowProc(
    HWND window, UINT message, WPARAM wparam, LPARAM lparam)
{
  if (IsSessionEnding(message, wparam))
  {
    Shutdown();
    task_runner_.WaitForShutdown(std::chrono::milliseconds(2000));
  }
  return std::nullopt;
}

void ProxyPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& methodCall,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
  if (methodCall.method_name() == "StopProxy" ||
      methodCall.method_name() == "StopProxyDetailed")
  {
    const int* expectedPort = nullptr;
    std::string errorMessage;
    if (methodCall.method_name() == "StopProxyDetailed" &&
        !ParseOptionalExpectedPort(methodCall, expectedPort, errorMessage))
    {
      result->Error("bad_args", errorMessage);
      return;
    }
    const auto port = expectedPort == nullptr
        ? std::optional<int>() : std::make_optional(*expectedPort);
    const bool detailed = methodCall.method_name() == "StopProxyDetailed";
    Dispatch(
        [state = state_, port, detailed]()
        {
          const auto details = StopProxy(port ? &*port : nullptr);
          if (details.success) state->applied_port.reset();
          return detailed ? EncodeDetails(details)
                          : flutter::EncodableValue(details.success);
        },
        std::move(result));
    return;
  }

  if (methodCall.method_name() == "InspectProxy")
  {
    auto* arguments =
        std::get_if<flutter::EncodableMap>(methodCall.arguments());
    if (arguments == nullptr)
    {
      result->Error("bad_args", "InspectProxy requires argument map");
      return;
    }
    auto expectedPortIt =
        arguments->find(flutter::EncodableValue("expectedPort"));
    if (expectedPortIt == arguments->end())
    {
      result->Error("bad_args", "InspectProxy requires expectedPort");
      return;
    }
    auto* expectedPort = std::get_if<int>(&expectedPortIt->second);
    if (expectedPort == nullptr ||
        *expectedPort < kMinProxyPort || *expectedPort > kMaxProxyPort)
    {
      result->Error("bad_args", "InspectProxy expectedPort is invalid");
      return;
    }
    Dispatch(
        [port = *expectedPort]()
        {
          return EncodeDetails(InspectProxy(port));
        },
        std::move(result));
    return;
  }

  if (methodCall.method_name() == "StartProxy" ||
      methodCall.method_name() == "StartProxyDetailed")
  {
    const int* port = nullptr;
    const flutter::EncodableList* bypassDomain = nullptr;
    std::string errorMessage;
    if (!ParseStartArguments(
            methodCall, port, bypassDomain, errorMessage))
    {
      result->Error("bad_args", errorMessage);
      return;
    }
    const bool detailed = methodCall.method_name() == "StartProxyDetailed";
    Dispatch(
        [state = state_, port = *port, bypass = *bypassDomain, detailed]()
        {
          const auto details = ApplyProxy(true, port, bypass);
          state->applied_port = AppliedProxyPort(details.success, port);
          return detailed ? EncodeDetails(details)
                          : flutter::EncodableValue(details.success);
        },
        std::move(result));
    return;
  }

  result->NotImplemented();
}

}  // namespace proxy
