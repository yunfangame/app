#include <windows.h>

#include <string>

namespace {
constexpr wchar_t kServiceName[] = L"FlClashHelperService";
SERVICE_STATUS_HANDLE status_handle = nullptr;
SERVICE_STATUS status{};
HANDLE stopped = nullptr;
std::wstring counter_path;
std::wstring ready_path;
volatile LONG stop_count = 0;

bool WriteNumber(const std::wstring& path, DWORD value) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ,
                            nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL,
                            nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  const std::string text = std::to_string(value);
  DWORD written = 0;
  const BOOL result = WriteFile(file, text.data(),
                               static_cast<DWORD>(text.size()), &written,
                               nullptr);
  const BOOL flushed = FlushFileBuffers(file);
  CloseHandle(file);
  return result && flushed && written == text.size();
}

void PublishStatus(DWORD state, DWORD accepted) {
  status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
  status.dwCurrentState = state;
  status.dwControlsAccepted = accepted;
  status.dwWin32ExitCode = NO_ERROR;
  status.dwCheckPoint = 0;
  status.dwWaitHint = 0;
  SetServiceStatus(status_handle, &status);
}

void WINAPI ServiceControl(DWORD control) {
  if (control == SERVICE_CONTROL_STOP) {
    const LONG count = InterlockedIncrement(&stop_count);
    WriteNumber(counter_path, static_cast<DWORD>(count));
    PublishStatus(SERVICE_STOP_PENDING, 0);
    SetEvent(stopped);
  } else if (control == SERVICE_CONTROL_INTERROGATE) {
    SetServiceStatus(status_handle, &status);
  }
}

void WINAPI ServiceMain(DWORD, LPWSTR*) {
  status_handle = RegisterServiceCtrlHandlerW(kServiceName, ServiceControl);
  if (!status_handle) return;
  stopped = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (!stopped || !WriteNumber(counter_path, 0)) {
    PublishStatus(SERVICE_STOPPED, 0);
    if (stopped) CloseHandle(stopped);
    return;
  }
  PublishStatus(SERVICE_RUNNING, SERVICE_ACCEPT_STOP);
  if (!WriteNumber(ready_path, GetCurrentProcessId())) SetEvent(stopped);
  WaitForSingleObject(stopped, INFINITE);
  PublishStatus(SERVICE_STOPPED, 0);
  CloseHandle(stopped);
}

LRESULT CALLBACK FixtureWindow(HWND window, UINT message, WPARAM first,
                                LPARAM second) {
  if (message == WM_DESTROY) {
    PostQuitMessage(0);
    return 0;
  }
  return DefWindowProcW(window, message, first, second);
}

int Idle(const std::wstring& ready) {
  const HINSTANCE instance = GetModuleHandleW(nullptr);
  WNDCLASSW type{};
  type.lpfnWndProc = FixtureWindow;
  type.hInstance = instance;
  type.lpszClassName = L"FLUTTER_RUNNER_WIN32_WINDOW";
  if (!RegisterClassW(&type)) return 2;
  const HWND window = CreateWindowW(type.lpszClassName, L"FlClash fixture",
                                   WS_OVERLAPPEDWINDOW, 30, 30, 240, 160,
                                   nullptr, nullptr, instance, nullptr);
  if (!window) return 3;
  ShowWindow(window, SW_SHOWNOACTIVATE);
  if (!WriteNumber(ready, GetCurrentProcessId())) return 4;
  MSG message{};
  while (GetMessageW(&message, nullptr, 0, 0) > 0) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
  return 0;
}
}

int wmain(int count, wchar_t** arguments) {
  if (count == 3 && std::wstring(arguments[1]) == L"idle") {
    return Idle(arguments[2]);
  }
  if (count == 4 && std::wstring(arguments[1]) == L"service") {
    counter_path = arguments[2];
    ready_path = arguments[3];
    SERVICE_TABLE_ENTRYW table[] = {
        {const_cast<LPWSTR>(kServiceName), ServiceMain}, {nullptr, nullptr}};
    return StartServiceCtrlDispatcherW(table) ? 0 : 5;
  }
  return 6;
}
