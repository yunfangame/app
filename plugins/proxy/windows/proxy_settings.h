#ifndef FLUTTER_PLUGIN_PROXY_SETTINGS_H_
#define FLUTTER_PLUGIN_PROXY_SETTINGS_H_

#include <windows.h>
#include <wininet.h>
#include <string>
#include <vector>

namespace proxy::settings {

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
               options[i].dwOption == INTERNET_PER_CONN_PROXY_BYPASS) {
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
