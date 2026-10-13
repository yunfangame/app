#ifndef FLUTTER_PLUGIN_PROXY_SESSION_H_
#define FLUTTER_PLUGIN_PROXY_SESSION_H_

#include <algorithm>
#include <cstdint>
#include <chrono>
#include <functional>
#include <map>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace proxy::settings {

struct ConnectionConfiguration {
  uint32_t flags = 1;
  std::wstring server;
  std::wstring bypass;
  std::wstring auto_config_url;

  bool operator==(const ConnectionConfiguration& other) const {
    return flags == other.flags && server == other.server &&
        bypass == other.bypass && auto_config_url == other.auto_config_url;
  }

  bool operator!=(const ConnectionConfiguration& other) const {
    return !(*this == other);
  }

  bool HasManualProxy() const { return (flags & 2) != 0; }
};

inline bool AppliedConfigurationMatches(const ConnectionConfiguration& value,
                                        const ConnectionConfiguration& expected) {
  return value.flags == expected.flags && value.server == expected.server &&
      value.bypass == expected.bypass &&
      ((expected.flags & 4) == 0 || value.auto_config_url == expected.auto_config_url);
}

struct ConnectionDiscovery {
  std::vector<std::wstring> active;
  std::vector<std::wstring> inactive;
  uint32_t savedEnumerationError = 0;
};

struct ConnectionTrace {
  std::wstring name;
  std::string phase;
  bool success = false;
  uint32_t errorCode = 0;
  int64_t elapsedMs = 0;
  std::optional<bool> active;
  std::optional<uint32_t> expectedFlags;
  std::optional<uint32_t> actualFlags;
  std::vector<std::string> differences;
};

struct SessionOperationDetails {
  bool success = false;
  std::string operation;
  std::string stage;
  uint32_t errorCode = 0;
  std::wstring connectionName;
  bool enabled = false;
  std::optional<bool> automaticProxyEnabled;
  std::wstring server;
  bool fallbackUsed = false;
  int rasFailureCount = 0;
  std::string message;
  int snapshotCount = 0;
  int restoredCount = 0;
  int skippedCount = 0;
  bool pendingCleanup = false;
  bool writeSkipped = false;
  bool restoreAbandoned = false;
  int activeRasCount = 0;
  int inactiveRasSkippedCount = 0;
  uint32_t savedRasEnumerationError = 0;
  int traceDroppedCount = 0;
  std::vector<ConnectionTrace> connectionTrace;
  bool rasActivityKnown = false;
  std::vector<std::wstring> activeRasNames;
};

struct ConnectionBackend {
  std::function<bool(std::vector<std::wstring>&, uint32_t&)> enumerate;
  std::function<bool(const std::wstring&, ConnectionConfiguration&, uint32_t&)> read;
  std::function<bool(const std::wstring&, const ConnectionConfiguration&,
                     uint32_t&, bool&)> write;
  std::function<bool(SessionOperationDetails&)> notify;
  std::function<bool(ConnectionDiscovery&, uint32_t&)> discover = {};
};

