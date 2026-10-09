#ifndef FLUTTER_PLUGIN_PROXY_SETTINGS_H_
#define FLUTTER_PLUGIN_PROXY_SETTINGS_H_

#include <windows.h>
#include <wininet.h>
#include <string>
#include <vector>

#include "proxy_session.h"

namespace proxy::settings {

inline std::wstring NormalizeBypassList(const std::wstring& value) {
  std::wstring normalized;
  size_t start = 0;
  while (true) {
    const auto end = value.find(L';', start);
    auto rule = value.substr(start, end == std::wstring::npos ? end : end - start);
    const auto first = rule.find_first_not_of(L" \t\r\n");
    if (first != std::wstring::npos) {
      const auto last = rule.find_last_not_of(L" \t\r\n");
      if (rule.substr(first, last - first + 1) == L"::1") {
        rule.replace(first, 3, L"[::1]");
      }
    }
    normalized += rule;
    if (end == std::wstring::npos) return normalized;
    normalized += L';';
    start = end + 1;
  }
}

inline bool ToAnsi(const wchar_t* value, std::string& output) {
  output.clear();
  if (value == nullptr || *value == L'\0') return true;
  const bool utf8 = GetACP() == CP_UTF8;
  BOOL substituted = FALSE;
  const auto flags = utf8 ? 0 : WC_NO_BEST_FIT_CHARS;
  auto* usedDefault = utf8 ? nullptr : &substituted;
  const int size = WideCharToMultiByte(
      CP_ACP, flags, value, -1, nullptr, 0, nullptr, usedDefault);
  if (size <= 0 || substituted) return false;
  std::vector<char> buffer(size);
  if (!WideCharToMultiByte(CP_ACP, flags, value, -1, buffer.data(), size,
                          nullptr, usedDefault) || substituted) return false;
  output.assign(buffer.data());
  return true;
}

inline bool SetConnectionOptions(
    INTERNET_PER_CONN_OPTION_LISTW& list, wchar_t* connection,
    DWORD& error, bool& fallback,
    decltype(&InternetSetOptionW) setWide = InternetSetOptionW,
    decltype(&InternetSetOptionA) setAnsi = InternetSetOptionA) {
  list.pszConnection = connection;
  list.dwOptionError = 0;
  if (setWide(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION,
              &list, sizeof(list))) {
    error = ERROR_SUCCESS;
    return true;
  }
  error = GetLastError();
  if (error != ERROR_INVALID_PARAMETER) return false;
  fallback = true;
  std::string connectionAnsi;
  if (!ToAnsi(connection, connectionAnsi)) {
    error = ERROR_NO_UNICODE_TRANSLATION;
    return false;
  }
  std::vector<INTERNET_PER_CONN_OPTIONA> options(list.dwOptionCount);
  std::vector<std::string> strings(list.dwOptionCount);
  for (DWORD i = 0; i < list.dwOptionCount; ++i) {
    options[i].dwOption = list.pOptions[i].dwOption;
    if (options[i].dwOption == INTERNET_PER_CONN_FLAGS) {
      options[i].Value.dwValue = list.pOptions[i].Value.dwValue;
    } else if (options[i].dwOption == INTERNET_PER_CONN_PROXY_SERVER ||
               options[i].dwOption == INTERNET_PER_CONN_PROXY_BYPASS ||
               options[i].dwOption == INTERNET_PER_CONN_AUTOCONFIG_URL) {
      if (!ToAnsi(list.pOptions[i].Value.pszValue, strings[i])) {
        error = ERROR_NO_UNICODE_TRANSLATION;
        return false;
      }
      options[i].Value.pszValue = strings[i].data();
    } else {
      error = ERROR_INVALID_PARAMETER;
      return false;
    }
  }
  INTERNET_PER_CONN_OPTION_LISTA ansi = {};
  ansi.dwSize = sizeof(ansi);
  ansi.pszConnection = connection == nullptr ? nullptr : connectionAnsi.data();
  ansi.dwOptionCount = list.dwOptionCount;
  ansi.pOptions = options.data();
  if (!setAnsi(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION,
               &ansi, sizeof(ansi))) {
    error = GetLastError();
    return false;
  }
  error = ERROR_SUCCESS;
  return true;
}

inline bool QueryConnection(
    const std::wstring& connection, ConnectionConfiguration& configuration,
    DWORD& error,
    decltype(&InternetQueryOptionW) queryWide = InternetQueryOptionW,
    decltype(&InternetQueryOptionA) queryAnsi = InternetQueryOptionA) {
  INTERNET_PER_CONN_OPTIONW options[4] = {};
  options[0].dwOption = INTERNET_PER_CONN_FLAGS_UI;
  options[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
  options[2].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
  options[3].dwOption = INTERNET_PER_CONN_AUTOCONFIG_URL;
  INTERNET_PER_CONN_OPTION_LISTW list = {};
  list.dwSize = sizeof(list);
  list.pszConnection = connection.empty() ? nullptr : const_cast<wchar_t*>(connection.c_str());
  list.dwOptionCount = 4;
  list.pOptions = options;
  auto freeWide = [&]() {
    for (size_t i = 1; i < 4; ++i) {
      GlobalFree(options[i].Value.pszValue);
      options[i].Value.pszValue = nullptr;
    }
  };
  DWORD size = sizeof(list);
  BOOL success = queryWide(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &list, &size);
  error = success ? ERROR_SUCCESS : GetLastError();
  if (success) {
    configuration.flags = options[0].Value.dwValue;
    configuration.server = options[1].Value.pszValue == nullptr ? L"" : options[1].Value.pszValue;
    configuration.bypass = options[2].Value.pszValue == nullptr ? L"" : options[2].Value.pszValue;
    configuration.auto_config_url = options[3].Value.pszValue == nullptr ? L"" : options[3].Value.pszValue;
    freeWide();
    return true;
  }
  freeWide();
  if (error != ERROR_INVALID_PARAMETER) return false;
  std::string connectionAnsi;
  if (!ToAnsi(list.pszConnection, connectionAnsi)) {
    error = ERROR_NO_UNICODE_TRANSLATION;
    return false;
  }
  INTERNET_PER_CONN_OPTIONA ansiOptions[4] = {};
  for (size_t i = 0; i < 4; ++i) ansiOptions[i].dwOption = options[i].dwOption;
  INTERNET_PER_CONN_OPTION_LISTA ansi = {};
  ansi.dwSize = sizeof(ansi);
  ansi.pszConnection = connection.empty() ? nullptr : connectionAnsi.data();
  ansi.dwOptionCount = 4;
  ansi.pOptions = ansiOptions;
  auto freeAnsi = [&]() {
    for (size_t i = 1; i < 4; ++i) {
      GlobalFree(ansiOptions[i].Value.pszValue);
      ansiOptions[i].Value.pszValue = nullptr;
    }
  };
  size = sizeof(ansi);
  success = queryAnsi(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &ansi, &size);
  error = success ? ERROR_SUCCESS : GetLastError();
  if (!success && error == ERROR_INVALID_PARAMETER) {
    freeAnsi();
    ansiOptions[0].dwOption = INTERNET_PER_CONN_FLAGS;
    ansi.dwOptionError = 0;
    size = sizeof(ansi);
    success = queryAnsi(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &ansi, &size);
    error = success ? ERROR_SUCCESS : GetLastError();
  }
  if (success) {
    configuration.flags = ansiOptions[0].Value.dwValue;
    std::wstring* values[] = {&configuration.server, &configuration.bypass,
                             &configuration.auto_config_url};
    for (size_t i = 1; i < 4; ++i) {
      auto& value = *values[i - 1];
      value.clear();
      const auto text = ansiOptions[i].Value.pszValue;
      if (text == nullptr || *text == '\0') continue;
      const int length = MultiByteToWideChar(CP_ACP, 0, text, -1, nullptr, 0);
      if (length <= 0) {
        success = FALSE;
        error = GetLastError();
        break;
      }
      std::vector<wchar_t> buffer(length);
      if (!MultiByteToWideChar(CP_ACP, 0, text, -1, buffer.data(), length)) {
        success = FALSE;
        error = GetLastError();
        break;
      }
      value.assign(buffer.data());
    }
  }
  freeAnsi();
  return success != FALSE;
}

inline bool WriteConnection(
    const std::wstring& connection, const ConnectionConfiguration& configuration,
    DWORD& error, bool& fallback,
    decltype(&InternetSetOptionW) setWide = InternetSetOptionW,
    decltype(&InternetSetOptionA) setAnsi = InternetSetOptionA) {
  INTERNET_PER_CONN_OPTIONW options[4] = {};
  options[0].dwOption = INTERNET_PER_CONN_FLAGS;
  options[0].Value.dwValue = configuration.flags;
  options[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
  options[1].Value.pszValue = const_cast<wchar_t*>(configuration.server.c_str());
  options[2].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
  options[2].Value.pszValue = const_cast<wchar_t*>(configuration.bypass.c_str());
  options[3].dwOption = INTERNET_PER_CONN_AUTOCONFIG_URL;
  options[3].Value.pszValue = const_cast<wchar_t*>(configuration.auto_config_url.c_str());
  INTERNET_PER_CONN_OPTION_LISTW list = {};
  list.dwSize = sizeof(list);
  list.dwOptionCount = 4;
  list.pOptions = options;
  return SetConnectionOptions(list, connection.empty() ? nullptr
      : const_cast<wchar_t*>(connection.c_str()), error, fallback, setWide, setAnsi);
}

inline bool QueryProxy(
    bool& enabled, std::wstring& server, DWORD& error,
    decltype(&InternetQueryOptionA) query = InternetQueryOptionA) {
  INTERNET_PER_CONN_OPTIONA options[2] = {};
  options[0].dwOption = INTERNET_PER_CONN_FLAGS_UI;
  options[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
  INTERNET_PER_CONN_OPTION_LISTA list = {};
  list.dwSize = sizeof(list);
  list.dwOptionCount = 2;
  list.pOptions = options;
  DWORD size = sizeof(list);
  BOOL success = query(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION,
                       &list, &size);
  error = success ? ERROR_SUCCESS : GetLastError();
  if (!success && error == ERROR_INVALID_PARAMETER) {
    GlobalFree(options[1].Value.pszValue);
    options[1].Value.pszValue = nullptr;
    options[0].dwOption = INTERNET_PER_CONN_FLAGS;
    size = sizeof(list);
    list.dwOptionError = 0;
    success = query(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION,
                    &list, &size);
    error = success ? ERROR_SUCCESS : GetLastError();
  }
  if (success) {
    enabled = (options[0].Value.dwValue & PROXY_TYPE_PROXY) != 0;
    server.clear();
    const auto value = options[1].Value.pszValue;
    if (value != nullptr && *value != '\0') {
      const int length = MultiByteToWideChar(CP_ACP, 0, value, -1, nullptr, 0);
      if (length <= 0) {
        success = FALSE;
        error = GetLastError();
      } else {
        std::vector<wchar_t> buffer(length);
        if (!MultiByteToWideChar(CP_ACP, 0, value, -1, buffer.data(), length)) {
          success = FALSE;
          error = GetLastError();
        } else {
          server.assign(buffer.data());
        }
      }
    }
  }
  GlobalFree(options[1].Value.pszValue);
  return success != FALSE;
}

}

#endif
