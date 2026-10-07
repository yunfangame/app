#include "window_visibility.h"

#include <algorithm>
#include <cstdint>
#include <limits>

namespace {

constexpr wchar_t kActivationMessageName[] =
    L"FengWoAccelerator.FengWo.ActivateMainWindow";

using Coordinate = std::int64_t;
using SetDpiContext = HANDLE(WINAPI*)(HANDLE);

class ThreadDpiScope {
 public:
  ThreadDpiScope() {
    HMODULE user32 = GetModuleHandleW(L"user32.dll");
    if (user32 == nullptr) return;
    set_context_ = reinterpret_cast<SetDpiContext>(
        GetProcAddress(user32, "SetThreadDpiAwarenessContext"));
    if (set_context_ != nullptr) {
      previous_ = set_context_(reinterpret_cast<HANDLE>(
          static_cast<std::intptr_t>(-4)));
    }
  }

  ~ThreadDpiScope() {
    if (previous_ != nullptr) set_context_(previous_);
  }

 private:
  SetDpiContext set_context_ = nullptr;
  HANDLE previous_ = nullptr;
};

Coordinate Width(const RECT& rect) {
  return static_cast<Coordinate>(rect.right) - rect.left;
}

Coordinate Height(const RECT& rect) {
  return static_cast<Coordinate>(rect.bottom) - rect.top;
}

bool HasWorkArea(const RECT& rect) {
  return Width(rect) > 0 && Height(rect) > 0;
}

bool IsReachable(const RECT& window, const RECT& work_area) {
  if (!HasWorkArea(window) || !HasWorkArea(work_area)) return false;
  const Coordinate visible_width =
      std::min<Coordinate>(window.right, work_area.right) -
      std::max<Coordinate>(window.left, work_area.left);
  const Coordinate header_height = std::min<Coordinate>(40, Height(window));
  const Coordinate visible_header =
      std::min<Coordinate>(static_cast<Coordinate>(window.top) + header_height,
                           work_area.bottom) -
      std::max<Coordinate>(window.top, work_area.top);
  const Coordinate required_width =
      std::min<Coordinate>(160, std::min(Width(window), Width(work_area)));
  const Coordinate required_header =
      std::min<Coordinate>(24, std::min(header_height, Height(work_area)));
  return visible_width >= required_width && visible_header >= required_header;
}

bool FitsWorkArea(const RECT& window, const RECT& work_area) {
  return Width(window) <= Width(work_area) &&
         Height(window) <= Height(work_area);
}

struct MonitorCollection {
  std::vector<RECT> work_areas;
  std::size_t preferred_monitor = 0;
  HMONITOR preferred = nullptr;
  bool failed = false;
};

BOOL CALLBACK CollectMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM parameter) {
  auto* collection = reinterpret_cast<MonitorCollection*>(parameter);
  try {
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (GetMonitorInfoW(monitor, &info) != FALSE && HasWorkArea(info.rcWork)) {
      if (monitor == collection->preferred) {
        collection->preferred_monitor = collection->work_areas.size();
      }
      collection->work_areas.push_back(info.rcWork);
    }
    return TRUE;
  } catch (...) {
    collection->failed = true;
    return FALSE;
  }
}

MonitorCollection CurrentMonitors() {
  MonitorCollection result;
  POINT cursor{};
  result.preferred = GetCursorPos(&cursor) != FALSE
                         ? MonitorFromPoint(cursor, MONITOR_DEFAULTTOPRIMARY)
                         : MonitorFromPoint(POINT{}, MONITOR_DEFAULTTOPRIMARY);
  if (EnumDisplayMonitors(nullptr, nullptr, CollectMonitor,
                          reinterpret_cast<LPARAM>(&result)) == FALSE ||
      result.failed) {
    result.work_areas.clear();
  }
  return result;
}

bool IsOwnerThread(HWND window) {
  return GetWindowThreadProcessId(window, nullptr) == GetCurrentThreadId();
}

bool SameBounds(const RECT& left, const RECT& right) {
  return left.left == right.left && left.top == right.top &&
         left.right == right.right && left.bottom == right.bottom;
}

}

