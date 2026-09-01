#include "wifi_ssid_plugin.h"

#include <windows.h>
#include <wlanapi.h>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <utility>

namespace wifi_ssid {

namespace {

constexpr int kPermissionGranted = 0;
constexpr char kChannelName[] = "wifi_ssid";
constexpr char kGetSsidMethod[] = "getSsid";
constexpr char kCheckPermissionMethod[] = "checkPermission";
constexpr char kRequestPermissionMethod[] = "requestPermission";

using WlanOpenHandleFunction =
    DWORD(WINAPI *)(DWORD, PVOID, PDWORD, PHANDLE);
using WlanCloseHandleFunction = DWORD(WINAPI *)(HANDLE, PVOID);
using WlanEnumInterfacesFunction =
    DWORD(WINAPI *)(HANDLE, PVOID, PWLAN_INTERFACE_INFO_LIST *);
using WlanQueryInterfaceFunction =
    DWORD(WINAPI *)(HANDLE, const GUID *, WLAN_INTF_OPCODE, PVOID, PDWORD,
                    PVOID *, PWLAN_OPCODE_VALUE_TYPE *);
using WlanFreeMemoryFunction = VOID(WINAPI *)(PVOID);

struct LibraryDeleter {
  using pointer = HMODULE;

  void operator()(HMODULE module) const {
    if (module != nullptr) {
      FreeLibrary(module);
    }
  }
};

using ScopedLibrary = std::unique_ptr<void, LibraryDeleter>;

template <typename Function>
Function ResolveFunction(HMODULE module, const char *name) {
  return reinterpret_cast<Function>(GetProcAddress(module, name));
}

class WlanApi {
 public:
  WlanApi() {
    wchar_t system_directory[MAX_PATH];
    const UINT length = GetSystemDirectoryW(system_directory, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) {
      return;
    }
    std::wstring library_path(system_directory, length);
    library_path.append(L"\\wlanapi.dll");
    module_.reset(LoadLibraryW(library_path.c_str()));
    if (module_ == nullptr) {
      return;
    }
    open_handle = ResolveFunction<WlanOpenHandleFunction>(
        module_.get(), "WlanOpenHandle");
    close_handle = ResolveFunction<WlanCloseHandleFunction>(
        module_.get(), "WlanCloseHandle");
    enum_interfaces = ResolveFunction<WlanEnumInterfacesFunction>(
        module_.get(), "WlanEnumInterfaces");
    query_interface = ResolveFunction<WlanQueryInterfaceFunction>(
        module_.get(), "WlanQueryInterface");
    free_memory = ResolveFunction<WlanFreeMemoryFunction>(
        module_.get(), "WlanFreeMemory");
  }

  bool is_available() const {
    return module_ != nullptr && open_handle != nullptr &&
           close_handle != nullptr && enum_interfaces != nullptr &&
           query_interface != nullptr && free_memory != nullptr;
  }

  WlanOpenHandleFunction open_handle = nullptr;
  WlanCloseHandleFunction close_handle = nullptr;
  WlanEnumInterfacesFunction enum_interfaces = nullptr;
  WlanQueryInterfaceFunction query_interface = nullptr;
  WlanFreeMemoryFunction free_memory = nullptr;

 private:
  ScopedLibrary module_;
};

struct WlanHandleDeleter {
  WlanCloseHandleFunction close_handle;

  void operator()(HANDLE handle) const {
    if (handle != nullptr && close_handle != nullptr) {
      close_handle(handle, nullptr);
    }
  }
};

struct WlanMemoryDeleter {
  WlanFreeMemoryFunction free_memory;

