#include "../proxy_session.h"

#include <iostream>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>

using proxy::settings::ConnectionBackend;
using proxy::settings::ConnectionConfiguration;
using proxy::settings::ProxySession;
using proxy::settings::SessionOperationDetails;

namespace {

void Require(bool value, const char* message) {
  if (!value) throw std::runtime_error(message);
}

ConnectionConfiguration Manual(int port = 7890) {
  return {3, L"127.0.0.1:" + std::to_wstring(port), L"localhost;[::1]", L""};
}

ConnectionConfiguration Original() {
  return {13, L"corporate.example:8080", L"*.corp;<local>", L"https://corp.example/proxy.pac"};
}

struct Fixture {
  std::map<std::wstring, ConnectionConfiguration> values{{L"", Original()}};
  std::vector<std::wstring> ras;
  int reads = 0;
  int writes = 0;
  int notifications = 0;
  bool enumeration_failure = false;
  bool notification_failure = false;
  std::wstring fail_write = L"never";
  std::wstring fail_read = L"never";
  bool change_on_failure = false;
  bool partial_on_failure = false;
  bool throw_on_write = false;
  bool read_failure_after_write = false;

  ConnectionBackend Backend() {
    return {
      [&](std::vector<std::wstring>& result, uint32_t& error) {
        if (enumeration_failure) { error = 5; return false; }
        result = ras;
        error = 0;
        return true;
      },
      [&](const std::wstring& name, ConnectionConfiguration& result, uint32_t& error) {
        reads++;
        if (name == fail_read || (read_failure_after_write && writes > 0)) {
          error = 5;
          return false;
        }
        result = values.at(name);
        error = 0;
        return true;
      },
      [&](const std::wstring& name, const ConnectionConfiguration& value,
          uint32_t& error, bool&) {
        writes++;
        if (throw_on_write) {
          values[name] = value;
          throw std::runtime_error("injected write exception");
        }
        if (name == fail_write) {
          if (change_on_failure) values[name] = value;
          if (partial_on_failure) {
            values[name].flags = value.flags;
            values[name].bypass = value.bypass;
          }
          error = 5;
          return false;
        }
        values[name] = value;
        error = 0;
        return true;
      },
      [&](SessionOperationDetails& result) {
        notifications++;
        if (notification_failure) {
          result.stage = "notify_refresh";
          result.errorCode = 5;
          return false;
        }
        return true;
      }
    };
  }
};

void CompleteSnapshotsAndRepeatedStart() {
  Fixture f;
  f.ras = {L"VPN-A", L"VPN-B"};
  f.values[L"VPN-A"] = {8, L"", L"office", L""};
  f.values[L"VPN-B"] = {7, L"old:88", L"intranet", L"https://vpn.example/pac"};
  const auto original = f.values;
  ProxySession session;
  auto first = session.Start(Manual(), f.Backend());
  Require(first.success && first.snapshotCount == 3, "all original connections captured");
  Require(f.writes == 3 && f.notifications == 1, "one complete write per changed connection");
  const auto reads = f.reads;
  auto repeated = session.Start(Manual(), f.Backend());
  Require(repeated.success && repeated.writeSkipped, "same settings skip writes");
  Require(f.writes == 3 && f.notifications == 1 && f.reads > reads, "same settings still verified");
  Require(session.Stop(7890, f.Backend()).success, "restore succeeds");
  Require(f.values == original && !session.HasPendingCleanup(), "PAC autodetect bypass restored individually");
  const auto stopped_writes = f.writes;
  auto second_stop = session.Stop(std::nullopt, f.Backend());
  Require(second_stop.success && second_stop.writeSkipped && f.writes == stopped_writes,
          "repeated stop does not rewrite configuration");
}

void PortChangesKeepOriginal() {
  Fixture f;
  ProxySession session;
  Require(session.Start(Manual(), f.Backend()).success, "initial port starts");
  Require(session.Start(Manual(7891), f.Backend()).success, "new port starts");
  const int writes = f.writes;
  auto stale = session.Stop(7890, f.Backend());
  Require(stale.success && stale.writeSkipped && session.HasPendingCleanup(), "stale port cannot release new proxy");
  Require(f.writes == writes && f.values[L""] == Manual(7891), "stale stop leaves current port");
  Require(session.Stop(7891, f.Backend()).success && f.values[L""] == Original(),
          "port changes restore first original snapshot");
}

void ExplicitReconnectRestoresLatestForeignSnapshot() {
  Fixture f;
  f.ras = {L"VPN"};
  f.values[L"VPN"] = Original();
  ProxySession session;
  Require(session.Start(Manual(), f.Backend()).success, "initial application starts");
  const ConnectionConfiguration external{
      15, L"external.example:17890", L"*.external;<local>",
      L"https://external.example/proxy.pac"};
  f.values[L""] = external;
  Require(session.Start(Manual(), f.Backend()).success, "explicit reconnect replaces foreign settings");
  Require(session.Stop(std::nullopt, f.Backend()).success, "reconnected session restores");
  Require(f.values[L""] == external && f.values[L"VPN"] == Original() &&
          !session.HasPendingCleanup(), "foreign takeover refreshes only its own restoration snapshot");
  const auto writes = f.writes;
  Require(session.Stop(std::nullopt, f.Backend()).writeSkipped && f.writes == writes &&
          f.values[L""] == external, "repeated stop preserves the latest external settings");
}

void ForeignChangesAndAlreadyRestored() {
  Fixture f;
  ProxySession session;
  Require(session.Start(Manual(), f.Backend()).success, "starts for foreign test");
  auto foreign = Manual();
  foreign.bypass = L"user-changed";
  f.values[L""] = foreign;
  const auto writes = f.writes;
  auto stop = session.Stop(7890, f.Backend());
  Require(stop.success && stop.restoreAbandoned && stop.writeSkipped, "changed bypass yields ownership");
  Require(f.values[L""] == foreign && f.writes == writes, "foreign configuration preserved");
  ProxySession restored;
  Require(restored.Start(Manual(), f.Backend()).success, "second session starts");
  f.values[L""] = foreign;
  stop = restored.Stop(std::nullopt, f.Backend());
  Require(stop.success && !stop.restoreAbandoned && stop.writeSkipped,
          "already original configuration skips restore without abandonment");
}

void SafeLegacyAndAdoptedProxy() {
  Fixture f;
  ProxySession empty;
  Require(empty.Stop(std::nullopt, f.Backend()).success && f.writes == 0,
          "legacy stop without session does not disable foreign proxy");
  f.values[L""] = Manual();
  ProxySession adopted;
  Require(adopted.Start(Manual(), f.Backend()).writeSkipped && f.writes == 0 &&
          !adopted.HasPendingCleanup(), "unchanged external settings are not acquired");
  Require(adopted.Stop(std::nullopt, f.Backend()).success && f.values[L""] == Manual() &&
          f.writes == 0, "external settings remain after an unchanged start and stop");
  Require(adopted.Start(Manual(7891), f.Backend()).success, "adopted proxy port changes");
  Require(adopted.Stop(std::nullopt, f.Backend()).success && f.values[L""] == Manual(),
          "written new port restores the original external configuration");
  f.values[L""] = Manual();
  ProxySession residual;
  Require(residual.Stop(7890, f.Backend()).success && f.values[L""].flags == 1,
          "confirmed residual endpoint can be disabled safely");
  f.values[L""] = Original();
  ProxySession foreign;
  const auto before = f.writes;
  Require(foreign.Stop(7890, f.Backend()).success && f.writes == before &&
          f.values[L""] == Original(), "residual cleanup skips different proxy");
}

void CaptureFailureDoesNotModify() {
  Fixture f;
  f.ras = {L"VPN"};
  f.fail_read = L"VPN";
  f.values[L"VPN"] = Original();
  ProxySession session;
  const auto result = session.Start(Manual(), f.Backend());
  Require(!result.success && result.stage == "capture_ras" && result.errorCode == 5 &&
          f.writes == 0, "capture failure refuses partial modification");
  f.fail_read = L"never";
  f.enumeration_failure = true;
  Require(!session.Start(Manual(), f.Backend()).success && f.writes == 0,
          "enumeration failure refuses modification");
}

void PartialFailuresRemainRecoverable() {
  for (const bool partial : {false, true}) {
    Fixture f;
    f.ras = {L"VPN"};
    f.values[L"VPN"] = Original();
    f.fail_write = L"VPN";
    f.change_on_failure = !partial;
    f.partial_on_failure = partial;
    const auto original = f.values;
    ProxySession session;
    auto result = session.Start(Manual(), f.Backend());
    Require(!result.success && result.stage == "apply_ras" && result.errorCode == 5 &&
            result.pendingCleanup, "partial failure retains diagnostic and cleanup ownership");
    f.fail_write = L"never";
    Require(session.Stop(std::nullopt, f.Backend()).success && f.values == original,
            "partially applied default and RAS restore complete originals");
  }
  Fixture f;
  f.throw_on_write = true;
  ProxySession session;
  bool thrown = false;
  try { session.Start(Manual(), f.Backend()); }
  catch (const std::runtime_error&) { thrown = true; }
  Require(thrown, "exception expected");
  f.throw_on_write = false;
  Require(session.HasPendingCleanup() && session.Stop(std::nullopt, f.Backend()).success &&
          f.values[L""] == Original(), "write exception cannot lose original ownership");
}

void FailedReadbackAndRestoreRetry() {
  Fixture f;
  f.read_failure_after_write = true;
  ProxySession session;
  auto start = session.Start(Manual(), f.Backend());
  Require(!start.success && start.stage == "readback" && start.errorCode == 5 &&
          start.pendingCleanup, "failed readback retains attempted ownership");
  f.read_failure_after_write = false;
  f.fail_write = L"";
  auto stop = session.Stop(7890, f.Backend());
  Require(!stop.success && stop.stage == "restore_default" && stop.errorCode == 5 &&
          stop.pendingCleanup, "failed restore keeps snapshot");
  f.fail_write = L"never";
  Require(session.Stop(7890, f.Backend()).success && f.values[L""] == Original(),
          "restore retry uses original configuration");
  for (const bool manual_original : {false, true}) {
    Fixture partial;
    if (manual_original) partial.values[L""].flags = 3;
    const auto original = partial.values[L""];
    ProxySession pending;
    Require(pending.Start(Manual(), partial.Backend()).success, "partial restore starts");
    partial.fail_write = L"";
    partial.partial_on_failure = true;
    const auto failed = pending.Stop(7890, partial.Backend());
    Require(!failed.success && failed.pendingCleanup && !failed.restoreAbandoned,
            "partial restoration remains owned");
    partial.fail_write = L"never";
    Require(pending.Stop(7890, partial.Backend()).success && partial.values[L""] == original &&
            !pending.HasPendingCleanup(), "partial restoration retries full original settings");
  }
}

void NotificationFailureRetriesWithoutRepeatedWrite() {
  Fixture f;
  ProxySession session;
  Require(session.Start(Manual(), f.Backend()).success, "notification test starts");
  f.notification_failure = true;
  auto stop = session.Stop(std::nullopt, f.Backend());
  Require(!stop.success && stop.stage == "notify_refresh" && stop.errorCode == 5 &&
          session.HasPendingCleanup() && f.values[L""] == Original(), "failed notification remains pending");
  const auto writes = f.writes;
  f.notification_failure = false;
  stop = session.Stop(std::nullopt, f.Backend());
  Require(stop.success && stop.writeSkipped && f.writes == writes &&
          !session.HasPendingCleanup(), "notification retry does not rewrite restored settings");
}

void IndependentRasOwnership() {
  Fixture f;
  f.ras = {L"VPN"};
  f.values[L"VPN"] = {8, L"", L"office", L""};
  ProxySession session;
  Require(session.Start(Manual(), f.Backend()).success, "RAS ownership test starts");
  const auto foreign = ConnectionConfiguration{7, L"other:90", L"user", L"https://other/pac"};
  f.values[L"VPN"] = foreign;
  const auto stop = session.Stop(std::nullopt, f.Backend());
  Require(stop.success && stop.restoreAbandoned && f.values[L""] == Original() &&
          f.values[L"VPN"] == foreign, "each RAS connection has independent ownership");
}

void UnchangedFailedWriteDoesNotAcquireExternalProxy() {
  Fixture f;
  f.fail_write = L"";
  ProxySession session;
  const auto failed = session.Start(Manual(), f.Backend());
  Require(!failed.success && failed.stage == "apply_default" && failed.errorCode == 5 &&
          f.values[L""] == Original() && !session.HasPendingCleanup(),
          "confirmed unchanged failed write does not acquire ownership");
  f.values[L""] = Manual();
  f.fail_write = L"never";
  const auto writes = f.writes;
  const auto stopped = session.Stop(std::nullopt, f.Backend());
  Require(stopped.success && stopped.writeSkipped && f.writes == writes &&
          f.values[L""] == Manual(), "external same configuration survives ordinary stop");
}

void UnchangedRetryPreservesPreviouslyAppliedOwnership() {
  Fixture f;
  ProxySession session;
  Require(session.Start(Manual(), f.Backend()).success, "previous application succeeds");
  f.fail_write = L"";
  const auto failed = session.Start(Manual(7891), f.Backend());
  Require(!failed.success && failed.errorCode == 5 && session.HasPendingCleanup() &&
          f.values[L""] == Manual(), "unchanged retry retains the previous real application");
  f.fail_write = L"never";
  Require(session.Stop(std::nullopt, f.Backend()).success && f.values[L""] == Original() &&
          !session.HasPendingCleanup(), "previous owned application still restores its original snapshot");
}

void UnchangedRestoreDoesNotAcquireForeignMixedSettings() {
  Fixture f;
  ProxySession session;
  Require(session.Start(Manual(), f.Backend()).success, "foreign restoration scenario starts");
  f.fail_write = L"";
  const auto failed = session.Stop(std::nullopt, f.Backend());
  Require(!failed.success && failed.errorCode == 5 && session.HasPendingCleanup() &&
          f.values[L""] == Manual(), "unchanged failed restore keeps only prior application ownership");
  auto foreign = Manual();
  foreign.flags = Original().flags;
  f.values[L""] = foreign;
  f.fail_write = L"never";
  const auto writes = f.writes;
  const auto stopped = session.Stop(std::nullopt, f.Backend());
  Require(stopped.success && stopped.restoreAbandoned && stopped.writeSkipped &&
          f.writes == writes && f.values[L""] == foreign,
          "unchanged failed restore cannot claim subsequent foreign mixed settings");
}

void PartialAndUnknownWritesRemainOwned() {
  for (const bool unknown : {false, true}) {
    Fixture f;
    f.fail_write = L"";
    f.partial_on_failure = !unknown;
    f.change_on_failure = unknown;
    f.read_failure_after_write = unknown;
    ProxySession session;
    const auto failed = session.Start(Manual(), f.Backend());
    Require(!failed.success && failed.errorCode == 5 && session.HasPendingCleanup(),
            "actual partial writes and unknown readbacks retain recoverable ownership");
    f.fail_write = L"never";
    f.read_failure_after_write = false;
    Require(session.Stop(std::nullopt, f.Backend()).success && f.values[L""] == Original() &&
            !session.HasPendingCleanup(), "partial or unknown applications restore the original snapshot");
  }
}

void InactiveRasDoesNotBlockWifi() {
  Fixture f;
  f.ras = {L"old-broadband"};
  f.fail_read = L"old-broadband";
  auto backend = f.Backend();
  backend.discover = [](proxy::settings::ConnectionDiscovery& result, uint32_t& error) {
    result.inactive = {L"old-broadband"};
    error = 0;
    return true;
  };
  ProxySession session;
  const auto applied = session.Start(Manual(17980), backend);
  Require(applied.success && applied.activeRasCount == 0 && applied.inactiveRasSkippedCount == 1 &&
          f.writes == 1 && f.values[L""] == Manual(17980), "unused broken RAS is never read or written");
  Require(applied.connectionTrace[1].phase == "skip_inactive_ras" &&
          applied.connectionTrace[1].active == false, "inactive decision is logged");
  Require(session.Stop(std::nullopt, backend).success && f.values[L""] == Original(),
          "default connection is restored after inactive RAS skip");
}

void ActiveRasFailuresStillFail() {
  Fixture f;
  f.ras = {L"active-broadband"};
  f.values[L"active-broadband"] = Original();
  f.fail_write = L"active-broadband";
  auto backend = f.Backend();
  backend.discover = [](proxy::settings::ConnectionDiscovery& result, uint32_t& error) {
    result.active = {L"active-broadband"};error = 0;return true;
  };
  ProxySession session;
  const auto applied = session.Start(Manual(17980), backend);
  Require(!applied.success && applied.activeRasCount == 1 && applied.connectionName == L"active-broadband",
          "active dialup failures are not ignored");
  Require(session.Stop(std::nullopt, backend).success && f.values[L""] == Original(),
          "default application rolls back after active RAS failure");
}

void UnknownRasActivityDoesNotWrite() {
  Fixture f;
  auto backend = f.Backend();
  backend.discover = [](proxy::settings::ConnectionDiscovery&, uint32_t& error) { error = 6;return false; };
  ProxySession session;
  const auto result = session.Start(Manual(), backend);
  Require(!result.success && result.stage == "capture_ras" && result.errorCode == 6 && f.writes == 0,
          "unknown activity is not interpreted as no active RAS");
}

void RetainedInactivePacIsAcceptedAndRestored() {
  Fixture f;
  auto backend = f.Backend();
  const auto write = backend.write;
  backend.write = [&](const std::wstring& name, const ConnectionConfiguration& desired,
                      uint32_t& error, bool& fallback) {
    const auto pac = f.values[name].auto_config_url;
    const auto success = write(name, desired, error, fallback);
    if (success && (desired.flags & 4) == 0) f.values[name].auto_config_url = pac;
    return success;
  };
  ProxySession session;
  const auto result = session.Start(Manual(), backend);
  Require(result.success && f.values[L""].auto_config_url == Original().auto_config_url,
          "retained disabled PAC does not cause false apply failure");
  Require(std::any_of(result.connectionTrace.begin(), result.connectionTrace.end(), [](const auto& row) {
    return std::find(row.differences.begin(), row.differences.end(), "inactive_pac_url_ignored") != row.differences.end();
  }), "inactive PAC normalization is logged without its URL");
  const int writes = f.writes;
  Require(session.Start(Manual(), backend).success && f.writes == writes,
          "normalized repeat apply remains idempotent");
  Require(session.Stop(std::nullopt, backend).success && f.values[L""] == Original(),
          "original active PAC settings are restored");
}

void EffectiveFieldsRemainStrict() {
  const auto desired = Manual();
  for (int field = 0; field < 3; ++field) {
    auto actual = desired;
    if (field == 0) actual.flags |= 8;
    if (field == 1) actual.server = L"127.0.0.1:9000";
    if (field == 2) actual.bypass = L"foreign";
    Require(!proxy::settings::AppliedConfigurationMatches(actual, desired),
            "proxy flags server and bypass mismatches still fail");
  }
  auto actual = Original();actual.auto_config_url = L"https://foreign.example/pac";
  Require(!proxy::settings::AppliedConfigurationMatches(actual, Original()), "active PAC URL remains strict");
}

void TopologyChangesRequireRetry() {
  Fixture f;
  auto backend = f.Backend();
  int discoveries = 0;
  backend.discover = [&](proxy::settings::ConnectionDiscovery& result, uint32_t& error) {
    if (++discoveries > 1) result.active = {L"new-broadband"};
    error = 0;
    return true;
  };
  ProxySession session;
  const auto result = session.Start(Manual(), backend);
  Require(!result.success && result.stage == "capture_ras" && result.errorCode == 1237,
          "new active RAS during apply requires retry instead of false readiness");
  Require(session.Stop(std::nullopt, backend).success && f.values[L""] == Original(),
          "topology-change application remains recoverable");
}

void HistoricalEnumerationFailureIsDiagnosticOnly() {
  Fixture f;
  auto backend = f.Backend();
  backend.discover = [](proxy::settings::ConnectionDiscovery& result, uint32_t& error) {
    result.savedEnumerationError = 5;error = 0;return true;
  };
  ProxySession session;
  const auto result = session.Start(Manual(), backend);
  Require(result.success && result.savedRasEnumerationError == 5,
          "saved phonebook inventory failure cannot block verified active topology");
  Require(session.Stop(std::nullopt, backend).success, "phonebook inventory failure does not break cleanup");
}

void RegistryMismatchCanBeRepairedFromSnapshot() {
  for (const bool already_applied : {false, true}) {
    Fixture f;
    if (already_applied) f.values[L""] = Manual();
    const auto original = f.values[L""];
    auto backend = f.Backend();
    backend.capture = backend.read;
    const auto read = backend.read;
    const auto write = backend.write;
    bool registry_matches = false;
    backend.read = [&](const std::wstring& name, ConnectionConfiguration& value, uint32_t& error) {
      if (!registry_matches) { error = 13; return false; }
      return read(name, value, error);
    };
    backend.write = [&](const std::wstring& name, const ConnectionConfiguration& value,
                        uint32_t& error, bool& fallback) {
      const bool success = write(name, value, error, fallback);
      if (success) registry_matches = true;
      return success;
    };
    auto strict_backend = backend;
    strict_backend.capture = {};
    ProxySession previous_policy;
    const auto rejected = previous_policy.Start(Manual(), strict_backend);
    Require(!rejected.success && rejected.stage == "capture_default" &&
            rejected.errorCode == 13 && f.writes == 0,
            "previous strict snapshot policy reproduces W-PROXY-11 (13)");
    ProxySession session;
    const auto result = session.Start(Manual(), backend);
    Require(result.success && f.writes == 1 && !result.writeSkipped,
            "legacy registry mismatch is repaired even when WinINet already has the desired proxy");
    Require(std::any_of(result.connectionTrace.begin(), result.connectionTrace.end(),
            [](const proxy::settings::ConnectionTrace& trace) {
              return trace.phase == "preflight_readback" && !trace.success && trace.errorCode == 13;
            }), "repaired legacy mismatch remains visible in the operation trace");
    registry_matches = false;
    Require(session.Stop(std::nullopt, backend).success && f.values[L""] == original &&
            !session.HasPendingCleanup(), "cleanup repairs registry mismatch and restores the WinINet snapshot");
  }
}

void SnapshotDoesNotBypassAppliedVerification() {
  Fixture f;
  auto backend = f.Backend();
  backend.capture = backend.read;
  backend.read = [](const std::wstring&, ConnectionConfiguration&, uint32_t& error) {
    error = 13;
    return false;
  };
  ProxySession session;
  const auto result = session.Start(Manual(), backend);
  Require(!result.success && result.stage == "readback" && result.errorCode == 13 &&
          f.writes == 1 && session.HasPendingCleanup(),
          "post-write registry mismatch still fails and retains recoverable ownership");
  backend.read = backend.capture;
  Require(session.Stop(std::nullopt, backend).success && f.values[L""] == Original(),
          "failed verified application restores its original snapshot");
}

void UnreadableSnapshotDoesNotWrite() {
  Fixture f;
  auto backend = f.Backend();
  backend.capture = [](const std::wstring&, ConnectionConfiguration&, uint32_t& error) {
    error = 13;
    return false;
  };
  ProxySession session;
  const auto result = session.Start(Manual(), backend);
  Require(!result.success && result.stage == "capture_default" && result.errorCode == 13 &&
          f.writes == 0 && !session.HasPendingCleanup(),
          "invalid WinINet snapshot cannot be replaced with guessed settings");
}

void MismatchedRegistryDoesNotAcquireForeignSettings() {
  Fixture f;
  auto backend = f.Backend();
  backend.capture = backend.read;
  ProxySession session;
  Require(session.Start(Manual(), backend).success, "foreign snapshot test starts");
  const auto foreign = Manual(9000);
  f.values[L""] = foreign;
  backend.read = [](const std::wstring&, ConnectionConfiguration&, uint32_t& error) {
    error = 13;
    return false;
  };
  const auto writes = f.writes;
  const auto stopped = session.Stop(std::nullopt, backend);
  Require(stopped.success && stopped.restoreAbandoned && f.writes == writes &&
          f.values[L""] == foreign && !session.HasPendingCleanup(),
          "registry mismatch never grants ownership of another application's proxy");
}

void CustomerRasWriteAcknowledgedButNotApplied() {
  const std::wstring name = L"\u5bbd\u5e26\u8fde\u63a5";
  const auto desired = Manual(17980);
  for (const auto& ras_before : std::vector<ConnectionConfiguration>{
           {1, L"127.0.0.1:7890", L"old-exclusion", L""},
           {3, desired.server, L"old-exclusion", L""},
           {1, desired.server, L"old-exclusion", L""}}) {
    Fixture f;
    f.values[L""] = {1, L"127.0.0.1:7890", L"old-default-exclusion", L""};
    f.values[name] = ras_before;
    const auto original = f.values;
    auto backend = f.Backend();
    backend.discover = [&](proxy::settings::ConnectionDiscovery& discovery, uint32_t& error) {
      discovery.active = {name};
      error = 0;
      return true;
    };
    backend.capture = backend.read;
    const auto write = backend.write;
    backend.write = [&, write](const std::wstring& connection,
                               const ConnectionConfiguration& value,
                               uint32_t& error, bool& fallback) {
      if (connection.empty()) return write(connection, value, error, fallback);
      f.writes++;
      error = 0;
      return true;
    };
    ProxySession session;
    const auto result = session.Start(desired, backend);
    Require(!result.success && result.stage == "readback_mismatch" &&
            result.errorCode == 13 && result.connectionName == name &&
            result.activeRasCount == 1 && f.notifications == 1,
            "acknowledged but unapplied active RAS settings fail final verification after refresh");
    bool default_verified = false;
    bool ras_write_acknowledged = false;
    bool ras_final_mismatch = false;
    for (const auto& trace : result.connectionTrace) {
      if (trace.name.empty() && trace.phase == "verify") default_verified = trace.success;
      if (trace.name == name && trace.phase == "write") ras_write_acknowledged = trace.success;
      if (trace.name == name && trace.phase == "verify") {
        ras_final_mismatch = !trace.success && trace.errorCode == 13 &&
            std::find(trace.differences.begin(), trace.differences.end(), "proxy_bypass") != trace.differences.end();
      }
    }
    Require(default_verified && ras_write_acknowledged && ras_final_mismatch,
            "diagnostic trace distinguishes a successful API call from effective RAS settings");
    Require(session.Stop(std::nullopt, backend).success && f.values == original &&
            !session.HasPendingCleanup(),
            "failed application restores changed default settings without rewriting unchanged RAS settings");
  }
}

void VerificationWaitsForNotification() {
  for (const bool read_error : {false, true}) {
    Fixture f;
    auto backend = f.Backend();
    const auto read = backend.read;
    backend.read = [&, read](const std::wstring& name, ConnectionConfiguration& value,
                             uint32_t& error) {
      if (f.writes > 0 && f.notifications == 0) {
        if (read_error) { error = 13; return false; }
        value = Original();
        error = 0;
        return true;
      }
      return read(name, value, error);
    };
    ProxySession session;
    const auto result = session.Start(Manual(), backend);
    Require(result.success && f.notifications == 1 && f.writes == 1,
            "pre-refresh stale or unreadable settings cannot override a successful final verification");
    Require(std::any_of(result.connectionTrace.begin(), result.connectionTrace.end(), [](const auto& trace) {
      return trace.phase == "readback" && !trace.success;
    }), "pre-refresh failure evidence is retained after convergence");
    Require(session.Stop(std::nullopt, backend).success && f.values[L""] == Original(),
            "a post-refresh successful apply retains exact restoration ownership");
  }
}

void RestorationWaitsForNotification() {
  for (const bool read_error : {false, true}) {
    Fixture f;
    ProxySession session;
    Require(session.Start(Manual(), f.Backend()).success, "restoration timing fixture starts");
    auto backend = f.Backend();
    const auto read = backend.read;
    backend.read = [&, read](const std::wstring& name, ConnectionConfiguration& value,
                             uint32_t& error) {
      if (f.writes > 1 && f.notifications == 1) {
        if (read_error) { error = 13; return false; }
        value = Manual();
        error = 0;
        return true;
      }
      return read(name, value, error);
    };
    const auto result = session.Stop(std::nullopt, backend);
    Require(result.success && f.notifications == 2 && f.writes == 2 &&
            !session.HasPendingCleanup() && f.values[L""] == Original(),
            "restore verification occurs after refresh and releases only confirmed cleanup");
  }
}

struct RasRecoveryFixture {
  Fixture f;
  const std::wstring name = L"\u5bbd\u5e26\u8fde\u63a5";
  int fallbackWrites = 0;
  bool fallbackNoOp = false;
  bool fallbackDenied = false;

