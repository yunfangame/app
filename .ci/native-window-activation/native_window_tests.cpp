#include <windows.h>
#include <sddl.h>

#include <filesystem>
#include <cstdint>
#include <fstream>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#include "window_visibility.h"

namespace {

struct Result {
  std::string name;
  bool passed;
  bool skipped;
  std::string error;
};

std::vector<Result> results;
std::filesystem::path report_path;
DWORD sender_integrity_rid = 0;
DWORD receiver_integrity_rid = 0;
bool medium_mutex_probe_confirmed = false;

class EnvironmentUnavailable : public std::runtime_error {
 public:
  using std::runtime_error::runtime_error;
};

class OwnedHandle {
 public:
  explicit OwnedHandle(HANDLE value) : value(value) {}
  ~OwnedHandle() {
    if (value != nullptr && value != INVALID_HANDLE_VALUE) CloseHandle(value);
  }
  OwnedHandle(const OwnedHandle&) = delete;
  OwnedHandle& operator=(const OwnedHandle&) = delete;
  HANDLE value;
};

void Require(bool value, const std::string& message) {
  if (!value) {
    throw std::runtime_error(message + " (Win32 error " +
                             std::to_string(GetLastError()) + ")");
  }
}

std::string JsonEscape(const std::string& input) {
  std::string output;
  for (const char c : input) {
    if (c == '\\' || c == '"') {
      output += '\\';
      output += c;
    } else if (c == '\n' || c == '\r') {
      output += ' ';
    } else {
      output += c;
    }
  }
  return output;
}

void SaveResults() {
  std::ofstream out(report_path);
  size_t passed = 0;
  size_t skipped = 0;
  for (const auto& result : results) {
    if (result.passed) {
      ++passed;
    }
    if (result.skipped) ++skipped;
  }
  out << "{\"synthetic_data_only\":true,\"production_module_compiled\":true,"
         "\"test_count\":" << results.size()
      << ",\"passed_count\":" << passed
      << ",\"failed_count\":" << (results.size() - passed - skipped)
      << ",\"skipped_count\":" << skipped
      << ",\"receiver_integrity_rid\":" << receiver_integrity_rid
      << ",\"sender_integrity_rid\":" << sender_integrity_rid
      << ",\"medium_mutex_read_only_probe_confirmed\":"
      << (medium_mutex_probe_confirmed ? "true" : "false")
      << ",\"tests\":[";
  bool first = true;
  for (const auto& result : results) {
    if (!first) {
      out << ',';
    }
    first = false;
    out << "{\"name\":\"" << JsonEscape(result.name)
        << "\",\"passed\":" << (result.passed ? "true" : "false")
        << ",\"skipped\":" << (result.skipped ? "true" : "false")
        << ",\"error\":\"" << JsonEscape(result.error) << "\"}";
  }
  out << "]}\n";
}

void Run(const std::string& name, const std::function<void()>& body) {
  try {
    body();
    results.push_back({name, true, false, ""});
    std::cout << "PASS: " << name << std::endl;
  } catch (const EnvironmentUnavailable& error) {
    results.push_back({name, false, true, error.what()});
    std::cout << "UNVERIFIED: " << name << ": " << error.what() << std::endl;
  } catch (const std::exception& error) {
    results.push_back({name, false, false, error.what()});
    std::cout << "FAIL: " << name << ": " << error.what() << std::endl;
  }
  SaveResults();
}

bool SameRect(const RECT& a, const RECT& b) {
  return a.left == b.left && a.top == b.top && a.right == b.right &&
         a.bottom == b.bottom;
}

bool Contained(const RECT& window, const RECT& area) {
  return window.right > window.left && window.bottom > window.top &&
         window.left >= area.left && window.top >= area.top &&
         window.right <= area.right && window.bottom <= area.bottom;
}

RECT CurrentWorkArea() {
  POINT cursor{};
  Require(GetCursorPos(&cursor) != FALSE, "GetCursorPos failed");
  const HMONITOR monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  Require(GetMonitorInfoW(monitor, &info) != FALSE, "GetMonitorInfo failed");
  return info.rcWork;
}

void PumpMessages() {
  MSG message{};
  while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
}

DWORD IntegrityRid(HANDLE process) {
  HANDLE raw_token = nullptr;
  Require(OpenProcessToken(process, TOKEN_QUERY, &raw_token) != FALSE,
          "OpenProcessToken failed");
  OwnedHandle token(raw_token);
  DWORD size = 0;
  GetTokenInformation(token.value, TokenIntegrityLevel, nullptr, 0, &size);
  Require(size != 0, "Integrity level size unavailable");
  std::vector<BYTE> data(size);
  Require(GetTokenInformation(token.value, TokenIntegrityLevel, data.data(),
                              size, &size) != FALSE,
          "Integrity level unavailable");
  const auto* label = reinterpret_cast<TOKEN_MANDATORY_LABEL*>(data.data());
  Require(IsValidSid(label->Label.Sid) != FALSE, "Invalid integrity SID");
  const BYTE count = *GetSidSubAuthorityCount(label->Label.Sid);
  Require(count > 0, "Integrity SID has no RID");
  return *GetSidSubAuthority(label->Label.Sid, count - 1);
}

void PostFromMediumIntegrityChild(HWND target, const std::wstring& mutex_name) {
  receiver_integrity_rid = IntegrityRid(GetCurrentProcess());
  if (receiver_integrity_rid < SECURITY_MANDATORY_HIGH_RID) {
    throw EnvironmentUnavailable("CI receiver is not high integrity");
  }
  HANDLE raw_token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(),
                        TOKEN_DUPLICATE | TOKEN_QUERY | TOKEN_ASSIGN_PRIMARY,
                        &raw_token)) {
    throw EnvironmentUnavailable("Cannot open token for restricted sender");
  }
  OwnedHandle token(raw_token);
  BYTE administrator_sid[SECURITY_MAX_SID_SIZE]{};
  DWORD sid_size = sizeof(administrator_sid);
  Require(CreateWellKnownSid(WinBuiltinAdministratorsSid, nullptr,
                              administrator_sid, &sid_size) != FALSE,
          "Cannot create administrator SID");
  SID_AND_ATTRIBUTES disabled{administrator_sid, 0};
  HANDLE raw_restricted = nullptr;
  if (!CreateRestrictedToken(token.value, DISABLE_MAX_PRIVILEGE, 1, &disabled,
                              0, nullptr, 0, nullptr, &raw_restricted)) {
    throw EnvironmentUnavailable("CreateRestrictedToken unavailable: " +
                                 std::to_string(GetLastError()));
  }
  OwnedHandle restricted(raw_restricted);
  PSID medium_sid = nullptr;
  Require(ConvertStringSidToSidW(L"S-1-16-8192", &medium_sid) != FALSE,
          "Cannot create medium integrity SID");
  TOKEN_MANDATORY_LABEL label{};
  label.Label.Sid = medium_sid;
  label.Label.Attributes = SE_GROUP_INTEGRITY;
  const BOOL assigned = SetTokenInformation(
      restricted.value, TokenIntegrityLevel, &label,
      static_cast<DWORD>(sizeof(label)) + GetLengthSid(medium_sid));
  const DWORD assign_error = GetLastError();
  LocalFree(medium_sid);
  if (!assigned) {
    throw EnvironmentUnavailable("Cannot assign medium integrity: " +
                                 std::to_string(assign_error));
  }
  std::vector<wchar_t> executable(32768);
  const DWORD length = GetModuleFileNameW(
      nullptr, executable.data(), static_cast<DWORD>(executable.size()));
  Require(length > 0 && length < executable.size(), "Executable path unavailable");
  const std::wstring command = L"\"" + std::wstring(executable.data()) +
      L"\" --medium-post " +
      std::to_wstring(reinterpret_cast<std::uintptr_t>(target)) +
      L" \"" + mutex_name + L"\"";
  std::vector<wchar_t> arguments(command.begin(), command.end());
  arguments.push_back(L'\0');
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  wchar_t desktop[] = L"winsta0\\default";
  startup.lpDesktop = desktop;
  PROCESS_INFORMATION child{};
  const DWORD flags = CREATE_SUSPENDED | CREATE_NO_WINDOW;
  BOOL created = CreateProcessAsUserW(
      restricted.value, executable.data(), arguments.data(), nullptr, nullptr,
      FALSE, flags, nullptr, nullptr, &startup, &child);
  DWORD create_error = GetLastError();
  if (!created && create_error == ERROR_PRIVILEGE_NOT_HELD) {
    arguments.assign(command.begin(), command.end());
    arguments.push_back(L'\0');
    created = CreateProcessWithTokenW(
        restricted.value, 0, executable.data(), arguments.data(), flags,
        nullptr, nullptr, &startup, &child);
    create_error = GetLastError();
  }
  if (!created) {
    throw EnvironmentUnavailable("Cannot launch medium integrity sender: " +
                                 std::to_string(create_error));
  }
  OwnedHandle child_process(child.hProcess);
  OwnedHandle child_thread(child.hThread);
  try {
    sender_integrity_rid = IntegrityRid(child_process.value);
    Require(sender_integrity_rid == SECURITY_MANDATORY_MEDIUM_RID,
            "Restricted sender is not actually medium integrity");
    Require(ResumeThread(child_thread.value) != static_cast<DWORD>(-1),
            "Restricted sender did not resume");
    Require(WaitForSingleObject(child_process.value, 10000) == WAIT_OBJECT_0,
            "Restricted sender exceeded its time limit");
    DWORD exit_code = 93;
    Require(GetExitCodeProcess(child_process.value, &exit_code) != FALSE &&
                exit_code == 0,
            "Medium sender failed production mutex probe or activation (exit " +
                std::to_string(exit_code) + ")");
    medium_mutex_probe_confirmed = true;
  } catch (...) {
    TerminateProcess(child_process.value, 92);
    WaitForSingleObject(child_process.value, 5000);
    throw;
  }
  PumpMessages();
}

