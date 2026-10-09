#ifndef FLUTTER_PLUGIN_PROXY_SESSION_H_
#define FLUTTER_PLUGIN_PROXY_SESSION_H_

#include <algorithm>
#include <cstdint>
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

struct SessionOperationDetails {
  bool success = false;
  std::string operation;
  std::string stage;
  uint32_t errorCode = 0;
  std::wstring connectionName;
  bool enabled = false;
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
};

struct ConnectionBackend {
  std::function<bool(std::vector<std::wstring>&, uint32_t&)> enumerate;
  std::function<bool(const std::wstring&, ConnectionConfiguration&, uint32_t&)> read;
  std::function<bool(const std::wstring&, const ConnectionConfiguration&,
                     uint32_t&, bool&)> write;
  std::function<bool(SessionOperationDetails&)> notify;
};

class ProxySession {
 public:
  SessionOperationDetails Start(const ConnectionConfiguration& desired,
                                const ConnectionBackend& backend) {
    SessionOperationDetails details;
    details.operation = "start";
    std::vector<std::wstring> names;
    if (!backend.enumerate(names, details.errorCode)) {
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
        details.stage = name.empty() ? "capture_default" : "capture_ras";
        details.connectionName = name;
        if (!name.empty()) details.rasFailureCount++;
        return Finish(details);
      }
      current.push_back({name, value});
    }
    bool wrote = false;
    for (const auto& item : current) {
      const auto& name = item.first;
      const auto& before = item.second;
      auto found = entries_.find(name);
      if (before == desired) {
        if (found == entries_.end()) {
          entries_.emplace(name, Entry{std::nullopt, desired, std::nullopt});
        } else {
          found->second.applied = desired;
          found->second.transition.reset();
          found->second.restoring = false;
        }
        continue;
      }
      if (found == entries_.end()) {
        found = entries_.emplace(name, Entry{before, std::nullopt, std::nullopt}).first;
      }
      auto& entry = found->second;
      if (!entry.original.has_value() && !IsOwned(entry, before)) entry.original = before;
      entry.restoring = false;
      entry.transition = Transition{before, desired};
      notification_pending_ = true;
      wrote = true;
      uint32_t write_error = 0;
      const bool written = backend.write(name, desired, write_error, details.fallbackUsed);
      ConnectionConfiguration readback;
      uint32_t read_error = 0;
      const bool read = backend.read(name, readback, read_error);
      if (read && IsMutation(readback, before, desired)) entry.applied = readback;
      if (!written || !read || readback != desired) {
        RecordFailure(details, !written ? (name.empty() ? "apply_default" : "apply_ras")
                      : !read ? "readback" : "readback_mismatch",
                      !written ? write_error : !read ? read_error : 13, name);
        if (name.empty()) break;
      } else {
        entry.applied = desired;
        entry.transition.reset();
      }
    }
    if (notification_pending_) {
      SessionOperationDetails notification;
      notification.operation = "start";
      if (backend.notify(notification)) {
        notification_pending_ = false;
      } else if (details.stage.empty()) {
        details.stage = notification.stage;
        details.errorCode = notification.errorCode;
      }
    }
    for (const auto& item : current) {
      ConnectionConfiguration readback;
      uint32_t error = 0;
      if (!backend.read(item.first, readback, error)) {
        RecordFailure(details, "readback", error, item.first);
      } else {
        if (item.first.empty()) SetReadback(details, readback);
        if (readback != desired) {
          RecordFailure(details, "readback_mismatch", 13, item.first);
        }
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
    if (entries_.empty()) {
      if (!expected_port.has_value() && !notification_pending_) {
        details.success = true;
        details.stage = "already_restored";
        details.writeSkipped = true;
        return Finish(details);
      }
      if (expected_port.has_value()) {
        std::vector<std::wstring> names;
        if (!backend.enumerate(names, details.errorCode)) {
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
            RecordFailure(details, "readback", error, name);
            continue;
          }
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
        RecordFailure(details, "readback", error, name);
        ++it;
        continue;
      }
      if (name.empty()) SetReadback(details, current);
      const auto restored = Restoration(entry, current);
      if (current == restored) {
        details.skippedCount++;
        it = entries_.erase(it);
        continue;
      }
      if (!IsOwned(entry, current)) {
        details.skippedCount++;
        details.restoreAbandoned = true;
        it = entries_.erase(it);
        continue;
      }
      if (!entry.restoring && expected_port.has_value() && current.HasManualProxy() &&
          current.server != L"127.0.0.1:" + std::to_wstring(*expected_port)) {
        details.skippedCount++;
        ++it;
        continue;
      }
      notification_pending_ = true;
      wrote = true;
      entry.applied = current;
      entry.restoring = true;
      entry.transition = Transition{current, restored};
      uint32_t write_error = 0;
      const bool written = backend.write(name, restored, write_error, details.fallbackUsed);
      ConnectionConfiguration readback;
      uint32_t read_error = 0;
      const bool read = backend.read(name, readback, read_error);
      if (read && name.empty()) SetReadback(details, readback);
      if (read && IsMutation(readback, current, restored)) entry.applied = readback;
      if (!written || !read || readback != restored) {
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
      } else if (details.stage.empty()) {
        details.stage = notification.stage;
        details.errorCode = notification.errorCode;
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
    return details;
  }

  std::map<std::wstring, Entry> entries_;
  bool notification_pending_ = false;
};

}

#endif