class ProxySession {
 public:
  SessionOperationDetails Start(const ConnectionConfiguration& desired,
                                const ConnectionBackend& backend) {
    SessionOperationDetails details;
    details.operation = "start";
    std::vector<std::wstring> names;
    if (!Discover(details, backend, names)) {
      details.stage = "capture_ras";
      details.connectionName = L"RAS_ENUM";
      details.rasFailureCount = 1;
      return Finish(details);
    }
    names.insert(names.begin(), L"");
    std::vector<std::pair<std::wstring, ConnectionConfiguration>> current;
    for (const auto& name : names) {
      if (std::any_of(current.begin(), current.end(), [&](const auto& entry) {
            return entry.first == name;
          })) continue;
      ConnectionConfiguration value;
      if (!backend.read(name, value, details.errorCode)) {
        Trace(details, name, "capture", false, details.errorCode);
        details.stage = name.empty() ? "capture_default" : "capture_ras";
        details.connectionName = name;
        if (!name.empty()) details.rasFailureCount++;
        return Finish(details);
      }
      Trace(details, name, "capture", true, 0, &value);
      current.push_back({name, value});
    }
    bool wrote = false;
    for (const auto& item : current) {
      const auto& name = item.first;
      const auto& before = item.second;
      auto found = entries_.find(name);
      if (AppliedConfigurationMatches(before, desired)) {
        if (found != entries_.end() && IsOwned(found->second, before)) {
          found->second.applied = before;
          found->second.transition.reset();
          found->second.restoring = false;
        } else if (found != entries_.end()) {
          entries_.erase(found);
        }
        Trace(details, name, "already_applied", true, 0, &before, &desired);
        continue;
      }
      const auto previous = found == entries_.end()
          ? std::optional<Entry>() : std::make_optional(found->second);
      if (found == entries_.end()) {
        found = entries_.emplace(name, Entry{before, std::nullopt, std::nullopt}).first;
      }
      auto& entry = found->second;
      if (!IsOwned(entry, before)) entry.original = before;
      entry.restoring = false;
      entry.transition = Transition{before, desired};
      notification_pending_ = true;
      wrote = true;
      uint32_t write_error = 0;
      const bool written = backend.write(name, desired, write_error, details.fallbackUsed);
      Trace(details, name, "write", written, write_error, nullptr, &desired);
      ConnectionConfiguration readback;
      uint32_t read_error = 0;
      const bool read = backend.read(name, readback, read_error);
      if (!written && read && readback == before) {
        if (previous.has_value()) entry = *previous;
        else entries_.erase(found);
      } else if (read && ((written && AppliedConfigurationMatches(readback, desired)) ||
                         IsMutation(readback, before, desired))) {
        entry.applied = readback;
      }
      Trace(details, name, "readback", read && AppliedConfigurationMatches(readback, desired),
            !read ? read_error : AppliedConfigurationMatches(readback, desired) ? 0 : 13,
            read ? &readback : nullptr, &desired);
      if (!written || !read || !AppliedConfigurationMatches(readback, desired)) {
        RecordFailure(details, !written ? (name.empty() ? "apply_default" : "apply_ras")
                      : !read ? "readback" : "readback_mismatch",
                      !written ? write_error : !read ? read_error : 13, name);
        if (name.empty()) break;
      } else {
        entry.applied = readback;
        entry.transition.reset();
      }
    }
    if (notification_pending_) {
      SessionOperationDetails notification;
      notification.operation = "start";
      if (backend.notify(notification)) {
        notification_pending_ = false;
        Trace(details, L"", "notify", true, 0);
      } else {
        Trace(details, L"", notification.stage, false, notification.errorCode);
        if (details.stage.empty()) {
          details.stage = notification.stage;
          details.errorCode = notification.errorCode;
        }
      }
    }
    for (const auto& item : current) {
      ConnectionConfiguration readback;
      uint32_t error = 0;
      if (!backend.read(item.first, readback, error)) {
        Trace(details, item.first, "verify", false, error, nullptr, &desired);
        RecordFailure(details, "readback", error, item.first);
      } else {
        if (item.first.empty()) SetReadback(details, readback);
        const bool matched = AppliedConfigurationMatches(readback, desired);
        Trace(details, item.first, "verify", matched, matched ? 0 : 13, &readback, &desired);
        if (!matched) {
          RecordFailure(details, "readback_mismatch", 13, item.first);
        }
      }
    }
    if (backend.discover) {
      ConnectionDiscovery latest;
      uint32_t error = 0;
      if (!backend.discover(latest, error)) {
        Trace(details, L"RAS_ENUM", "verify_activity", false, error);
        RecordFailure(details, "capture_ras", error, L"RAS_ENUM");
      } else {
        auto active = latest.active;
        auto captured = names;
        captured.erase(std::remove(captured.begin(), captured.end(), L""), captured.end());
        std::sort(active.begin(), active.end());
        std::sort(captured.begin(), captured.end());
        const bool unchanged = active == captured;
        Trace(details, L"RAS_ENUM", "verify_activity", unchanged, unchanged ? 0 : 1237);
        if (!unchanged) RecordFailure(details, "capture_ras", 1237, L"RAS_ENUM");
      }
    }
    if (details.stage.empty()) {
      details.success = true;
      details.writeSkipped = !wrote;
      details.stage = wrote ? (details.fallbackUsed ? "verified_ansi_fallback" : "verified")
                            : "already_applied";
    }
    return Finish(details);
  }

