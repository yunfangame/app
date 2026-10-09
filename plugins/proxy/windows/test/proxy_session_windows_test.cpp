#include <windows.h>
#include <wininet.h>

#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>

#include "../proxy_settings.h"

using proxy::settings::ConnectionBackend;
using proxy::settings::ConnectionConfiguration;
using proxy::settings::ProxySession;
using proxy::settings::SessionOperationDetails;

namespace {

void Require(bool value, const char* message) {
  if (!value) throw std::runtime_error(message);
}

ConnectionConfiguration FixtureConfiguration() {
  return {PROXY_TYPE_DIRECT | PROXY_TYPE_AUTO_PROXY_URL | PROXY_TYPE_AUTO_DETECT,
          L"corporate.example:8080", L"*.corp;<local>",
          L"http://127.0.0.1:65534/not-contacted.pac"};
}

ConnectionConfiguration Manual(int port = 17890) {
  return {PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY,
          L"127.0.0.1:" + std::to_wstring(port), L"localhost;[::1]", L""};
}

bool Notify(SessionOperationDetails& details) {
  if (!InternetSetOptionW(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0)) {
    details.stage = "notify_settings_changed";
    details.errorCode = GetLastError();
    return false;
  }
  if (!InternetSetOptionW(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0)) {
    details.stage = "notify_refresh";
    details.errorCode = GetLastError();
    return false;
  }
  return true;
}

ConnectionConfiguration Read() {
  ConnectionConfiguration configuration;
  DWORD error = 0;
  Require(proxy::settings::QueryConnection(L"", configuration, error),
          "Cannot query complete WinINet configuration");
  return configuration;
}

void Apply(const ConnectionConfiguration& configuration) {
  DWORD error = 0;
  bool fallback = false;
  Require(proxy::settings::WriteConnection(L"", configuration, error, fallback),
          "Cannot apply complete WinINet fixture");
  SessionOperationDetails notification;
  Require(Notify(notification), "Cannot notify fixture change");
}

class SnapshotGuard {
 public:
  SnapshotGuard() : original_(Read()) {}
  ~SnapshotGuard() {
    if (restored_) return;
    DWORD error = 0;
    bool fallback = false;
    proxy::settings::WriteConnection(L"", original_, error, fallback);
    SessionOperationDetails notification;
    Notify(notification);
  }
  void Restore() {
    Apply(original_);
    Require(Read() == original_, "Original Windows account proxy was not fully restored");
    restored_ = true;
  }

 private:
  ConnectionConfiguration original_;
  bool restored_ = false;
};

int ansi_reads = 0;
int ansi_writes = 0;

BOOL WINAPI RejectWideQuery(HINTERNET, DWORD, LPVOID, LPDWORD) {
  SetLastError(ERROR_INVALID_PARAMETER);
  return FALSE;
}

BOOL WINAPI RejectWideWrite(HINTERNET, DWORD, LPVOID, DWORD) {
  SetLastError(ERROR_INVALID_PARAMETER);
  return FALSE;
}

BOOL WINAPI FillAnsiQuery(HINTERNET handle, DWORD option, LPVOID buffer, LPDWORD size) {
  auto* list = static_cast<INTERNET_PER_CONN_OPTION_LISTA*>(buffer);
  Require(handle == nullptr && option == INTERNET_OPTION_PER_CONNECTION_OPTION &&
          *size == sizeof(*list) && list->dwOptionCount == 4 &&
          std::string(list->pszConnection) == "VPN-A", "Wrong ANSI complete query schema");
  ansi_reads++;
  if (list->pOptions[0].dwOption == INTERNET_PER_CONN_FLAGS_UI) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return FALSE;
  }
  Require(list->pOptions[0].dwOption == INTERNET_PER_CONN_FLAGS,
          "Legacy query did not use connection flags");
  list->pOptions[0].Value.dwValue = FixtureConfiguration().flags;
  const char* values[] = {"corporate.example:8080", "*.corp;<local>",
                          "http://127.0.0.1:65534/not-contacted.pac"};
  const DWORD options[] = {INTERNET_PER_CONN_PROXY_SERVER, INTERNET_PER_CONN_PROXY_BYPASS,
                           INTERNET_PER_CONN_AUTOCONFIG_URL};
  for (size_t i = 0; i < 3; ++i) {
    Require(list->pOptions[i + 1].dwOption == options[i], "Wrong ANSI string option type");
    const auto length = std::strlen(values[i]) + 1;
    auto* memory = static_cast<char*>(GlobalAlloc(GPTR, length));
    Require(memory != nullptr, "Cannot allocate query fixture");
    std::memcpy(memory, values[i], length);
    list->pOptions[i + 1].Value.pszValue = memory;
  }
  return TRUE;
}

