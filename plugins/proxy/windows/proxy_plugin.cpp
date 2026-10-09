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

using ProxyOperationDetails = proxy::settings::SessionOperationDetails;

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

bool EnumerateConnections(std::vector<std::wstring>& names, uint32_t& error)
{
  DWORD size = 0;
  DWORD count = 0;
  auto status = RasEnumEntriesW(nullptr, nullptr, nullptr, &size, &count);
  if (status == ERROR_SUCCESS && count == 0)
  {
    error = ERROR_SUCCESS;
    return true;
  }
  if (status != ERROR_BUFFER_TOO_SMALL || count == 0)
  {
    error = status;
    return false;
  }
  std::vector<RASENTRYNAMEW> entries(count);
  for (auto& entry : entries) entry.dwSize = sizeof(entry);
  status = RasEnumEntriesW(nullptr, nullptr, entries.data(), &size, &count);
  error = status;
  if (status != ERROR_SUCCESS) return false;
  for (DWORD i = 0; i < count; ++i) names.emplace_back(entries[i].szEntryName);
  return true;
}

bool ReadConnection(const std::wstring& name,
                    proxy::settings::ConnectionConfiguration& configuration,
                    uint32_t& error)
{
  DWORD native_error = ERROR_SUCCESS;
  if (!proxy::settings::QueryConnection(name, configuration, native_error))
  {
    error = native_error;
    return false;
  }
  if (name.empty())
  {
    ProxyReadback registry;
    if (!ReadProxyRegistry(registry, native_error))
    {
      error = native_error;
      return false;
    }
    if (registry.enabled != configuration.HasManualProxy() ||
        (registry.enabled && registry.server != configuration.server))
    {
      error = ERROR_INVALID_DATA;
      return false;
    }
  }
  error = ERROR_SUCCESS;
  return true;
}

bool WriteConnection(const std::wstring& name,
                     const proxy::settings::ConnectionConfiguration& configuration,
                     uint32_t& error, bool& fallback)
{
  DWORD native_error = ERROR_SUCCESS;
  const bool result = proxy::settings::WriteConnection(name, configuration,
                                                       native_error, fallback);
  error = native_error;
  return result;
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

proxy::settings::ConnectionBackend NativeBackend()
{
  return {EnumerateConnections, ReadConnection, WriteConnection, NotifySettingsChanged};
}

ProxyOperationDetails ApplyProxy(proxy::settings::ProxySession& session,
                                int port,
                                const flutter::EncodableList& bypassDomain)
{
  proxy::settings::ConnectionConfiguration desired;
  desired.flags = PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY;
  desired.server = Utf8ToWide("127.0.0.1:" + std::to_string(port));
  desired.bypass = BuildBypassList(bypassDomain);
  return session.Start(desired, NativeBackend());
}

ProxyOperationDetails StopProxy(proxy::settings::ProxySession& session,
                               const int* expectedPort)
{
  return session.Stop(expectedPort == nullptr ? std::optional<int>()
                                              : std::make_optional(*expectedPort),
                      NativeBackend());
}

ProxyOperationDetails InspectProxy(const int expectedPort)
{
  ProxyOperationDetails details;
  details.operation = "inspect";
  ProxyReadback readback;
  DWORD error = ERROR_SUCCESS;
  if (!ReadProxySettings(readback, error))
  {
    details.stage = "readback";
    details.errorCode = error;
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
       flutter::EncodableValue(details.message)},
      {flutter::EncodableValue("writeSkipped"),
       flutter::EncodableValue(details.writeSkipped)},
      {flutter::EncodableValue("restoreAbandoned"),
       flutter::EncodableValue(details.restoreAbandoned)},
      {flutter::EncodableValue("snapshotCount"),
       flutter::EncodableValue(details.snapshotCount)},
      {flutter::EncodableValue("restoredCount"),
       flutter::EncodableValue(details.restoredCount)},
      {flutter::EncodableValue("skippedCount"),
       flutter::EncodableValue(details.skippedCount)},
      {flutter::EncodableValue("pendingCleanup"),
       flutter::EncodableValue(details.pendingCleanup)}};
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
  settings::ProxySession session;
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
    if (!state->session.HasPendingCleanup()) return;
    StopProxy(state->session, nullptr);
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
          const auto details = StopProxy(state->session, port ? &*port : nullptr);
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
          const auto details = ApplyProxy(state->session, port, bypass);
          return detailed ? EncodeDetails(details)
                          : flutter::EncodableValue(details.success);
        },
        std::move(result));
    return;
  }

  result->NotImplemented();
}

}  // namespace proxy