class FixtureMutex {
 public:
  FixtureMutex() {
    name = L"Local\\FengWoNativeCI-" + std::to_wstring(GetCurrentProcessId()) +
           L"-" + std::to_wstring(GetTickCount64());
    value = AcquireFengWoInstanceMutex(name.c_str());
    Require(value.handle != nullptr && value.owns_mutex &&
                !value.existing_instance,
            "Production mutex acquisition did not create owner");
    PSECURITY_DESCRIPTOR descriptor = nullptr;
    Require(ConvertStringSecurityDescriptorToSecurityDescriptorW(
                L"S:(ML;;NW;;;HI)", SDDL_REVISION_1, &descriptor, nullptr) != FALSE,
            "Cannot build synthetic high-integrity mutex label");
    const BOOL labeled = SetKernelObjectSecurity(
        value.handle, LABEL_SECURITY_INFORMATION, descriptor);
    const DWORD label_error = GetLastError();
    LocalFree(descriptor);
    if (!labeled) {
      ReleaseFengWoInstanceMutex(&value);
      throw EnvironmentUnavailable("Cannot label synthetic high mutex: " +
                                   std::to_string(label_error));
    }
  }
  ~FixtureMutex() { ReleaseFengWoInstanceMutex(&value); }
  std::wstring name;
  FengWoInstanceMutex value;
};

