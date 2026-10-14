#ifndef FLUTTER_PLUGIN_PROXY_REGISTRY_H_
#define FLUTTER_PLUGIN_PROXY_REGISTRY_H_

#include <windows.h>
#include <string>
#include <vector>

namespace proxy::settings {

struct RegistryProxyReadback {
  bool enabled = false;
  std::wstring server;
};

inline bool ReadRegistryProxyString(HKEY key, const wchar_t* name,
                                    std::wstring& value, DWORD& error) {
  DWORD type = 0;
  DWORD size = 0;
  auto status = RegQueryValueExW(key, name, nullptr, &type, nullptr, &size);
  if (status == ERROR_FILE_NOT_FOUND) {
    value.clear();
    return true;
  }
  if (status != ERROR_SUCCESS || (type != REG_SZ && type != REG_EXPAND_SZ)) {
    error = status == ERROR_SUCCESS ? ERROR_INVALID_DATA : status;
    return false;
  }
  std::vector<wchar_t> buffer(size / sizeof(wchar_t) + 1, L'\0');
  status = RegQueryValueExW(key, name, nullptr, &type,
                           reinterpret_cast<LPBYTE>(buffer.data()), &size);
  if (status != ERROR_SUCCESS) {
    error = status;
    return false;
  }
  value.assign(buffer.data());
  return true;
}

inline bool ReadProxyRegistry(RegistryProxyReadback& readback, DWORD& error) {
  HKEY key = nullptr;
  auto status = RegOpenKeyExW(HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings",
      0, KEY_QUERY_VALUE, &key);
  if (status != ERROR_SUCCESS) {
    error = status;
    return false;
  }
  DWORD enabled = 0;
  DWORD type = 0;
  DWORD size = sizeof(enabled);
  status = RegQueryValueExW(key, L"ProxyEnable", nullptr, &type,
                           reinterpret_cast<LPBYTE>(&enabled), &size);
  if (status == ERROR_FILE_NOT_FOUND) {
    enabled = 0;
  } else if (status != ERROR_SUCCESS || type != REG_DWORD) {
    RegCloseKey(key);
    error = status == ERROR_SUCCESS ? ERROR_INVALID_DATA : status;
    return false;
  }
  readback.enabled = enabled != 0;
  const bool success = ReadRegistryProxyString(key, L"ProxyServer", readback.server, error);
  RegCloseKey(key);
  if (success) error = ERROR_SUCCESS;
  return success;
}

}

#endif
