#define NOMINMAX
#include <windows.h>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>

template <typename Function>
Function Resolve(HMODULE module, const char* name) {
  const auto address = GetProcAddress(module, name);
  if (address == nullptr) throw std::runtime_error(std::string("Missing export: ") + name);
  Function function;
  static_assert(sizeof(function) == sizeof(address));
  std::memcpy(&function, &address, sizeof(function));
  return function;
}

int wmain(int argc, wchar_t* argv[]) {
  if (argc != 3) return 2;
  const auto module = LoadLibraryW(argv[1]);
  if (module == nullptr) return 3;
  void* runtime = nullptr;
  void* context = nullptr;
  void (*free_runtime)(void*) = nullptr;
  void (*free_context)(void*) = nullptr;
  try {
    std::ifstream symbols(argv[2]);
    if (!symbols) throw std::runtime_error("Cannot read required exports");
    std::string symbol;
    size_t symbol_count = 0;
    while (std::getline(symbols, symbol)) {
      if (!symbol.empty() && symbol.back() == '\r') symbol.pop_back();
      if (symbol.empty()) continue;
      if (GetProcAddress(module, symbol.c_str()) == nullptr) {
        throw std::runtime_error("Missing export: " + symbol);
      }
      ++symbol_count;
    }
    if (symbol_count != 55) throw std::runtime_error("Unexpected FFI export contract");
    const auto new_runtime = Resolve<void* (*)(void*, int64_t)>(module, "jsNewRuntime");
    const auto new_context = Resolve<void* (*)(void*)>(module, "jsNewContext");
    const auto eval = Resolve<void* (*)(void*, const char*, size_t, const char*, int32_t)>(module, "jsEval");
    const auto is_exception = Resolve<int32_t (*)(void*)>(module, "jsIsException");
    const auto to_string = Resolve<const char* (*)(void*, void*)>(module, "jsToCString");
    const auto free_string = Resolve<void (*)(void*, const char*)>(module, "jsFreeCString");
    const auto free_value = Resolve<void (*)(void*, void*, int32_t)>(module, "jsFreeValue");
    const auto pending_job = Resolve<int32_t (*)(void*)>(module, "jsExecutePendingJob");
    const auto set_memory = Resolve<void (*)(void*, size_t)>(module, "jsSetMemoryLimit");
    const auto value_size = Resolve<uint32_t (*)()>(module, "sizeOfJSValue");
    free_runtime = Resolve<void (*)(void*)>(module, "jsFreeRuntime");
    free_context = Resolve<void (*)(void*)>(module, "jsFreeContext");
    if (value_size() != 16) throw std::runtime_error("Unexpected ARM64 JSValue ABI");
    runtime = new_runtime(nullptr, 20);
    if (runtime == nullptr) throw std::runtime_error("Cannot create runtime");
    set_memory(runtime, 64 * 1024 * 1024);
    context = new_context(runtime);
    if (context == nullptr) throw std::runtime_error("Cannot create context");
    const auto check_eval = [&](const char* input, const char* expected) {
      const auto result = eval(context, input, std::strlen(input), "smoke.js", 0);
      if (result == nullptr || is_exception(result)) throw std::runtime_error("Evaluation failed");
      const auto text = to_string(context, result);
      const auto actual = text == nullptr ? std::string() : std::string(text);
      if (text != nullptr) free_string(context, text);
      free_value(context, result, 1);
      if (actual != expected) throw std::runtime_error("Unexpected evaluation result");
    };
    check_eval("1 + 2", "3");
    check_eval("'蜂窝 ARM64 🚀'", "蜂窝 ARM64 🚀");
    check_eval("function main(c) { c.name='蜂窝'; c.port=7890; return c; } JSON.stringify(main({mode:'rule'}))",
               "{\"mode\":\"rule\",\"name\":\"蜂窝\",\"port\":7890}");
    check_eval("globalThis.answer=0; Promise.resolve(42).then(v=>globalThis.answer=v); 'queued'", "queued");
    for (int iteration = 0; iteration < 10 && pending_job(runtime) > 0; ++iteration) {}
    check_eval("globalThis.answer", "42");
    const char* endless = "while (true) {}";
    const auto timed = eval(context, endless, std::strlen(endless), "timeout.js", 0);
    if (timed == nullptr || !is_exception(timed)) throw std::runtime_error("Execution timeout was not enforced");
    free_value(context, timed, 1);
    free_context(context);
    context = nullptr;
    free_runtime(runtime);
    runtime = nullptr;
    FreeLibrary(module);
    std::cout << "ARM64 QuickJS exports, values, UTF-8, config, Promise and timeout passed\n";
    return 0;
  } catch (const std::exception& failure) {
    if (context != nullptr && free_context != nullptr) free_context(context);
    if (runtime != nullptr && free_runtime != nullptr) free_runtime(runtime);
    FreeLibrary(module);
    std::cerr << failure.what() << '\n';
    return 1;
  }
}