  SessionOperationDetails Stop(std::optional<int> expected_port,
                               const ConnectionBackend& backend) {
    SessionOperationDetails details;
    details.operation = "stop";
    if (!entries_.empty() && backend.discover) {
      ConnectionDiscovery activity;
      uint32_t error = 0;
      if (backend.discover(activity, error)) {
        details.rasActivityKnown = true;
        details.activeRasNames = activity.active;
        details.activeRasCount = static_cast<int>(activity.active.size());
        details.inactiveRasSkippedCount = static_cast<int>(activity.inactive.size());
        details.savedRasEnumerationError = activity.savedEnumerationError;
        Trace(details, L"RAS_ENUM", "restore_activity", true, 0);
      } else {
        Trace(details, L"RAS_ENUM", "restore_activity_unknown", false, error);
      }
    }
    if (entries_.empty()) {
      if (!expected_port.has_value() && !notification_pending_) {
        details.success = true;
        details.stage = "already_restored";
        details.writeSkipped = true;
        return Finish(details);
      }
      if (expected_port.has_value()) {
        std::vector<std::wstring> names;
        if (!Discover(details, backend, names)) {
          details.stage = "capture_ras";
          details.connectionName = L"RAS_ENUM";
          details.rasFailureCount = 1;
          return Finish(details);
        }
        names.insert(names.begin(), L"");
        const auto expected = L"127.0.0.1:" + std::to_wstring(*expected_port);
        for (const auto& name : names) {
          ConnectionConfiguration current;
          uint32_t error = 0;
          if (!backend.read(name, current, error)) {
            Trace(details, name, "residual_capture", false, error);
            RecordFailure(details, "readback", error, name);
            continue;
          }
          Trace(details, name, "residual_capture", true, 0, &current);
          if (name.empty()) SetReadback(details, current);
          if (current.flags == 3 && current.server == expected && current.auto_config_url.empty()) {
            entries_.emplace(name, Entry{std::nullopt, current, std::nullopt});
          } else {
            details.skippedCount++;
          }
        }
      }
    }
    bool wrote = false;
    for (auto it = entries_.begin(); it != entries_.end();) {
      const auto name = it->first;
      auto& entry = it->second;
      ConnectionConfiguration current;
      uint32_t error = 0;
      if (!backend.read(name, current, error)) {
        Trace(details, name, "restore_capture", false, error);
        RecordFailure(details, "readback", error, name);
        ++it;
        continue;
      }
      Trace(details, name, "restore_capture", true, 0, &current);
      if (name.empty()) SetReadback(details, current);
      const auto restored = Restoration(entry, current);
      if (current == restored) {
        Trace(details, name, "already_restored", true, 0, &current, &restored);
        details.skippedCount++;
        it = entries_.erase(it);
        continue;
      }
      if (!IsOwned(entry, current)) {
        Trace(details, name, "restore_skipped_foreign", true, 0, &current, &restored);
        details.skippedCount++;
        details.restoreAbandoned = true;
        it = entries_.erase(it);
        continue;
      }
      if (!entry.restoring && expected_port.has_value() && current.HasManualProxy() &&
          current.server != L"127.0.0.1:" + std::to_wstring(*expected_port)) {
        Trace(details, name, "restore_skipped_stale_port", true, 0, &current, &restored);
        details.skippedCount++;
        ++it;
        continue;
      }
      const auto previous = entry;
      notification_pending_ = true;
      wrote = true;
      entry.applied = current;
      entry.restoring = true;
      entry.transition = Transition{current, restored};
      uint32_t write_error = 0;
      const bool written = backend.write(name, restored, write_error, details.fallbackUsed);
      Trace(details, name, "restore_write", written, write_error, nullptr, &restored);
      ConnectionConfiguration readback;
      uint32_t read_error = 0;
      const bool read = backend.read(name, readback, read_error);
      if (read && name.empty()) SetReadback(details, readback);
      if (!written && read && readback == current) {
        entry = previous;
      } else if (read && IsMutation(readback, current, restored)) {
        entry.applied = readback;
      }
      const bool matched = read && AppliedConfigurationMatches(readback, restored);
      Trace(details, name, "restore_verify", matched, !read ? read_error : matched ? 0 : 13,
            read ? &readback : nullptr, &restored);
      if (!written || !matched) {
        RecordFailure(details, !written ? (name.empty() ? "restore_default" : "restore_ras")
                      : !read ? "readback" : "readback_mismatch",
                      !written ? write_error : !read ? read_error : 13, name);
        ++it;
      } else {
        details.restoredCount++;
        it = entries_.erase(it);
      }
    }
    if (notification_pending_) {
      SessionOperationDetails notification;
      notification.operation = "stop";
      if (backend.notify(notification)) {
        notification_pending_ = false;
        Trace(details, L"", "restore_notify", true, 0);
      } else {
        Trace(details, L"", notification.stage, false, notification.errorCode);
        if (details.stage.empty()) {
          details.stage = notification.stage;
          details.errorCode = notification.errorCode;
        }
      }
    }
    if (details.stage.empty()) {
      details.success = true;
      details.writeSkipped = !wrote;
      details.stage = wrote ? "restored" : details.skippedCount > 0
          ? "skipped_foreign_or_restored" : "already_restored";
    }
    return Finish(details);
  }

  bool HasPendingCleanup() const { return !entries_.empty() || notification_pending_; }

