#include <windows.h>
#include <wininet.h>

#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>

#include "../proxy_settings.h"
#include "../proxy_registry.h"

#pragma comment(lib, "advapi32")

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

bool VerifyRegistry(const ConnectionConfiguration& configuration, DWORD& error) {
  proxy::settings::RegistryProxyReadback registry;
  if (!proxy::settings::ReadProxyRegistry(registry, error)) return false;
  if (registry.enabled != configuration.HasManualProxy() ||
      (registry.enabled && registry.server != configuration.server)) {
    error = ERROR_INVALID_DATA;
    return false;
  }
  error = ERROR_SUCCESS;
  return true;
}

ConnectionConfiguration Read() {
  ConnectionConfiguration configuration;
  DWORD error = 0;
  Require(proxy::settings::QueryConnection(L"", configuration, error),
          "Cannot query complete WinINet configuration");
  Require(VerifyRegistry(configuration, error), "Cannot corroborate WinINet with proxy registry");
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
        if (success && name.empty() && !VerifyRegistry(configuration, native_error)) {
          error = native_error;
          return false;
        }
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

void ActualLegacyRegistryRepair() {
  SnapshotGuard original;
  struct LegacyValue {
    const char* label;
    const wchar_t* name;
    DWORD type;
    const void* data;
    DWORD size;
  };
  const wchar_t short_string[] = L"x";
  const wchar_t long_string[] = L"legacy-invalid-type";
  const DWORD number = 1;
  const wchar_t multiple[] = L"invalid\0";
  const LegacyValue fixtures[] = {
    {"enable_short_string", L"ProxyEnable", REG_SZ, short_string, sizeof(short_string)},
    {"enable_long_string", L"ProxyEnable", REG_SZ, long_string, sizeof(long_string)},
    {"enable_binary", L"ProxyEnable", REG_BINARY, &number, sizeof(number)},
    {"server_dword", L"ProxyServer", REG_DWORD, &number, sizeof(number)},
    {"server_binary", L"ProxyServer", REG_BINARY, &number, sizeof(number)},
    {"server_multi_string", L"ProxyServer", REG_MULTI_SZ, multiple, sizeof(multiple)},
  };
  int invalid_data_reproductions = 0;
  int more_data_reproductions = 0;
  for (const auto& fixture : fixtures) {
    Apply(FixtureConfiguration());
    NativeFixture native;
    auto backend = native.Backend();
    backend.capture = [](const std::wstring& name, ConnectionConfiguration& configuration,
                         uint32_t& error) {
      DWORD native_error = 0;
      const bool success = proxy::settings::QueryConnection(name, configuration, native_error);
      error = native_error;
      return success;
    };
    ConnectionConfiguration snapshot;
    uint32_t error = 0;
    Require(backend.capture(L"", snapshot, error), "Cannot capture clean fixture snapshot");
    HKEY key = nullptr;
    Require(RegOpenKeyExW(HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings",
        0, KEY_SET_VALUE, &key) == ERROR_SUCCESS, "Cannot prepare registry fixture");
    const auto status = RegSetValueExW(key, fixture.name, 0, fixture.type,
        static_cast<const BYTE*>(fixture.data), fixture.size);
    RegCloseKey(key);
    Require(status == ERROR_SUCCESS, "Cannot write legacy registry fixture");
    proxy::settings::RegistryProxyReadback raw;
    DWORD raw_error = 0;
    const bool raw_success = proxy::settings::ReadProxyRegistry(raw, raw_error);
    auto strict = backend;
    strict.capture = {};
    ProxySession old_policy;
    const auto rejected = old_policy.Start(Manual(), strict);
    std::cout << "LEGACY_FIXTURE: " << fixture.label << " raw_success=" << raw_success
              << " raw_error=" << raw_error << " old_success=" << rejected.success
              << " stage=" << rejected.stage << " error=" << rejected.errorCode
              << " writes=" << native.writes << "\n";
    if (rejected.success) {
      const auto stopped = old_policy.Stop(std::nullopt, strict);
      std::cout << "NORMALIZED_OLD_CLEANUP: " << fixture.label << " success="
                << stopped.success << " stage=" << stopped.stage << " error="
                << stopped.errorCode << "\n";
      Apply(snapshot);
      Require(Read() == snapshot, "Cannot restore normalized fixture baseline");
      continue;
    }
    Require(rejected.stage == "capture_default" && native.writes == 0,
            "Legacy snapshot rejection wrote settings or failed at an unexpected stage");
    Require(rejected.errorCode == ERROR_INVALID_DATA || rejected.errorCode == ERROR_MORE_DATA,
            "Unexpected native legacy registry error");
    invalid_data_reproductions += rejected.errorCode == ERROR_INVALID_DATA ? 1 : 0;
    more_data_reproductions += rejected.errorCode == ERROR_MORE_DATA ? 1 : 0;
    ConnectionConfiguration repaired_original;
    Require(backend.capture(L"", repaired_original, error), "Cannot capture actual legacy WinINet snapshot");
    ProxySession repaired;
    const auto applied = repaired.Start(Manual(), backend);
    Require(applied.success && Read() == Manual(), "Actual registry repair failed");
    Require(repaired.Stop(std::nullopt, backend).success && Read() == repaired_original,
            "Repaired session did not restore its original complete WinINet snapshot");
    std::cout << "REPAIRED: " << fixture.label << " native_error=" << rejected.errorCode
              << " verified and original settings restored\n";
  }
  original.Restore();
  Require(more_data_reproductions > 0, "Actual ERROR_MORE_DATA fixture was not reproduced");
  Require(invalid_data_reproductions > 0, "Actual ERROR_INVALID_DATA fixture was not reproduced");
  std::cout << "PASS: actual legacy snapshot failures 13 and 234 repaired without error normalization\n";
}

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
          !adopted.HasPendingCleanup() &&
          adopted.Stop(std::nullopt, native.Backend()).success && Read() == Manual(),
          "Real unchanged external endpoint was incorrectly acquired");
  Require(adopted.Start(Manual(17891), native.Backend()).success &&
          adopted.Stop(std::nullopt, native.Backend()).success && Read() == Manual(),
          "Real written new endpoint did not restore the original external endpoint");
  original.Restore();
}

}

int main() {
  try {
    wchar_t actions[16] = {};
    wchar_t mutation[16] = {};
    wchar_t authorized_machine[MAX_COMPUTERNAME_LENGTH + 1] = {};
    wchar_t machine[MAX_COMPUTERNAME_LENGTH + 1] = {};
    DWORD machine_length = MAX_COMPUTERNAME_LENGTH + 1;
    GetEnvironmentVariableW(L"GITHUB_ACTIONS", actions, 16);
    GetEnvironmentVariableW(L"FENGWO_PROXY_MUTATING_TEST", mutation, 16);
    GetEnvironmentVariableW(L"FENGWO_PROXY_TEST_MACHINE", authorized_machine,
                            MAX_COMPUTERNAME_LENGTH + 1);
    const bool named_test_machine = GetComputerNameW(machine, &machine_length) &&
        authorized_machine[0] != L'\0' && std::wstring(machine) == authorized_machine;
    Require((std::wstring(actions) == L"true" || named_test_machine) &&
            std::wstring(mutation) == L"1", "Requires an explicitly selected isolated Windows test account");
    TypedFallback();
    ActualWindowsSession();
    ActualLegacyRegistryRepair();
    std::cout << "PASS: typed complete W/ANSI fallback, real WinINet restoration and registry corroboration\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAIL: " << error.what() << '\n';
    return 1;
  }
}
