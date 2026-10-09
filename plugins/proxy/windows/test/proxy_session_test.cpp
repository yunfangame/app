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
  Require(adopted.Start(Manual(), f.Backend()).writeSkipped && f.writes == 0,
          "existing exact client configuration adopted without fabricated original");
  Require(adopted.Start(Manual(7891), f.Backend()).success, "adopted proxy port changes");
  Require(adopted.Stop(7891, f.Backend()).success && f.values[L""].flags == 1,
          "adopted configuration disables instead of restoring old dead proxy");
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

}

int main() {
  try {
    CompleteSnapshotsAndRepeatedStart();
    PortChangesKeepOriginal();
    ForeignChangesAndAlreadyRestored();
    SafeLegacyAndAdoptedProxy();
    CaptureFailureDoesNotModify();
    PartialFailuresRemainRecoverable();
    FailedReadbackAndRestoreRetry();
    NotificationFailureRetriesWithoutRepeatedWrite();
    IndependentRasOwnership();
    std::cout << "PASS: 9 proxy session suites\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAIL: " << error.what() << '\n';
    return 1;
  }
}
