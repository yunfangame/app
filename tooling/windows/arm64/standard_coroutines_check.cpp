#include <coroutine>
#include <cstdlib>

#if defined(_WIN32)
#include <winrt/Windows.Foundation.h>
#include <winrt/base.h>
#if !defined(_M_ARM64)
#error The Windows coroutine check must use native ARM64
#endif
#endif

static_assert(__cpp_impl_coroutine >= 201902L);
static_assert(__cpp_lib_coroutine >= 201902L);

struct Task {
  struct promise_type {
    Task get_return_object() const noexcept { return {}; }
    std::suspend_never initial_suspend() const noexcept { return {}; }
    std::suspend_never final_suspend() const noexcept { return {}; }
    void return_void() const noexcept {}
    void unhandled_exception() const noexcept { std::abort(); }
  };
};

Task Complete(int& value) {
  value = 42;
  co_return;
}

#if defined(_WIN32)
winrt::Windows::Foundation::IAsyncAction CompleteWinrt(int& value) {
  value = 43;
  co_return;
}
#endif

int main() {
  int value = 0;
  Complete(value);
  if (value != 42) return 1;
#if defined(_WIN32)
  winrt::init_apartment(winrt::apartment_type::multi_threaded);
  CompleteWinrt(value).get();
  winrt::uninit_apartment();
  if (value != 43) return 2;
#endif
  return 0;
}
