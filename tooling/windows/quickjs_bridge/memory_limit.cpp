#include "quickjs/quickjs.h"

extern "C" __declspec(dllexport) void jsSetMemoryLimit(JSRuntime* runtime, size_t limit) {
  JS_SetMemoryLimit(runtime, limit);
}
