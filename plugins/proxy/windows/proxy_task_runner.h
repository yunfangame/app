#ifndef FLUTTER_PLUGIN_PROXY_TASK_RUNNER_H_
#define FLUTTER_PLUGIN_PROXY_TASK_RUNNER_H_

#include <chrono>
#include <condition_variable>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <thread>
#include <utility>

namespace proxy {

class ProxyTaskRunner {
 public:
  using Task = std::function<void()>;

  ProxyTaskRunner() : state_(std::make_shared<State>()) {
    std::thread([state = state_] { Run(state); }).detach();
  }

  ~ProxyTaskRunner() { Shutdown(); }

  ProxyTaskRunner(const ProxyTaskRunner&) = delete;
  ProxyTaskRunner& operator=(const ProxyTaskRunner&) = delete;
  ProxyTaskRunner(ProxyTaskRunner&&) = delete;
  ProxyTaskRunner& operator=(ProxyTaskRunner&&) = delete;

  bool Post(Task run, Task cancel = {}) {
    if (!run) return false;
    const auto state = state_;
    {
      std::lock_guard<std::mutex> lock(state->mutex);
      if (state->shutdown_requested) return false;
      state->queue.push_back({std::move(run), std::move(cancel)});
    }
    state->condition.notify_one();
    return true;
  }

  void Shutdown(Task finalizer = {}) {
    const auto state = state_;
    std::deque<WorkItem> cancelled;
    {
      std::lock_guard<std::mutex> lock(state->mutex);
      if (state->shutdown_requested) return;
      state->shutdown_requested = true;
      state->finalizer = std::move(finalizer);
      cancelled.swap(state->queue);
    }
    for (auto& item : cancelled) {
      Invoke(item.cancel);
    }
    {
      std::lock_guard<std::mutex> lock(state->mutex);
      state->cancellation_complete = true;
    }
    state->condition.notify_all();
  }

  bool WaitForShutdown(std::chrono::milliseconds timeout) const {
    const auto state = state_;
    std::unique_lock<std::mutex> lock(state->mutex);
    return state->condition.wait_for(
        lock, timeout, [&state] { return state->shutdown_complete; });
  }

 private:
  struct WorkItem {
    Task run;
    Task cancel;
  };

  struct State {
    std::mutex mutex;
    std::condition_variable condition;
    std::deque<WorkItem> queue;
    Task finalizer;
    bool shutdown_requested = false;
    bool cancellation_complete = false;
    bool shutdown_complete = false;
  };

  static void Invoke(Task& task) noexcept {
    if (!task) return;
    try {
      task();
    } catch (...) {
    }
  }

  static void Run(const std::shared_ptr<State>& state) noexcept {
    while (true) {
      WorkItem item;
      Task finalizer;
      {
        std::unique_lock<std::mutex> lock(state->mutex);
        state->condition.wait(lock, [&state] {
          return !state->queue.empty() ||
                 (state->shutdown_requested &&
                  state->cancellation_complete);
        });
        if (!state->queue.empty()) {
          item = std::move(state->queue.front());
          state->queue.pop_front();
        } else {
          finalizer = std::move(state->finalizer);
        }
      }
      if (item.run) {
        Invoke(item.run);
        continue;
      }
      Invoke(finalizer);
      {
        std::lock_guard<std::mutex> lock(state->mutex);
        state->shutdown_complete = true;
      }
      state->condition.notify_all();
      return;
    }
  }

  std::shared_ptr<State> state_;
};

}

#endif