  RasRecoveryFixture() {
    f.ras = {name};
    f.values[name] = Original();
  }

  ConnectionBackend Backend() {
    auto backend = f.Backend();
    backend.capture = backend.read;
    backend.discover = [&](proxy::settings::ConnectionDiscovery& discovery, uint32_t& error) {
      discovery.active = f.ras;
      error = 0;
      return true;
    };
    const auto write = backend.write;
    backend.write = [&, write](const std::wstring& connection,
                               const ConnectionConfiguration& value,
                               uint32_t& error, bool& fallback) {
      if (connection.empty()) return write(connection, value, error, fallback);
      f.writes++;
      error = 0;
      return true;
    };
    backend.writeFallback = [&, write](const std::wstring& connection,
                                       const ConnectionConfiguration& value,
                                       uint32_t& error, bool& fallback) {
      Require(connection == name, "compatibility writer must not target the default connection");
      fallbackWrites++;
      fallback = true;
      if (fallbackDenied) { error = 5; return false; }
      if (fallbackNoOp) { error = 0; return true; }
      return write(connection, value, error, fallback);
    };
    return backend;
  }
};

void RasRecoveryVerifiesAndRestores() {
  for (const bool bypass_only : {false, true}) {
    RasRecoveryFixture fixture;
    auto& f = fixture.f;
    if (bypass_only) {
      f.values[fixture.name] = Manual(17980);
      f.values[fixture.name].bypass = L"old-exclusion";
    }
    const auto original = f.values;
    auto backend = fixture.Backend();
    ProxySession session;
    const auto result = session.Start(Manual(17980), backend);
    Require(result.success && result.fallbackUsed && fixture.fallbackWrites == 1 &&
            f.notifications == 2 && f.values[fixture.name] == Manual(17980),
            "one verified compatibility write repairs unchanged or partially applied active RAS settings");
    const auto writes = f.writes;
    Require(session.Start(Manual(17980), backend).success && f.writes == writes &&
            fixture.fallbackWrites == 1, "a verified RAS recovery is not repeatedly rewritten");
    Require(session.Stop(std::nullopt, backend).success && f.values == original &&
            fixture.fallbackWrites == 2 && !session.HasPendingCleanup(),
            "disconnect uses the successful compatibility writer to restore the original RAS snapshot");
  }
}

void RasRecoveryCannotHidePersistentFailure() {
  for (const bool denied : {false, true}) {
    RasRecoveryFixture fixture;
    fixture.fallbackDenied = denied;
    fixture.fallbackNoOp = !denied;
    const auto original = fixture.f.values;
    ProxySession session;
    const auto result = session.Start(Manual(17980), fixture.Backend());
    Require(!result.success && fixture.fallbackWrites == 1 &&
            result.errorCode == (denied ? 5u : 13u),
            "a denied or ineffective compatibility write cannot become a successful connection");
    Require(session.Stop(std::nullopt, fixture.Backend()).success && fixture.f.values == original,
            "failed recovery still restores only changed settings");
  }
}

void RasRecoveryYieldsToExternalChanges() {
  for (const bool topology_change : {false, true}) {
    RasRecoveryFixture fixture;
    auto backend = fixture.Backend();
    const auto notify = backend.notify;
    auto foreign = Original();
    foreign.server = L"foreign.example:9999";
    backend.notify = [&, notify](SessionOperationDetails& details) {
      if (topology_change) fixture.f.ras.clear();
      else fixture.f.values[fixture.name] = foreign;
      return notify(details);
    };
    ProxySession session;
    const auto result = session.Start(Manual(17980), backend);
    Require(!result.success && fixture.fallbackWrites == 0,
            "recovery never rewrites a foreign RAS snapshot or a changed active topology");
    Require(session.Stop(std::nullopt, backend).success &&
            fixture.f.values[fixture.name] == (topology_change ? Original() : foreign),
            "cleanup preserves foreign settings and disconnected RAS state");
  }
}

void RasRecoveryRequiresKnownActiveAndSuccessfulWrite() {
  for (const bool write_denied : {false, true}) {
    RasRecoveryFixture fixture;
    auto backend = fixture.Backend();
    if (write_denied) {
      const auto write = backend.write;
      backend.write = [&, write](const std::wstring& connection,
                                 const ConnectionConfiguration& value,
                                 uint32_t& error, bool& fallback) {
        if (connection.empty()) return write(connection, value, error, fallback);
        error = 5;
        return false;
      };
    } else backend.discover = {};
    ProxySession session;
    Require(!session.Start(Manual(17980), backend).success && fixture.fallbackWrites == 0,
            "unknown RAS activity or a real write error cannot trigger compatibility retries");
    Require(session.Stop(std::nullopt, backend).success, "nonrecoverable failures clean up owned settings");
  }
}

void RasRecoveryRechecksDefaultAndNotification() {
  for (const bool notification_failure : {false, true}) {
    RasRecoveryFixture fixture;
    auto backend = fixture.Backend();
    const auto fallback = backend.writeFallback;
    const auto notify = backend.notify;
    auto foreign = Original();
    foreign.server = L"external.example:8888";
    if (notification_failure) {
      backend.notify = [&, notify](SessionOperationDetails& details) {
        if (fixture.f.notifications == 1) {
          fixture.f.notifications++;
          details.stage = "notify_refresh";
          details.errorCode = 5;
          return false;
        }
        return notify(details);
      };
    } else {
      backend.writeFallback = [&, fallback](const std::wstring& connection,
                                            const ConnectionConfiguration& value,
                                            uint32_t& error, bool& used) {
        const bool result = fallback(connection, value, error, used);
        fixture.f.values[L""] = foreign;
        return result;
      };
    }
    ProxySession session;
    const auto result = session.Start(Manual(17980), backend);
    Require(!result.success && fixture.fallbackWrites == 1 &&
            result.stage == (notification_failure ? "notify_refresh" : "readback_mismatch"),
            "successful RAS retry cannot conceal a failed notification or changed default proxy");
    Require(session.Stop(std::nullopt, backend).success &&
            fixture.f.values[L""] == (notification_failure ? Original() : foreign) &&
            fixture.f.values[fixture.name] == Original() && !session.HasPendingCleanup(),
            "cleanup restores owned RAS settings without taking over a foreign default proxy");
  }
}

void RestorationFinalReadRemainsStrict() {
  Fixture f;
  ProxySession session;
  Require(session.Start(Manual(), f.Backend()).success, "restore final-read fixture starts");
  auto backend = f.Backend();
  const auto notify = backend.notify;
  auto foreign = Original();
  foreign.bypass = L"externally-changed";
  backend.notify = [&, notify](SessionOperationDetails& details) {
    f.values[L""] = foreign;
    return notify(details);
  };
  const auto stopped = session.Stop(std::nullopt, backend);
  Require(!stopped.success && stopped.stage == "readback_mismatch" && session.HasPendingCleanup(),
          "a pre-refresh successful restore cannot hide a mismatched final read");
  const auto writes = f.writes;
  const auto retried = session.Stop(std::nullopt, f.Backend());
  Require(retried.success && retried.restoreAbandoned && f.writes == writes &&
          f.values[L""] == foreign && !session.HasPendingCleanup(),
          "a later cleanup yields to foreign changes rather than force-restoring stale settings");
}

void RasRecoveryRequiresLosslessRestoration() {
  RasRecoveryFixture fixture;
  auto backend = fixture.Backend();
  backend.canRestoreFallback = [&](const std::wstring& name,
                                    const ConnectionConfiguration& configuration,
                                    uint32_t& error) {
    Require(name == fixture.name && configuration == Original(),
            "recovery checks the exact original snapshot before changing the encoding path");
    error = 1113;
    return false;
  };
  ProxySession session;
  const auto result = session.Start(Manual(17980), backend);
  Require(!result.success && result.errorCode == 1113 && fixture.fallbackWrites == 0,
          "an unrepresentable original snapshot cannot enter a compatibility path that cannot restore it");
  Require(session.Stop(std::nullopt, backend).success && fixture.f.values[L""] == Original() &&
          fixture.f.values[fixture.name] == Original(), "lossless-restoration refusal still cleans the ordinary write");
}

void RasRecoveryRechecksSnapshotAfterTopology() {
  RasRecoveryFixture fixture;
  auto backend = fixture.Backend();
  const auto discover = backend.discover;
  int discoveries = 0;
  auto foreign = Original();
  foreign.server = L"new-owner.example:9888";
  backend.discover = [&, discover](proxy::settings::ConnectionDiscovery& discovery, uint32_t& error) {
    if (++discoveries == 2) fixture.f.values[fixture.name] = foreign;
    return discover(discovery, error);
  };
  ProxySession session;
  const auto result = session.Start(Manual(17980), backend);
  Require(!result.success && fixture.fallbackWrites == 0 && fixture.f.values[fixture.name] == foreign,
          "a foreign change during topology checking is detected by the final prewrite read");
  Require(session.Stop(std::nullopt, backend).success && fixture.f.values[fixture.name] == foreign &&
          fixture.f.values[L""] == Original(), "cleanup preserves the new owner after a prewrite race");
}

}