class FixtureWindow {
 public:
  FixtureWindow(const RECT& rect, bool visible = true) {
    WNDCLASSW window_class{};
    window_class.lpfnWndProc = &FixtureWindow::WindowProcedure;
    window_class.hInstance = GetModuleHandleW(nullptr);
    window_class.lpszClassName = L"FLUTTER_RUNNER_WIN32_WINDOW";
    const ATOM registered = RegisterClassW(&window_class);
    Require(registered != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS,
            "RegisterClass failed");
    handle = CreateWindowExW(
        WS_EX_TOOLWINDOW, window_class.lpszClassName,
        L"Synthetic native window fixture", WS_OVERLAPPEDWINDOW, rect.left,
        rect.top, rect.right - rect.left, rect.bottom - rect.top, nullptr,
        nullptr, window_class.hInstance, this);
    Require(handle != nullptr, "CreateWindow failed");
    presentation.OnFirstFrame();
    ShowWindow(handle, visible ? SW_SHOWNORMAL : SW_HIDE);
    PumpMessages();
  }

  ~FixtureWindow() {
    if (handle != nullptr) {
      DestroyWindow(handle);
    }
    PumpMessages();
  }

  RECT Bounds() const {
    RECT rect{};
    Require(GetWindowRect(handle, &rect) != FALSE, "GetWindowRect failed");
    return rect;
  }