 private:
  static bool Discover(SessionOperationDetails& details, const ConnectionBackend& backend,
                       std::vector<std::wstring>& names) {
    if (!backend.discover) return backend.enumerate(names, details.errorCode);
    ConnectionDiscovery discovery;
    if (!backend.discover(discovery, details.errorCode)) {
      Trace(details, L"RAS_ENUM", "discover_activity", false, details.errorCode);
      return false;
    }
    names = discovery.active;
    details.rasActivityKnown = true;
    details.activeRasNames = discovery.active;
    details.activeRasCount = static_cast<int>(discovery.active.size());
    details.inactiveRasSkippedCount = static_cast<int>(discovery.inactive.size());
    details.savedRasEnumerationError = discovery.savedEnumerationError;
    Trace(details, L"RAS_ENUM", "discover_activity", true, 0);
    for (size_t index = 0; index < discovery.inactive.size(); ++index) {
      if (index >= 16) { details.traceDroppedCount++; continue; }
      Trace(details, discovery.inactive[index], "skip_inactive_ras", true, 0);
    }
    return true;
  }

  static void Trace(SessionOperationDetails& details, const std::wstring& name,
                    const std::string& phase, bool success, uint32_t error,
                    const ConnectionConfiguration* actual = nullptr,
                    const ConnectionConfiguration* expected = nullptr) {
    if (details.connectionTrace.size() >= 128) {
      details.traceDroppedCount++;
      return;
    }
    ConnectionTrace trace;
    trace.name = name;
    trace.phase = phase;
    trace.success = success;
    trace.errorCode = error;
    trace.elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
    if (details.rasActivityKnown && !name.empty() && name != L"RAS_ENUM") {
      trace.active = std::find(details.activeRasNames.begin(), details.activeRasNames.end(), name)
          != details.activeRasNames.end();
    }
    if (expected) trace.expectedFlags = expected->flags;
    if (actual) trace.actualFlags = actual->flags;
    if (actual && expected) {
      if (actual->flags != expected->flags) trace.differences.push_back("flags");
      if (actual->server != expected->server) trace.differences.push_back("proxy_server");
      if (actual->bypass != expected->bypass) trace.differences.push_back("proxy_bypass");
      if (actual->auto_config_url != expected->auto_config_url) {
        trace.differences.push_back((expected->flags & 4) == 0 ? "inactive_pac_url_ignored" : "pac_url");
      }
    }
    details.connectionTrace.push_back(std::move(trace));
  }

  struct Transition {
    ConnectionConfiguration before;
    ConnectionConfiguration desired;
  };

  struct Entry {
    std::optional<ConnectionConfiguration> original;
    std::optional<ConnectionConfiguration> applied;
    std::optional<Transition> transition;
    bool restoring = false;
  };

  static bool IsMutation(const ConnectionConfiguration& value,
                         const ConnectionConfiguration& before,
                         const ConnectionConfiguration& desired) {
    if (value == desired) return true;
    return value != before &&
        (value.server == before.server || value.server == desired.server) &&
        (value.flags == before.flags || value.flags == desired.flags) &&
        (value.bypass == before.bypass || value.bypass == desired.bypass) &&
        (value.auto_config_url == before.auto_config_url ||
         value.auto_config_url == desired.auto_config_url);
  }

  static bool IsOwned(const Entry& entry, const ConnectionConfiguration& current) {
    if (entry.applied.has_value() && current == *entry.applied) return true;
    return entry.transition.has_value() &&
        IsMutation(current, entry.transition->before, entry.transition->desired);
  }

  static ConnectionConfiguration Restoration(const Entry& entry,
                                             const ConnectionConfiguration& current) {
    if (entry.original.has_value()) return *entry.original;
    auto result = current;
    result.flags = (result.flags & ~uint32_t{2}) | 1;
    return result;
  }

  static void SetReadback(SessionOperationDetails& details,
                          const ConnectionConfiguration& current) {
    details.enabled = current.HasManualProxy();
    details.automaticProxyEnabled = (current.flags & 12) != 0;
    details.server = current.server;
  }

  static void RecordFailure(SessionOperationDetails& details,
                            const std::string& stage, uint32_t error,
                            const std::wstring& name) {
    if (!name.empty()) details.rasFailureCount++;
    if (!details.stage.empty()) return;
    details.stage = stage;
    details.errorCode = error;
    details.connectionName = name;
  }

  SessionOperationDetails Finish(SessionOperationDetails details) const {
    details.snapshotCount = static_cast<int>(entries_.size());
    details.pendingCleanup = HasPendingCleanup();
    if (!details.connectionTrace.empty()) {
      const auto started = details.connectionTrace.front().elapsedMs;
      for (auto& trace : details.connectionTrace) trace.elapsedMs -= started;
    }
    return details;
  }

  std::map<std::wstring, Entry> entries_;
  bool notification_pending_ = false;
};

}

#endif
