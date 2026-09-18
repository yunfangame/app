#ifndef FLUTTER_PLUGIN_PROXY_PLUGIN_H_
#define FLUTTER_PLUGIN_PROXY_PLUGIN_H_

#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <functional>
#include <memory>
#include <optional>

#include "proxy_task_runner.h"

namespace proxy {

class ProxyPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  ProxyPlugin();

  explicit ProxyPlugin(flutter::PluginRegistrarWindows* registrar);

  ~ProxyPlugin() override;

  ProxyPlugin(const ProxyPlugin&) = delete;
  ProxyPlugin& operator=(const ProxyPlugin&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  static bool IsSessionEnding(UINT message, WPARAM wparam);

  static std::optional<int> AppliedProxyPort(bool success, int port);

  std::optional<LRESULT> HandleWindowProc(
      HWND window, UINT message, WPARAM wparam, LPARAM lparam);

 private:
  struct ProxyState;

  void Dispatch(
      std::function<flutter::EncodableValue()> operation,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void Shutdown();

  flutter::PluginRegistrarWindows* registrar_ = nullptr;
  int window_proc_id_ = -1;
  std::shared_ptr<ProxyState> state_;
  ProxyTaskRunner task_runner_;
};

}  // namespace proxy

#endif  // FLUTTER_PLUGIN_PROXY_PLUGIN_H_