FengWoWindowBounds ComputeFengWoWindowBounds(
    const RECT& window, const std::vector<RECT>& work_areas,
    std::size_t preferred_monitor, bool prefer_current_monitor) {
  FengWoWindowBounds result{window, false};
  if (work_areas.empty()) return result;
  if (preferred_monitor >= work_areas.size() ||
      !HasWorkArea(work_areas[preferred_monitor])) {
    preferred_monitor = 0;
    while (preferred_monitor < work_areas.size() &&
           !HasWorkArea(work_areas[preferred_monitor])) {
      ++preferred_monitor;
    }
    if (preferred_monitor == work_areas.size()) return result;
  }
  if (prefer_current_monitor) {
    if (IsReachable(window, work_areas[preferred_monitor]) &&
        FitsWorkArea(window, work_areas[preferred_monitor])) {
      return result;
    }
  } else {
    std::size_t reachable_monitor = work_areas.size();
    for (std::size_t index = 0; index < work_areas.size(); ++index) {
      if (IsReachable(window, work_areas[index])) {
        if (FitsWorkArea(window, work_areas[index])) return result;
        if (reachable_monitor == work_areas.size()) reachable_monitor = index;
      }
    }
    if (reachable_monitor != work_areas.size()) {
      preferred_monitor = reachable_monitor;
    }
  }
  const RECT& area = work_areas[preferred_monitor];
  const Coordinate max_size = std::numeric_limits<int>::max();
  const Coordinate width = std::min(
      std::min(Width(area), max_size),
      std::max<Coordinate>(380, Width(window) > 0 ? Width(window) : 1280));
  const Coordinate height = std::min(
      std::min(Height(area), max_size),
      std::max<Coordinate>(400, Height(window) > 0 ? Height(window) : 720));
  const bool reachable = IsReachable(window, area);
  const Coordinate left = reachable
                              ? std::max<Coordinate>(area.left,
                                  std::min<Coordinate>(window.left,
                                                       static_cast<Coordinate>(area.right) - width))
                              : static_cast<Coordinate>(area.left) +
                                    (Width(area) - width) / 2;
  const Coordinate top = reachable
                             ? std::max<Coordinate>(area.top,
                                 std::min<Coordinate>(window.top,
                                                      static_cast<Coordinate>(area.bottom) - height))
                             : static_cast<Coordinate>(area.top) +
                                   (Height(area) - height) / 2;
  result.rect = RECT{static_cast<LONG>(left), static_cast<LONG>(top),
                     static_cast<LONG>(left + width),
                     static_cast<LONG>(top + height)};
  result.changed = !SameBounds(window, result.rect);
  return result;
}

bool FengWoWindowPresentationState::RequestActivation() {
  activation_pending_ = !first_frame_ready_;
  return first_frame_ready_;
}

bool FengWoWindowPresentationState::OnFirstFrame() {
  first_frame_ready_ = true;
  const bool activate = activation_pending_;
  activation_pending_ = false;
  return activate;
}

void FengWoWindowPresentationState::Reset() {
  first_frame_ready_ = false;
  activation_pending_ = false;
}

FengWoInstanceMutex AcquireFengWoInstanceMutex(const wchar_t* name) {
  FengWoInstanceMutex result;
  for (int attempt = 0; attempt < 2; ++attempt) {
    SetLastError(ERROR_SUCCESS);
    result.handle = CreateMutexW(nullptr, TRUE, name);
    result.create_error = GetLastError();
    if (result.handle != nullptr) {
      result.existing_instance = result.create_error == ERROR_ALREADY_EXISTS;
      result.owns_mutex = !result.existing_instance;
      return result;
    }
    if (result.create_error != ERROR_ACCESS_DENIED) return result;
    SetLastError(ERROR_SUCCESS);
    result.handle = OpenMutexW(SYNCHRONIZE, FALSE, name);
    result.open_error = GetLastError();
    if (result.handle != nullptr) {
      result.existing_instance = true;
      result.read_only_probe = true;
      return result;
    }
    if (result.open_error != ERROR_FILE_NOT_FOUND) return result;
  }
  return result;
}

void ReleaseFengWoInstanceMutex(FengWoInstanceMutex* mutex) {
  if (mutex == nullptr || mutex->handle == nullptr) return;
  if (mutex->owns_mutex) ReleaseMutex(mutex->handle);
  CloseHandle(mutex->handle);
  mutex->handle = nullptr;
  mutex->owns_mutex = false;
}

UINT GetFengWoWindowActivationMessage() {
  static const UINT message = RegisterWindowMessageW(kActivationMessageName);
  return message;
}

bool IsFengWoWindowActivationRequest(UINT message, WPARAM wparam,
                                     LPARAM lparam) {
  const UINT activation = GetFengWoWindowActivationMessage();
  return activation != 0 && message == activation && wparam == 0 && lparam == 0;
}

bool AllowFengWoWindowActivation(HWND window) {
  const UINT activation = GetFengWoWindowActivationMessage();
  return window != nullptr && activation != 0 &&
         ChangeWindowMessageFilterEx(window, activation, MSGFLT_ALLOW,
                                     nullptr) != FALSE;
}