#ifdef FENGWO_PROXY_SESSION_STANDALONE
int main() {
  try {
    CompleteSnapshotsAndRepeatedStart();
    PortChangesKeepOriginal();
    ExplicitReconnectRestoresLatestForeignSnapshot();
    ForeignChangesAndAlreadyRestored();
    SafeLegacyAndAdoptedProxy();
    CaptureFailureDoesNotModify();
    PartialFailuresRemainRecoverable();
    FailedReadbackAndRestoreRetry();
    NotificationFailureRetriesWithoutRepeatedWrite();
    IndependentRasOwnership();
    UnchangedFailedWriteDoesNotAcquireExternalProxy();
    UnchangedRetryPreservesPreviouslyAppliedOwnership();
    UnchangedRestoreDoesNotAcquireForeignMixedSettings();
    PartialAndUnknownWritesRemainOwned();
    InactiveRasDoesNotBlockWifi();
    ActiveRasFailuresStillFail();
    UnknownRasActivityDoesNotWrite();
    RetainedInactivePacIsAcceptedAndRestored();
    EffectiveFieldsRemainStrict();
    TopologyChangesRequireRetry();
    HistoricalEnumerationFailureIsDiagnosticOnly();
    RegistryMismatchCanBeRepairedFromSnapshot();
    SnapshotDoesNotBypassAppliedVerification();
    UnreadableSnapshotDoesNotWrite();
    MismatchedRegistryDoesNotAcquireForeignSettings();
    CustomerRasWriteAcknowledgedButNotApplied();
    VerificationWaitsForNotification();
    RestorationWaitsForNotification();
    RasRecoveryVerifiesAndRestores();
    RasRecoveryCannotHidePersistentFailure();
    RasRecoveryYieldsToExternalChanges();
    RasRecoveryRequiresKnownActiveAndSuccessfulWrite();
    RasRecoveryRechecksDefaultAndNotification();
    RestorationFinalReadRemainsStrict();
    RasRecoveryRequiresLosslessRestoration();
    RasRecoveryRechecksSnapshotAfterTopology();
    std::cout << "PASS: 36 proxy session suites\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAIL: " << error.what() << '\n';
    return 1;
  }
}
#else
#include <gtest/gtest.h>

