#include "../proxy_task_runner.h"

#include <gtest/gtest.h>

#include <atomic>
#include <chrono>
#include <future>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

namespace proxy {
namespace {

class ManualEvent {
 public:
  ManualEvent() : future_(promise_.get_future().share()) {}

  void Signal() {
    std::call_once(signal_once_, [this] { promise_.set_value(); });
  }

  void Wait() const { future_.wait(); }

  std::future_status WaitFor(std::chrono::milliseconds timeout) const {
    return future_.wait_for(timeout);
  }

 private:
  std::promise<void> promise_;
  std::shared_future<void> future_;
  std::once_flag signal_once_;
};

class ScopedSignal {
 public:
  explicit ScopedSignal(std::shared_ptr<ManualEvent> event)
      : event_(std::move(event)) {}

  ~ScopedSignal() { event_->Signal(); }

 private:
  std::shared_ptr<ManualEvent> event_;
};

TEST(ProxyTaskRunner, BlockedTaskDoesNotBlockPost) {
  ProxyTaskRunner runner;
  const auto started = std::make_shared<ManualEvent>();
  const auto release = std::make_shared<ManualEvent>();
  ScopedSignal release_on_exit(release);
  ASSERT_TRUE(runner.Post([started, release] {
    started->Signal();
    release->Wait();
  }));
  ASSERT_EQ(started->WaitFor(std::chrono::seconds(1)),
            std::future_status::ready);

  const auto posted = std::make_shared<std::promise<bool>>();
  auto posted_future = posted->get_future();
  std::thread poster([&runner, posted] {
    posted->set_value(runner.Post([] {}));
  });
  const auto post_status = posted_future.wait_for(std::chrono::milliseconds(200));
  release->Signal();
  poster.join();

  ASSERT_EQ(post_status, std::future_status::ready);
  EXPECT_TRUE(posted_future.get());
  runner.Shutdown();
  EXPECT_TRUE(runner.WaitForShutdown(std::chrono::seconds(1)));
}

TEST(ProxyTaskRunner, RunsTasksInPostingOrder) {
  struct Result {
    std::mutex mutex;
    std::vector<int> order;
    ManualEvent complete;
  };

  ProxyTaskRunner runner;
  const auto result = std::make_shared<Result>();
  for (int value = 1; value <= 3; ++value) {
    ASSERT_TRUE(runner.Post([result, value] {
      {
        std::lock_guard<std::mutex> lock(result->mutex);
        result->order.push_back(value);
      }
      if (value == 3) result->complete.Signal();
    }));
  }

  EXPECT_EQ(result->complete.WaitFor(std::chrono::seconds(1)),
            std::future_status::ready);
  runner.Shutdown();
  EXPECT_TRUE(runner.WaitForShutdown(std::chrono::seconds(1)));
  std::lock_guard<std::mutex> lock(result->mutex);
  EXPECT_EQ(result->order, (std::vector<int>{1, 2, 3}));
}

TEST(ProxyTaskRunner, DestructorDoesNotWaitForRunningTaskOrRunPendingTask) {
  const auto started = std::make_shared<ManualEvent>();
  const auto release = std::make_shared<ManualEvent>();
  const auto finished = std::make_shared<ManualEvent>();
  const auto destroyed = std::make_shared<ManualEvent>();
  const auto pending_ran = std::make_shared<std::atomic<bool>>(false);
  const auto pending_cancelled = std::make_shared<std::atomic<int>>(0);

  auto runner = std::make_unique<ProxyTaskRunner>();
  ScopedSignal release_on_exit(release);
  ASSERT_TRUE(runner->Post([started, release, finished] {
    started->Signal();
    release->Wait();
    finished->Signal();
  }));
  ASSERT_EQ(started->WaitFor(std::chrono::seconds(1)),
            std::future_status::ready);
  ASSERT_TRUE(runner->Post(
      [pending_ran] { *pending_ran = true; },
      [pending_cancelled] { ++*pending_cancelled; }));

  const auto before = std::chrono::steady_clock::now();
  std::thread destroyer(
      [runner = std::move(runner), destroyed]() mutable {
        runner.reset();
        destroyed->Signal();
      });
  const auto destroy_status =
      destroyed->WaitFor(std::chrono::milliseconds(200));
  const auto elapsed = std::chrono::steady_clock::now() - before;
  release->Signal();
  const auto finish_status = finished->WaitFor(std::chrono::seconds(1));
  destroyer.join();

  EXPECT_EQ(destroy_status, std::future_status::ready);
  EXPECT_LT(std::chrono::duration_cast<std::chrono::milliseconds>(elapsed).count(),
            1000);
  EXPECT_FALSE(pending_ran->load());
  EXPECT_EQ(pending_cancelled->load(), 1);
  EXPECT_EQ(finish_status, std::future_status::ready);
}

TEST(ProxyTaskRunner, ShutdownCancelsQueuedTasksAndFinalizesOnce) {
  ProxyTaskRunner runner;
  const auto started = std::make_shared<ManualEvent>();
  const auto release = std::make_shared<ManualEvent>();
  ScopedSignal release_on_exit(release);
  const auto shutdown_returned = std::make_shared<ManualEvent>();
  const auto running = std::make_shared<std::atomic<int>>(0);
  const auto cancelled = std::make_shared<std::atomic<int>>(0);
  const auto finalized = std::make_shared<std::atomic<int>>(0);
  const auto ignored_finalizer = std::make_shared<std::atomic<int>>(0);

  ASSERT_TRUE(runner.Post([started, release, running] {
    ++*running;
    started->Signal();
    release->Wait();
  }));
  ASSERT_EQ(started->WaitFor(std::chrono::seconds(1)),
            std::future_status::ready);
  ASSERT_TRUE(runner.Post([running] { ++*running; }, [cancelled] {
    ++*cancelled;
    throw 3;
  }));
  ASSERT_TRUE(runner.Post([running] { ++*running; },
                          [cancelled] { ++*cancelled; }));

  std::thread shutdown([&runner, finalized, shutdown_returned] {
    runner.Shutdown([finalized] { ++*finalized; });
    shutdown_returned->Signal();
  });
  const auto shutdown_status =
      shutdown_returned->WaitFor(std::chrono::milliseconds(200));
  release->Signal();
  shutdown.join();

  runner.Shutdown([ignored_finalizer] { ++*ignored_finalizer; });
  EXPECT_EQ(shutdown_status, std::future_status::ready);
  EXPECT_EQ(cancelled->load(), 2);
  EXPECT_EQ(running->load(), 1);
  EXPECT_FALSE(runner.Post([running] { ++*running; },
                           [cancelled] { ++*cancelled; }));
  EXPECT_EQ(cancelled->load(), 2);

  ASSERT_TRUE(runner.WaitForShutdown(std::chrono::seconds(1)));
  EXPECT_EQ(running->load(), 1);
  EXPECT_EQ(cancelled->load(), 2);
  EXPECT_EQ(finalized->load(), 1);
  EXPECT_EQ(ignored_finalizer->load(), 0);
}

TEST(ProxyTaskRunner, WaitForShutdownUsesTheRequestedTimeout) {
  ProxyTaskRunner runner;
  const auto started = std::make_shared<ManualEvent>();
  const auto release = std::make_shared<ManualEvent>();
  ScopedSignal release_on_exit(release);
  ASSERT_TRUE(runner.Post([started, release] {
    started->Signal();
    release->Wait();
  }));
  ASSERT_EQ(started->WaitFor(std::chrono::seconds(1)),
            std::future_status::ready);

  runner.Shutdown();
  EXPECT_FALSE(runner.WaitForShutdown(std::chrono::milliseconds(20)));
  release->Signal();
  EXPECT_TRUE(runner.WaitForShutdown(std::chrono::seconds(1)));
}

TEST(ProxyTaskRunner, ExceptionsDoNotStopTheWorkerOrShutdown) {
  ProxyTaskRunner runner;
  const auto continued = std::make_shared<ManualEvent>();
  ASSERT_TRUE(runner.Post([] { throw 1; }));
  ASSERT_TRUE(runner.Post([continued] { continued->Signal(); }));
  EXPECT_EQ(continued->WaitFor(std::chrono::seconds(1)),
            std::future_status::ready);

  runner.Shutdown([] { throw 2; });
  EXPECT_TRUE(runner.WaitForShutdown(std::chrono::seconds(1)));
}

}
}