  void AssertRecovered() const {
    Require(IsWindowVisible(handle) != FALSE, "Window remains hidden");
    Require(IsIconic(handle) == FALSE, "Window remains minimized");
    Require(IsHungAppWindow(handle) == FALSE, "Windows reports hung window");
    Require(Contained(Bounds(), CurrentWorkArea()),
            "Window is outside current monitor work area");
    DWORD process_id = 0;
    GetWindowThreadProcessId(handle, &process_id);
    Require(process_id == GetCurrentProcessId(), "Fixture PID changed");
    const LONG_PTR style = GetWindowLongPtrW(handle, GWL_EXSTYLE);
    Require((style & WS_EX_APPWINDOW) != 0 && (style & WS_EX_TOOLWINDOW) == 0,
            "Window taskbar style was not restored");
  }

  HWND handle = nullptr;
  int requests = 0;
  int activations = 0;
  FengWoWindowPresentationState presentation;

 private:
  static LRESULT CALLBACK WindowProcedure(HWND window, UINT message,
                                           WPARAM wparam, LPARAM lparam) {
    if (message == WM_NCCREATE) {
      const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
      SetWindowLongPtrW(window, GWLP_USERDATA,
                        reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    }
    auto* fixture = reinterpret_cast<FixtureWindow*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (fixture != nullptr &&
        IsFengWoWindowActivationRequest(message, wparam, lparam)) {
      ++fixture->requests;
      if (fixture->presentation.RequestActivation()) {
        ++fixture->activations;
        ActivateFengWoWindow(window);
      }
      return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
  }
};

RECT InsideCurrentWorkArea() {
  const RECT area = CurrentWorkArea();
  return {area.left + 20, area.top + 20, area.left + 420, area.top + 300};
}

}

int wmain(int argc, wchar_t** argv) {
  if (argc == 4 && std::wstring(argv[1]) == L"--medium-post") {
    const auto target = reinterpret_cast<HWND>(
        static_cast<std::uintptr_t>(std::stoull(argv[2])));
    if (IntegrityRid(GetCurrentProcess()) != SECURITY_MANDATORY_MEDIUM_RID) {
      return 81;
    }
    FengWoInstanceMutex mutex = AcquireFengWoInstanceMutex(argv[3]);
    const bool probe = mutex.handle != nullptr && mutex.existing_instance &&
        mutex.read_only_probe && !mutex.owns_mutex &&
        mutex.create_error == ERROR_ACCESS_DENIED;
    ReleaseFengWoInstanceMutex(&mutex);
    if (!probe) return 82;
    return PostFengWoWindowActivation(target) ? 0 : 83;
  }
  if (argc != 2) {
    return 2;
  }
  report_path = std::filesystem::path(argv[1]);
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

  Run("normal-window-preserves-position-and-size", [] {
    FixtureWindow fixture(InsideCurrentWorkArea());
    const RECT before = fixture.Bounds();
    EnsureFengWoWindowOnScreen(fixture.handle, false);
    Require(SameRect(before, fixture.Bounds()), "Normal window was moved");
    ActivateFengWoWindow(fixture.handle);
    Require(SameRect(before, fixture.Bounds()), "Normal activation moved window");
    fixture.AssertRecovered();
  });

  Run("passive-recovery-does-not-show-hidden-window", [] {
    FixtureWindow fixture({20000, 20000, 21000, 20700}, false);
    EnsureFengWoWindowOnScreen(fixture.handle, false);
    Require(IsWindowVisible(fixture.handle) == FALSE,
            "Passive startup displayed a hidden window");
    Require(Contained(fixture.Bounds(), CurrentWorkArea()),
            "Passive startup did not repair hidden offscreen geometry");
  });

  Run("explicit-activation-restores-hidden-window", [] {
    FixtureWindow fixture(InsideCurrentWorkArea(), false);
    ActivateFengWoWindow(fixture.handle);
    fixture.AssertRecovered();
  });

  Run("explicit-activation-restores-minimized-window", [] {
    FixtureWindow fixture(InsideCurrentWorkArea());
    ShowWindow(fixture.handle, SW_MINIMIZE);
    Require(IsIconic(fixture.handle) != FALSE, "Fixture was not minimized");
    ActivateFengWoWindow(fixture.handle);
    fixture.AssertRecovered();
  });

  Run("explicit-activation-restores-offscreen-window", [] {
    FixtureWindow fixture({20000, 20000, 21000, 20700});
    Require(!Contained(fixture.Bounds(), CurrentWorkArea()),
            "Fixture was not offscreen");
    ActivateFengWoWindow(fixture.handle);
    fixture.AssertRecovered();
  });

  Run("current-monitor-selection-and-normal-window-preservation", [] {
    const std::vector<RECT> areas{{0, 0, 1200, 800}, {-1280, -50, 0, 850}};
    const RECT old_monitor{100, 100, 700, 600};
    const auto moved = ComputeFengWoWindowBounds(old_monitor, areas, 1, true);
    Require(moved.changed && Contained(moved.rect, areas[1]),
            "Explicit activation did not select current monitor");
    const RECT current{-1100, 100, -500, 600};
    const auto same = ComputeFengWoWindowBounds(current, areas, 1, true);
    Require(!same.changed && SameRect(same.rect, current),
            "Normal window already on current monitor moved");
  });

  Run("passive-recovery-preserves-window-on-another-monitor", [] {
    const std::vector<RECT> areas{{0, 0, 1200, 800}, {-1280, -50, 0, 850}};
    const RECT current{-1100, 100, -500, 600};
    const auto bounds = ComputeFengWoWindowBounds(current, areas, 0, false);
    Require(!bounds.changed && SameRect(bounds.rect, current),
            "Passive startup moved a valid window to another monitor");
  });

  Run("small-workarea-clamps-size-and-supports-negative-coordinates", [] {
    const std::vector<RECT> small{{40, 80, 220, 170}};
    const auto clamped = ComputeFengWoWindowBounds(
        RECT{20000, 20000, 21280, 20720}, small, 0, true);
    Require(clamped.changed && Contained(clamped.rect, small[0]),
            "Oversized window did not fit small work area");
    const std::vector<RECT> negative{{-1920, -1000, -640, -100}};
    const auto moved = ComputeFengWoWindowBounds(
        RECT{20000, 20000, 21000, 20700}, negative, 0, true);
    Require(moved.changed && Contained(moved.rect, negative[0]),
            "Negative-coordinate work area recovery failed");
  });

  Run("registered-message-rejects-payload-and-medium-activates-high", [] {
    const UINT message = GetFengWoWindowActivationMessage();
    Require(message >= 0xc000 && message <= 0xffff,
            "Activation message is not process-independent registered message");
    Require(message == GetFengWoWindowActivationMessage(),
            "Activation registration is unstable");
    Require(IsFengWoWindowActivationRequest(message, 0, 0),
            "Zero-payload activation was rejected");
    Require(!IsFengWoWindowActivationRequest(message, 1, 0) &&
                !IsFengWoWindowActivationRequest(message, 0, 1) &&
                !IsFengWoWindowActivationRequest(WM_COPYDATA, 0, 0),
            "Activation message accepted payload or unrelated message");
    FixtureWindow fixture(InsideCurrentWorkArea(), false);
    Require(AllowFengWoWindowActivation(fixture.handle),
            "Window-scoped registered message allowance failed");
    Require(!AllowFengWoWindowActivation(nullptr) &&
                !PostFengWoWindowActivation(nullptr) &&
                !EnsureFengWoWindowOnScreen(nullptr, true),
            "Invalid HWND was accepted");
    PostMessageW(fixture.handle, message, 1, 1);
    PumpMessages();
    Require(fixture.requests == 0 && IsWindowVisible(fixture.handle) == FALSE,
            "Invalid request changed window visibility");
    FixtureMutex mutex;
    PostFromMediumIntegrityChild(fixture.handle, mutex.name);
    Require(mutex.value.owns_mutex && mutex.value.handle != nullptr,
            "Medium sender consumed high process mutex ownership");
    Require(fixture.requests == 1 && fixture.activations == 1,
            "Medium request was not received by high integrity owner");
    fixture.AssertRecovered();
  });

  Run("repeated-launch-activation-keeps-own-window-and-process", [] {
    FixtureWindow fixture({20000, 20000, 21000, 20700}, false);
    const HWND before = fixture.handle;
    Require(PostFengWoWindowActivation(fixture.handle) &&
                PostFengWoWindowActivation(fixture.handle),
            "Posting repeated activation failed");
    PumpMessages();
    Require(fixture.requests == 2 && fixture.activations == 2,
            "Repeated activation requests were lost");
    Require(fixture.handle == before, "Activation replaced HWND");
    fixture.AssertRecovered();
    ShowWindow(fixture.handle, SW_HIDE);
    bool wrong_thread_ensure = true;
    std::thread worker([&] {
      wrong_thread_ensure = EnsureFengWoWindowOnScreen(fixture.handle, true);
      ActivateFengWoWindow(fixture.handle);
    });
    worker.join();
    Require(!wrong_thread_ensure && IsWindowVisible(fixture.handle) == FALSE,
            "Worker thread changed owner window directly");
    PumpMessages();
    Require(fixture.requests == 3 && fixture.activations == 3,
            "Worker activation did not reach owner thread");
    fixture.AssertRecovered();
  });

  Run("first-frame-gate-coalesces-request-and-preserves-silent-start", [] {
    FengWoWindowPresentationState silent;
    Require(!silent.OnFirstFrame(), "First frame forced an unsolicited show");
    FengWoWindowPresentationState pending;
    Require(!pending.RequestActivation() && !pending.RequestActivation(),
            "Activation ran before the first frame");
    Require(pending.OnFirstFrame(), "Pending activation was not replayed");
    Require(!pending.OnFirstFrame(), "Pending activation replayed twice");
    Require(pending.RequestActivation(), "Ready window rejected activation");
    pending.Reset();
    Require(!pending.OnFirstFrame(), "Reset retained stale activation intent");
  });

  Run("show-position-hook-clamps-saved-offscreen-position", [] {
    FixtureWindow fixture(InsideCurrentWorkArea(), false);
    WINDOWPOS passive{fixture.handle, nullptr, 20000, 20000, 1000, 700, 0};
    AdjustFengWoWindowPosition(fixture.handle, &passive);
    Require(passive.x == 20000 && passive.y == 20000,
            "Hidden configuration position was changed before show");
    passive.flags = SWP_SHOWWINDOW;
    AdjustFengWoWindowPosition(fixture.handle, &passive);
    const RECT adjusted{passive.x, passive.y, passive.x + passive.cx,
                         passive.y + passive.cy};
    Require(Contained(adjusted, CurrentWorkArea()),
            "Show-time position hook did not clamp offscreen geometry");
    Require(IsWindowVisible(fixture.handle) == FALSE,
            "Position computation forced window visibility");
  });

  bool all_passed = results.size() == 12;
  for (const auto& result : results) {
    all_passed = all_passed && result.passed;
  }
  return all_passed ? 0 : 1;
}