TEST(ProxySession, CompleteSnapshotsAndRepeatedStart) { CompleteSnapshotsAndRepeatedStart(); }
TEST(ProxySession, PortChangesKeepOriginal) { PortChangesKeepOriginal(); }
TEST(ProxySession, ExplicitReconnectRestoresLatestForeignSnapshot) { ExplicitReconnectRestoresLatestForeignSnapshot(); }
TEST(ProxySession, ForeignChangesAndAlreadyRestored) { ForeignChangesAndAlreadyRestored(); }
TEST(ProxySession, SafeLegacyAndAdoptedProxy) { SafeLegacyAndAdoptedProxy(); }
TEST(ProxySession, CaptureFailureDoesNotModify) { CaptureFailureDoesNotModify(); }
TEST(ProxySession, PartialFailuresRemainRecoverable) { PartialFailuresRemainRecoverable(); }
TEST(ProxySession, FailedReadbackAndRestoreRetry) { FailedReadbackAndRestoreRetry(); }
TEST(ProxySession, NotificationFailureRetriesWithoutRepeatedWrite) { NotificationFailureRetriesWithoutRepeatedWrite(); }
TEST(ProxySession, IndependentRasOwnership) { IndependentRasOwnership(); }
TEST(ProxySession, UnchangedFailedWriteDoesNotAcquireExternalProxy) { UnchangedFailedWriteDoesNotAcquireExternalProxy(); }
TEST(ProxySession, UnchangedRetryPreservesPreviouslyAppliedOwnership) { UnchangedRetryPreservesPreviouslyAppliedOwnership(); }
TEST(ProxySession, UnchangedRestoreDoesNotAcquireForeignMixedSettings) { UnchangedRestoreDoesNotAcquireForeignMixedSettings(); }
TEST(ProxySession, PartialAndUnknownWritesRemainOwned) { PartialAndUnknownWritesRemainOwned(); }
TEST(ProxySession, InactiveRasDoesNotBlockWifi) { InactiveRasDoesNotBlockWifi(); }
TEST(ProxySession, ActiveRasFailuresStillFail) { ActiveRasFailuresStillFail(); }
TEST(ProxySession, UnknownRasActivityDoesNotWrite) { UnknownRasActivityDoesNotWrite(); }
TEST(ProxySession, RetainedInactivePacIsAcceptedAndRestored) { RetainedInactivePacIsAcceptedAndRestored(); }
TEST(ProxySession, EffectiveFieldsRemainStrict) { EffectiveFieldsRemainStrict(); }
TEST(ProxySession, TopologyChangesRequireRetry) { TopologyChangesRequireRetry(); }
TEST(ProxySession, HistoricalEnumerationFailureIsDiagnosticOnly) { HistoricalEnumerationFailureIsDiagnosticOnly(); }
TEST(ProxySession, RegistryMismatchCanBeRepairedFromSnapshot) { RegistryMismatchCanBeRepairedFromSnapshot(); }
TEST(ProxySession, SnapshotDoesNotBypassAppliedVerification) { SnapshotDoesNotBypassAppliedVerification(); }
TEST(ProxySession, UnreadableSnapshotDoesNotWrite) { UnreadableSnapshotDoesNotWrite(); }
TEST(ProxySession, MismatchedRegistryDoesNotAcquireForeignSettings) { MismatchedRegistryDoesNotAcquireForeignSettings(); }
TEST(ProxySession, CustomerRasWriteAcknowledgedButNotApplied) { CustomerRasWriteAcknowledgedButNotApplied(); }
TEST(ProxySession, VerificationWaitsForNotification) { VerificationWaitsForNotification(); }
TEST(ProxySession, RestorationWaitsForNotification) { RestorationWaitsForNotification(); }
TEST(ProxySession, RasRecoveryVerifiesAndRestores) { RasRecoveryVerifiesAndRestores(); }
TEST(ProxySession, RasRecoveryCannotHidePersistentFailure) { RasRecoveryCannotHidePersistentFailure(); }
TEST(ProxySession, RasRecoveryYieldsToExternalChanges) { RasRecoveryYieldsToExternalChanges(); }
TEST(ProxySession, RasRecoveryRequiresKnownActiveAndSuccessfulWrite) { RasRecoveryRequiresKnownActiveAndSuccessfulWrite(); }
TEST(ProxySession, RasRecoveryRechecksDefaultAndNotification) { RasRecoveryRechecksDefaultAndNotification(); }
TEST(ProxySession, RestorationFinalReadRemainsStrict) { RestorationFinalReadRemainsStrict(); }
TEST(ProxySession, RasRecoveryRequiresLosslessRestoration) { RasRecoveryRequiresLosslessRestoration(); }
TEST(ProxySession, RasRecoveryRechecksSnapshotAfterTopology) { RasRecoveryRechecksSnapshotAfterTopology(); }
#endif
