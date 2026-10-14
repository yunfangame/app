#ifndef FLUTTER_PLUGIN_PROXY_RAS_H_
#define FLUTTER_PLUGIN_PROXY_RAS_H_

#include <windows.h>
#include <ras.h>
#include <raserror.h>

#include "proxy_session.h"

namespace proxy::settings {

inline bool DiscoverActiveConnections(
    std::vector<std::wstring>& active, uint32_t& error,
    decltype(&RasEnumConnectionsW) enumerate = RasEnumConnectionsW,
    decltype(&RasGetConnectStatusW) statusOf = RasGetConnectStatusW) {
  active.clear();
  for (int topology_attempt = 0; topology_attempt < 4; ++topology_attempt) {
    std::vector<RASCONNW> connections(1);
    DWORD size = sizeof(RASCONNW);
    DWORD count = 0;
    DWORD status = ERROR_SUCCESS;
    for (int attempt = 0; attempt < 4; ++attempt) {
      for (auto& connection : connections) connection.dwSize = sizeof(RASCONNW);
      size = static_cast<DWORD>(connections.size() * sizeof(RASCONNW));
      status = enumerate(connections.data(), &size, &count);
      if (status != ERROR_BUFFER_TOO_SMALL) break;
      const size_t required = (static_cast<size_t>(size) + sizeof(RASCONNW) - 1) /
          sizeof(RASCONNW);
      if (required == 0 || required > 1024) {
        error = ERROR_INVALID_DATA;
        return false;
      }
      connections.resize(required);
    }
    if (status != ERROR_SUCCESS || count > connections.size()) {
      error = status == ERROR_SUCCESS ? ERROR_INVALID_DATA : status;
      return false;
    }
    std::vector<std::wstring> observed;
    bool changed = false;
    for (DWORD i = 0; i < count; ++i) {
      RASCONNSTATUSW state = {};
      state.dwSize = sizeof(state);
      status = statusOf(connections[i].hrasconn, &state);
      if (status == ERROR_INVALID_HANDLE || status == ERROR_PORT_NOT_OPEN) {
        changed = true;
        break;
      }
      if (status != ERROR_SUCCESS) {
        error = status;
        return false;
      }
      if (state.rasconnstate != RASCS_Connected) continue;
      const std::wstring name = connections[i].szEntryName;
      if (name.empty()) {
        error = ERROR_INVALID_DATA;
        return false;
      }
      if (std::find(observed.begin(), observed.end(), name) == observed.end())
        observed.push_back(name);
    }
    if (changed) continue;
    active = std::move(observed);
    error = ERROR_SUCCESS;
    return true;
  }
  error = ERROR_RETRY;
  return false;
}

}

#endif
