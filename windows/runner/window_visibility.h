#ifndef RUNNER_WINDOW_VISIBILITY_H_
#define RUNNER_WINDOW_VISIBILITY_H_

#include <windows.h>

#include <cstddef>
#include <vector>

struct FengWoWindowBounds {
  RECT rect;
  bool changed;
};

struct FengWoInstanceMutex {
  HANDLE handle = nullptr;
  bool owns_mutex = false;
  bool existing_instance = false;
  bool read_only_probe = false;
  DWORD create_error = ERROR_SUCCESS;
  DWORD open_error = ERROR_SUCCESS;
};

FengWoInstanceMutex AcquireFengWoInstanceMutex(const wchar_t* name);
void ReleaseFengWoInstanceMutex(FengWoInstanceMutex* mutex);

FengWoWindowBounds ComputeFengWoWindowBounds(
    const RECT& window, const std::vector<RECT>& work_areas,
    std::size_t preferred_monitor, bool prefer_current_monitor);

class FengWoWindowPresentationState {
 public:
  bool RequestActivation();
  bool OnFirstFrame();
  void Reset();

 private:
  bool first_frame_ready_ = false;
  bool activation_pending_ = false;
};

UINT GetFengWoWindowActivationMessage();
bool IsFengWoWindowActivationRequest(UINT message, WPARAM wparam,
                                     LPARAM lparam);
bool AllowFengWoWindowActivation(HWND window);
bool PostFengWoWindowActivation(HWND window);
bool EnsureFengWoWindowOnScreen(HWND window, bool prefer_current_monitor);
void AdjustFengWoWindowPosition(HWND window, WINDOWPOS* position);
void ActivateFengWoWindow(HWND window);

#endif
