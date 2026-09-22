#include <windows.h>
#include <winhttp.h>
#include <wininet.h>

#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>

#include "../proxy_settings.h"

namespace {

void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

void Notify() {
  Require(InternetSetOptionW(nullptr, INTERNET_OPTION_SETTINGS_CHANGED,
                             nullptr, 0) != FALSE,
          "Proxy change notification failed");
  Require(InternetSetOptionW(nullptr, INTERNET_OPTION_REFRESH,
                             nullptr, 0) != FALSE,
          "Proxy refresh failed");
}

class ProxySnapshot {
 public:
  ProxySnapshot() {
    options_[0].dwOption = INTERNET_PER_CONN_FLAGS;
    options_[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
    options_[2].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
    options_[3].dwOption = INTERNET_PER_CONN_AUTOCONFIG_URL;
    list_.dwSize = sizeof(list_);
    list_.dwOptionCount = 4;
    list_.pOptions = options_;
    DWORD size = sizeof(list_);
    captured_ = InternetQueryOptionA(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION,
                                    &list_, &size) != FALSE;
  }

  ~ProxySnapshot() {
    if (captured_ && !restored_) Restore();
    for (size_t i = 1; i < 4; ++i) GlobalFree(options_[i].Value.pszValue);
  }

  bool captured() const { return captured_; }

  bool Restore() {
    if (!captured_) return false;
    restored_ = InternetSetOptionA(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION,
                                  &list_, sizeof(list_)) != FALSE;
    const bool notified = InternetSetOptionW(
        nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0) != FALSE;
    const bool refreshed = InternetSetOptionW(
        nullptr, INTERNET_OPTION_REFRESH, nullptr, 0) != FALSE;
    return restored_ && notified && refreshed;
  }

 private:
  INTERNET_PER_CONN_OPTIONA options_[4] = {};
  INTERNET_PER_CONN_OPTION_LISTA list_ = {};
  bool captured_ = false;
  bool restored_ = false;
};

void Apply(const std::wstring& bypass) {
  INTERNET_PER_CONN_OPTIONW options[3] = {};
  options[0].dwOption = INTERNET_PER_CONN_FLAGS;
  options[0].Value.dwValue = PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY;
  options[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
  options[1].Value.pszValue = const_cast<wchar_t*>(L"127.0.0.1:17890");
  options[2].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
  options[2].Value.pszValue = const_cast<wchar_t*>(bypass.c_str());
  INTERNET_PER_CONN_OPTION_LISTW list = {};
  list.dwSize = sizeof(list);
  list.dwOptionCount = 3;
  list.pOptions = options;
  DWORD error = 0;
  bool fallback = false;
  Require(proxy::settings::SetConnectionOptions(
              list, nullptr, error, fallback),
          "Production proxy writer failed");
  Notify();
}

DWORD OpenAutomaticProxy() {
  const auto session = WinHttpOpen(
      L"FengWoProxyCompatibilityTest/1", WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
      WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, WINHTTP_FLAG_ASYNC);
  if (!session) return GetLastError();
  WinHttpCloseHandle(session);
  return ERROR_SUCCESS;
}

std::wstring ReadUtf8(const std::filesystem::path& path) {
  std::ifstream input(path, std::ios::binary);
  Require(input.good(), "Cannot read bypass fixture");
  std::string value{std::istreambuf_iterator<char>(input),
                    std::istreambuf_iterator<char>()};
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                      value.data(), static_cast<int>(value.size()),
                                      nullptr, 0);
  Require(size > 0, "Invalid or empty UTF-8 bypass fixture");
  std::wstring result(size, L'\0');
  Require(MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                             value.data(), static_cast<int>(value.size()),
                             result.data(), size) == size,
          "Cannot decode bypass fixture");
  return result;
}

void WriteUtf8(const std::filesystem::path& path, const std::wstring& value) {
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                      static_cast<int>(value.size()),
                                      nullptr, 0, nullptr, nullptr);
  Require(size > 0, "Cannot encode normalized bypass");
  std::string result(size, '\0');
  Require(WideCharToMultiByte(CP_UTF8, 0, value.data(),
                             static_cast<int>(value.size()), result.data(), size,
                             nullptr, nullptr) == size,
          "Cannot encode normalized bypass");
  std::ofstream output(path, std::ios::binary);
  output.write(result.data(), static_cast<std::streamsize>(result.size()));
  Require(output.good(), "Cannot write normalized bypass");
}

}

int wmain(int argc, wchar_t** argv) {
  try {
    wchar_t actions[16] = {};
    wchar_t allowMutation[16] = {};
    GetEnvironmentVariableW(L"GITHUB_ACTIONS", actions, 16);
    GetEnvironmentVariableW(L"FENGWO_PROXY_MUTATING_TEST", allowMutation, 16);
    Require(std::wstring(actions) == L"true" &&
                std::wstring(allowMutation) == L"1",
            "Requires an isolated CI Windows account");
    Require(argc == 3, "Expected raw bypass input and normalized output paths");
    using proxy::settings::NormalizeBypassList;
    Require(NormalizeBypassList(L"::1") == L"[::1]", "Bare loopback not normalized");
    Require(NormalizeBypassList(L"; ::1 ;[::1];;") == L"; [::1] ;[::1];;",
            "Whitespace or separators changed");
    Require(NormalizeBypassList(L"<local>;*.lan;[::1]:8080;公司内网") ==
                L"<local>;*.lan;[::1]:8080;公司内网",
            "Unrelated bypass entries changed");
    Require(NormalizeBypassList(L"").empty(), "Empty bypass changed");
    const auto raw = ReadUtf8(argv[1]);
    const auto normalized = NormalizeBypassList(raw);
    Require(raw != normalized, "Fixture must exercise legacy bare IPv6 loopback");
    Require(NormalizeBypassList(normalized) == normalized, "Normalization is not idempotent");
    ProxySnapshot original;
    Require(original.captured(), "Cannot back up proxy settings");
    Apply(raw);
    const auto legacyError = OpenAutomaticProxy();
    Apply(normalized);
    const auto fixedError = OpenAutomaticProxy();
    std::cout << "legacy_auto_proxy_error=" << legacyError << "\n"
              << "normalized_auto_proxy_error=" << fixedError << "\n";
    Require(fixedError == ERROR_SUCCESS, "Normalized bypass still breaks WinHTTP");
    Require(original.Restore(), "Cannot restore original proxy settings");
    WriteUtf8(argv[2], normalized);
    std::cout << "PASS: production writer and normalized bypass support WinHTTP\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << "\n";
    return 1;
  }
}
