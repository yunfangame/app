#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <iterator>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kSingleInstanceMutexName[] =
    L"Local\\FengWoAccelerator.FlClash.MainWindow";
constexpr wchar_t kMainWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

struct WindowSearchContext {
  const wchar_t* executable_path;
  HWND result;
};

BOOL CALLBACK FindPrimaryWindow(HWND window, LPARAM parameter) {
  wchar_t class_name[128] = {};
  if (GetClassNameW(window, class_name,
                    static_cast<int>(std::size(class_name))) == 0 ||
      wcscmp(class_name, kMainWindowClassName) != 0) {
    return TRUE;
  }

  DWORD process_id = 0;
  GetWindowThreadProcessId(window, &process_id);
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                               process_id);
  if (process == nullptr) {
    return TRUE;
  }
  wchar_t process_path[MAX_PATH] = {};
  DWORD process_path_size = static_cast<DWORD>(std::size(process_path));
  const bool path_found =
      QueryFullProcessImageNameW(process, 0, process_path,
                                 &process_path_size) != FALSE;
  CloseHandle(process);
  if (!path_found) {
    return TRUE;
  }

  auto* context = reinterpret_cast<WindowSearchContext*>(parameter);
  if (_wcsicmp(process_path, context->executable_path) == 0) {
    context->result = window;
    return FALSE;
  }
  return TRUE;
}

bool RestoreExistingWindow() {
  wchar_t executable_path[MAX_PATH] = {};
  if (GetModuleFileNameW(nullptr, executable_path,
                         static_cast<DWORD>(std::size(executable_path))) == 0) {
    return false;
  }
  // The primary process may still be creating its window when a user quickly
  // starts the shortcut twice. Wait briefly so the activation is not lost.
  for (int attempt = 0; attempt < 40; ++attempt) {
    WindowSearchContext context{executable_path, nullptr};
    EnumWindows(FindPrimaryWindow, reinterpret_cast<LPARAM>(&context));
    if (context.result != nullptr) {
      ActivateFengWoWindow(context.result);
      return true;
    }
    Sleep(50);
  }
  return false;
}

void ReleaseInstanceMutex(HANDLE instance_mutex) {
  if (instance_mutex == nullptr) {
    return;
  }
  ReleaseMutex(instance_mutex);
  CloseHandle(instance_mutex);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  HANDLE instance_mutex =
      CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (instance_mutex != nullptr && GetLastError() == ERROR_ALREADY_EXISTS) {
    // The primary instance handles this registered message using its own HWND,
    // so activation does not depend on a localized or dynamically changed
    // window title. The executable-path lookup below remains as a fallback.
    AllowSetForegroundWindow(ASFW_ANY);
    const UINT activation_message = GetFengWoWindowActivationMessage();
    if (activation_message != 0) {
      PostMessageW(HWND_BROADCAST, activation_message, 0, 0);
    }
    RestoreExistingWindow();
    CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"蜂窝加速器", origin, size)) {
    ReleaseInstanceMutex(instance_mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ReleaseInstanceMutex(instance_mutex);
  return EXIT_SUCCESS;
}