BOOL WINAPI VerifyAnsiWrite(HINTERNET handle, DWORD option, LPVOID buffer, DWORD size) {
  const auto* list = static_cast<INTERNET_PER_CONN_OPTION_LISTA*>(buffer);
  Require(handle == nullptr && option == INTERNET_OPTION_PER_CONNECTION_OPTION &&
          size == sizeof(*list) && list->dwOptionCount == 4 &&
          std::string(list->pszConnection) == "VPN-A", "Wrong ANSI complete write schema");
  Require(list->pOptions[0].dwOption == INTERNET_PER_CONN_FLAGS &&
          list->pOptions[0].Value.dwValue == FixtureConfiguration().flags,
          "ANSI flags did not preserve PAC and autodetect");
  Require(list->pOptions[1].dwOption == INTERNET_PER_CONN_PROXY_SERVER &&
          std::string(list->pOptions[1].Value.pszValue) == "corporate.example:8080",
          "ANSI server not preserved");
  Require(list->pOptions[2].dwOption == INTERNET_PER_CONN_PROXY_BYPASS &&
          std::string(list->pOptions[2].Value.pszValue) == "*.corp;<local>",
          "ANSI bypass not preserved");
  Require(list->pOptions[3].dwOption == INTERNET_PER_CONN_AUTOCONFIG_URL &&
          std::string(list->pOptions[3].Value.pszValue) ==
              "http://127.0.0.1:65534/not-contacted.pac", "ANSI PAC string not preserved");
  ansi_writes++;
  return TRUE;
}

void TypedFallback() {
  ConnectionConfiguration configuration;
  DWORD error = 0;
  Require(proxy::settings::QueryConnection(L"VPN-A", configuration, error,
          RejectWideQuery, FillAnsiQuery) && configuration == FixtureConfiguration() &&
          error == ERROR_SUCCESS && ansi_reads == 2, "Complete query fallback failed");
  bool fallback = false;
  Require(proxy::settings::WriteConnection(L"VPN-A", configuration, error, fallback,
          RejectWideWrite, VerifyAnsiWrite) && fallback && error == ERROR_SUCCESS &&
          ansi_writes == 1, "Complete writer fallback failed");
}

struct NativeFixture {
  int reads = 0;
  int writes = 0;
  int notifications = 0;

  ConnectionBackend Backend() {
    return {
      [](std::vector<std::wstring>& names, uint32_t& error) {
        names.clear();
        error = 0;
        return true;
      },
      [&](const std::wstring& name, ConnectionConfiguration& configuration, uint32_t& error) {
        reads++;
        DWORD native_error = 0;
        const bool success = proxy::settings::QueryConnection(name, configuration, native_error);
        error = native_error;
        return success;
      },
      [&](const std::wstring& name, const ConnectionConfiguration& configuration,
          uint32_t& error, bool& fallback) {
        writes++;
        DWORD native_error = 0;
        const bool success = proxy::settings::WriteConnection(name, configuration,
                                                              native_error, fallback);
        error = native_error;
        return success;
      },
      [&](SessionOperationDetails& details) { notifications++; return Notify(details); }
    };
  }
};

void ActualWindowsSession() {
  SnapshotGuard original;
  const auto fixture = FixtureConfiguration();
  Apply(fixture);
  Require(Read() == fixture, "Fixture PAC/autodetect values did not round trip");
  NativeFixture native;
  ProxySession session;
  Require(session.Start(Manual(), native.Backend()).success && Read() == Manual(),
          "Real WinINet session start failed");
  const int reads = native.reads;
  const auto repeated = session.Start(Manual(), native.Backend());
  Require(repeated.success && repeated.writeSkipped && native.writes == 1 &&
          native.notifications == 1 && native.reads > reads,
          "Real unchanged Start repeated writes or skipped verification");
  Require(session.Stop(17890, native.Backend()).success && Read() == fixture &&
          native.writes == 2 && !session.HasPendingCleanup(),
          "Real Stop did not restore complete original PAC/autodetect settings");
  Require(session.Stop(std::nullopt, native.Backend()).writeSkipped && native.writes == 2,
          "Real repeated Stop wrote again");
  ProxySession ports;
  Require(ports.Start(Manual(), native.Backend()).success &&
          ports.Start(Manual(17891), native.Backend()).success &&
          ports.Stop(17891, native.Backend()).success && Read() == fixture,
          "Real port changes lost initial snapshot");
  ProxySession foreign;
  Require(foreign.Start(Manual(), native.Backend()).success, "Real foreign test start failed");
  const ConnectionConfiguration other{PROXY_TYPE_DIRECT, L"127.0.0.1:17892", L"*.foreign", L""};
  Apply(other);
  const int writes = native.writes;
  const auto stopped = foreign.Stop(17890, native.Backend());
  Require(stopped.success && stopped.restoreAbandoned && stopped.writeSkipped &&
          native.writes == writes && Read() == other, "Real foreign configuration was overwritten");
  Apply(Manual());
  ProxySession adopted;
  Require(adopted.Start(Manual(), native.Backend()).writeSkipped &&
          adopted.Stop(17890, native.Backend()).success,
          "Real residual endpoint could not be adopted and released");
  auto disabled = Manual();
  disabled.flags = PROXY_TYPE_DIRECT;
  Require(Read() == disabled, "Adopted residual endpoint restored a dead proxy");
  original.Restore();
}

}

int main() {
  try {
    wchar_t actions[16] = {};
    wchar_t mutation[16] = {};
    GetEnvironmentVariableW(L"GITHUB_ACTIONS", actions, 16);
    GetEnvironmentVariableW(L"FENGWO_PROXY_MUTATING_TEST", mutation, 16);
    Require(std::wstring(actions) == L"true" && std::wstring(mutation) == L"1",
            "Requires an isolated CI Windows account");
    TypedFallback();
    ActualWindowsSession();
    std::cout << "PASS: typed complete W/ANSI fallback and real WinINet session restoration\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAIL: " << error.what() << '\n';
    return 1;
  }
}
