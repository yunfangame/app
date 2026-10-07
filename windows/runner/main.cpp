#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <iterator>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kSingleInstanceMutexName[] =
    L"Local\\FengWoAccelerator.FengWo.MainWindow";
constexpr wchar_t kMainWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

struct WindowSearchContext {
  const wchar_t* executable_path;
  DWORD session_id;
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
  DWORD session_id = 0;
  auto* context = reinterpret_cast<WindowSearchContext*>(parameter);
  if (ProcessIdToSessionId(process_id, &session_id) == FALSE ||
      session_id != context->session_id) {
    return TRUE;
  }
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                               process_id);
  if (process == nullptr) {
    return TRUE;
  }
  wchar_t process_path[32768] = {};
  DWORD process_path_size = static_cast<DWORD>(std::size(process_path));
  const bool path_found =
      QueryFullProcessImageNameW(process, 0, process_path,
                                 &process_path_size) != FALSE;
  CloseHandle(process);
  if (!path_found) {
    return TRUE;
  }

  if (_wcsicmp(process_path, context->executable_path) == 0) {
    context->result = window;
    return FALSE;
  }
  return TRUE;
}

bool RestoreExistingWindow(bool broadcast_if_missing = true) {
  wchar_t executable_path[32768] = {};
  const DWORD path_size = GetModuleFileNameW(
      nullptr, executable_path,
      static_cast<DWORD>(std::size(executable_path)));
  DWORD session_id = 0;
  if (path_size == 0 || path_size >= std::size(executable_path) ||
      ProcessIdToSessionId(GetCurrentProcessId(), &session_id) == FALSE) {
    return false;
  }
  for (int attempt = 0; attempt < 40; ++attempt) {
    WindowSearchContext context{executable_path, session_id, nullptr};
    EnumWindows(FindPrimaryWindow, reinterpret_cast<LPARAM>(&context));
    if (context.result != nullptr &&
        PostFengWoWindowActivation(context.result)) {
      return true;
    }
    const UINT activation = GetFengWoWindowActivationMessage();
    if (broadcast_if_missing && activation != 0 && attempt % 4 == 0) {
      PostMessageW(HWND_BROADCAST, activation, 0, 0);
    }
    Sleep(50);
  }
  return false;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  FengWoInstanceMutex instance_mutex =
      AcquireFengWoInstanceMutex(kSingleInstanceMutexName);
  if (instance_mutex.existing_instance) {
    const UINT activation_message = GetFengWoWindowActivationMessage();
    if (activation_message != 0) {
      PostMessageW(HWND_BROADCAST, activation_message, 0, 0);
    }
    RestoreExistingWindow();
    ReleaseFengWoInstanceMutex(&instance_mutex);
    return EXIT_SUCCESS;
  }
  if (instance_mutex.handle == nullptr &&
      instance_mutex.create_error == ERROR_ACCESS_DENIED &&
      RestoreExistingWindow(false)) {
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
  if (!window.Create(L"\u8702\u7a9d\u52a0\u901f\u5668", origin, size)) {
    ReleaseFengWoInstanceMutex(&instance_mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ReleaseFengWoInstanceMutex(&instance_mutex);
  return EXIT_SUCCESS;
}
