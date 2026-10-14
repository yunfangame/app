#include "../proxy_ras.h"

#include <gtest/gtest.h>

namespace {

struct RasFixture {
  std::vector<std::wstring> names;
  std::vector<RASCONNSTATE> states;
  DWORD status_error = ERROR_SUCCESS;
  DWORD enumeration_error = ERROR_SUCCESS;
  bool disappear_after_retry = false;
  int enumerations = 0;
  static RasFixture* current;

  static DWORD WINAPI Enumerate(LPRASCONNW connections, LPDWORD size, LPDWORD count) {
    auto& f = *current;
    ++f.enumerations;
    if (f.enumeration_error != ERROR_SUCCESS) return f.enumeration_error;
    *count = f.disappear_after_retry && f.enumerations > 1 ? 0 : static_cast<DWORD>(f.names.size());
    const DWORD required = *count * sizeof(RASCONNW);
    if (*size < required) { *size = required; return ERROR_BUFFER_TOO_SMALL; }
    for (DWORD i = 0; i < *count; ++i) {
      EXPECT_EQ(connections[i].dwSize, sizeof(RASCONNW));
      connections[i].hrasconn = reinterpret_cast<HRASCONN>(static_cast<uintptr_t>(i + 1));
      const auto length = std::min(f.names[i].size(), static_cast<size_t>(RAS_MaxEntryName));
      std::copy_n(f.names[i].data(), length, connections[i].szEntryName);
      connections[i].szEntryName[length] = L'\0';
    }
    *size = required;
    return ERROR_SUCCESS;
  }

  static DWORD WINAPI Status(HRASCONN handle, LPRASCONNSTATUSW status) {
    auto& f = *current;
    EXPECT_EQ(status->dwSize, sizeof(RASCONNSTATUSW));
    if (f.status_error != ERROR_SUCCESS) return f.status_error;
    status->rasconnstate = f.states.at(reinterpret_cast<uintptr_t>(handle) - 1);
    return ERROR_SUCCESS;
  }

  bool Discover(std::vector<std::wstring>& active, uint32_t& error) {
    current = this;
    return proxy::settings::DiscoverActiveConnections(active, error, Enumerate, Status);
  }
};

RasFixture* RasFixture::current = nullptr;

TEST(ProxyRas, TransitionalUnnamedConnectionDoesNotBlockDefaultProxy) {
  RasFixture f;
  f.names = {L""};
  f.states = {RASCS_Authenticate};
  std::vector<std::wstring> active;
  uint32_t error = 13;
  EXPECT_TRUE(f.Discover(active, error));
  EXPECT_TRUE(active.empty());
  EXPECT_EQ(error, ERROR_SUCCESS);
}

TEST(ProxyRas, OnlyEstablishedConnectionsAreActive) {
  RasFixture f;
  f.names = {L"dialing", L"connected", L"disconnected", L"connected"};
  f.states = {RASCS_OpenPort, RASCS_Connected, RASCS_Disconnected, RASCS_Connected};
  std::vector<std::wstring> active;
  uint32_t error = 0;
  EXPECT_TRUE(f.Discover(active, error));
  EXPECT_EQ(active, std::vector<std::wstring>({L"connected"}));
}

TEST(ProxyRas, DisappearingHandleReenumerates) {
  for (DWORD failure : std::vector<DWORD>{ERROR_INVALID_HANDLE, ERROR_PORT_NOT_OPEN}) {
    RasFixture f;
    f.names = {L"disconnecting"};
    f.status_error = failure;
    f.disappear_after_retry = true;
    std::vector<std::wstring> active{L"stale"};
    uint32_t error = 0;
    EXPECT_TRUE(f.Discover(active, error));
    EXPECT_TRUE(active.empty());
    EXPECT_EQ(f.enumerations, 2);
  }
}

TEST(ProxyRas, UnstableTopologyIsBoundedAndFails) {
  RasFixture f;
  f.names = {L"unstable"};
  f.status_error = ERROR_INVALID_HANDLE;
  std::vector<std::wstring> active;
  uint32_t error = 0;
  EXPECT_FALSE(f.Discover(active, error));
  EXPECT_EQ(error, ERROR_RETRY);
  EXPECT_EQ(f.enumerations, 4);
}

TEST(ProxyRas, RealFailuresAreNotReportedAsNoConnections) {
  for (const bool enumeration : {false, true}) {
    RasFixture f;
    f.names = {L"vpn"};
    if (enumeration) f.enumeration_error = ERROR_INVALID_DATA;
    else f.status_error = ERROR_INVALID_DATA;
    std::vector<std::wstring> active;
    uint32_t error = 0;
    EXPECT_FALSE(f.Discover(active, error));
    EXPECT_EQ(error, ERROR_INVALID_DATA);
  }
}

TEST(ProxyRas, EstablishedUnnamedConnectionStillFails) {
  RasFixture f;
  f.names = {L""};
  f.states = {RASCS_Connected};
  std::vector<std::wstring> active;
  uint32_t error = 0;
  EXPECT_FALSE(f.Discover(active, error));
  EXPECT_EQ(error, ERROR_INVALID_DATA);
}

}