bool PostFengWoWindowActivation(HWND window) {
  const UINT activation = GetFengWoWindowActivationMessage();
  if (window == nullptr || activation == 0) return false;
  DWORD process_id = 0;
  GetWindowThreadProcessId(window, &process_id);
  if (process_id != 0) AllowSetForegroundWindow(process_id);
  return PostMessageW(window, activation, 0, 0) != FALSE;
}

bool EnsureFengWoWindowOnScreen(HWND window, bool prefer_current_monitor) {
  if (window == nullptr || !IsOwnerThread(window) || IsIconic(window)) {
    return false;
  }
  ThreadDpiScope dpi;
  RECT current{};
  if (GetWindowRect(window, &current) == FALSE) return false;
  const MonitorCollection monitors = CurrentMonitors();
  if (IsZoomed(window)) {
    const HMONITOR existing_monitor =
        MonitorFromWindow(window, MONITOR_DEFAULTTONULL);
    if ((!prefer_current_monitor && existing_monitor != nullptr) ||
        (prefer_current_monitor && existing_monitor == monitors.preferred)) {
      return true;
    }
    if (monitors.work_areas.empty()) return false;
    ShowWindow(window, SW_RESTORE);
    const bool moved = EnsureFengWoWindowOnScreen(window, true);
    ShowWindow(window, SW_MAXIMIZE);
    return moved;
  }
  const FengWoWindowBounds bounds = ComputeFengWoWindowBounds(
      current, monitors.work_areas, monitors.preferred_monitor,
      prefer_current_monitor);
  if (!bounds.changed) return true;
  return SetWindowPos(window, nullptr, bounds.rect.left, bounds.rect.top,
                      static_cast<int>(Width(bounds.rect)),
                      static_cast<int>(Height(bounds.rect)),
                      SWP_NOZORDER | SWP_NOACTIVATE | SWP_ASYNCWINDOWPOS) != FALSE;
}

void AdjustFengWoWindowPosition(HWND window, WINDOWPOS* position) {
  if (window == nullptr || position == nullptr ||
      (position->flags & SWP_SHOWWINDOW) == 0 || IsIconic(window) ||
      IsZoomed(window) || !IsOwnerThread(window)) {
    return;
  }
  RECT current{};
  if (GetWindowRect(window, &current) == FALSE) return;
  const Coordinate left = (position->flags & SWP_NOMOVE) != 0
                              ? current.left
                              : position->x;
  const Coordinate top = (position->flags & SWP_NOMOVE) != 0
                             ? current.top
                             : position->y;
  const Coordinate width = (position->flags & SWP_NOSIZE) != 0
                               ? Width(current)
                               : position->cx;
  const Coordinate height = (position->flags & SWP_NOSIZE) != 0
                                ? Height(current)
                                : position->cy;
  const Coordinate max_coordinate = std::numeric_limits<LONG>::max();
  const Coordinate min_coordinate = std::numeric_limits<LONG>::min();
  if (left + width > max_coordinate || left + width < min_coordinate ||
      top + height > max_coordinate || top + height < min_coordinate) {
    return;
  }
  const RECT requested{static_cast<LONG>(left), static_cast<LONG>(top),
                        static_cast<LONG>(left + width),
                        static_cast<LONG>(top + height)};
  const MonitorCollection monitors = CurrentMonitors();
  const FengWoWindowBounds bounds = ComputeFengWoWindowBounds(
      requested, monitors.work_areas, monitors.preferred_monitor, false);
  if (bounds.changed) {
    position->x = bounds.rect.left;
    position->y = bounds.rect.top;
    position->cx = static_cast<int>(Width(bounds.rect));
    position->cy = static_cast<int>(Height(bounds.rect));
    position->flags &= ~(SWP_NOMOVE | SWP_NOSIZE);
  }
}

void ActivateFengWoWindow(HWND window) {
  if (window == nullptr) return;
  if (!IsOwnerThread(window)) {
    PostFengWoWindowActivation(window);
    return;
  }
  LONG_PTR style = GetWindowLongPtrW(window, GWL_EXSTYLE);
  style |= WS_EX_APPWINDOW;
  style &= ~static_cast<LONG_PTR>(WS_EX_TOOLWINDOW);
  SetWindowLongPtrW(window, GWL_EXSTYLE, style);
  if (IsIconic(window)) {
    ShowWindow(window, SW_RESTORE);
  } else if (IsWindowVisible(window) == FALSE) {
    ShowWindow(window, SW_SHOW);
  }
  EnsureFengWoWindowOnScreen(window, true);
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED |
                   SWP_SHOWWINDOW | SWP_ASYNCWINDOWPOS);
  SetForegroundWindow(window);
}