  template <typename T>
  void operator()(T *memory) const {
    if (memory != nullptr && free_memory != nullptr) {
      free_memory(memory);
    }
  }
};

using ScopedWlanHandle = std::unique_ptr<void, WlanHandleDeleter>;
using ScopedInterfaceList =
    std::unique_ptr<WLAN_INTERFACE_INFO_LIST, WlanMemoryDeleter>;
using ScopedConnectionAttributes =
    std::unique_ptr<WLAN_CONNECTION_ATTRIBUTES, WlanMemoryDeleter>;

}  // namespace

void WifiSsidPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  auto plugin = std::make_unique<WifiSsidPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });
  registrar->AddPlugin(std::move(plugin));
}

WifiSsidPlugin::WifiSsidPlugin() = default;

WifiSsidPlugin::~WifiSsidPlugin() = default;

void WifiSsidPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() == kGetSsidMethod) {
    GetSsid(std::move(result));
  } else if (method_call.method_name() == kCheckPermissionMethod ||
             method_call.method_name() == kRequestPermissionMethod) {
    result->Success(flutter::EncodableValue(kPermissionGranted));
  } else {
    result->NotImplemented();
  }
}

void WifiSsidPlugin::GetSsid(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  WlanApi api;
  if (!api.is_available()) {
    result->Success(flutter::EncodableValue());
    return;
  }
  HANDLE client_handle = nullptr;
  DWORD current_version = 0;
  DWORD result_code = api.open_handle(WLAN_API_VERSION_2_0, nullptr,
                                      &current_version, &client_handle);
  if (result_code == ERROR_ACCESS_DENIED) {
    result->Success(flutter::EncodableValue());
    return;
  }
  if (result_code != ERROR_SUCCESS) {
    result->Error("WLAN_ERROR", "Failed to open WLAN handle",
                  flutter::EncodableValue(static_cast<int>(result_code)));
    return;
  }
  ScopedWlanHandle client(client_handle,
                          WlanHandleDeleter{api.close_handle});

  PWLAN_INTERFACE_INFO_LIST interface_list = nullptr;
  result_code =
      api.enum_interfaces(client.get(), nullptr, &interface_list);
  if (result_code == ERROR_ACCESS_DENIED) {
    result->Success(flutter::EncodableValue());
    return;
  }
  if (result_code != ERROR_SUCCESS) {
    result->Error("WLAN_ERROR", "Failed to enumerate WLAN interfaces",
                  flutter::EncodableValue(static_cast<int>(result_code)));
    return;
  }
  ScopedInterfaceList interfaces(
      interface_list, WlanMemoryDeleter{api.free_memory});

  std::string ssid;
  bool access_denied = false;
  for (DWORD i = 0; i < interfaces->dwNumberOfItems; ++i) {
    const auto &interface_info = interfaces->InterfaceInfo[i];
    if (interface_info.isState != wlan_interface_state_connected) {
      continue;
    }

    PWLAN_CONNECTION_ATTRIBUTES connection_attributes = nullptr;
    DWORD data_size = 0;
    result_code = api.query_interface(
        client.get(), &interface_info.InterfaceGuid,
        wlan_intf_opcode_current_connection, nullptr, &data_size,
        reinterpret_cast<PVOID *>(&connection_attributes), nullptr);

    if (result_code == ERROR_ACCESS_DENIED) {
      access_denied = true;
      break;
    }
    if (result_code != ERROR_SUCCESS || connection_attributes == nullptr) {
      continue;
    }

    ScopedConnectionAttributes connection(
        connection_attributes, WlanMemoryDeleter{api.free_memory});
    const auto &dot11_ssid =
        connection->wlanAssociationAttributes.dot11Ssid;
    if (dot11_ssid.uSSIDLength == 0 ||
        dot11_ssid.uSSIDLength > DOT11_SSID_MAX_LENGTH) {
      continue;
    }
    ssid.assign(reinterpret_cast<const char *>(dot11_ssid.ucSSID),
                dot11_ssid.uSSIDLength);
    break;
  }

  if (access_denied || ssid.empty()) {
    result->Success(flutter::EncodableValue());
    return;
  }

  result->Success(flutter::EncodableValue(ssid));
}

}  // namespace wifi_ssid
