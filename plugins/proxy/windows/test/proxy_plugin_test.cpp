#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>

#include <memory>
#include <string>
#include <variant>

#include "proxy_plugin.h"

namespace proxy {
namespace test {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;

}  // namespace

TEST(ProxyPlugin, UnknownMethodIsNotImplemented) {
  ProxyPlugin plugin;
  bool not_implemented = false;
  plugin.HandleMethodCall(
      MethodCall("unknown", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          nullptr, nullptr,
          [&not_implemented]() { not_implemented = true; }));

  EXPECT_TRUE(not_implemented);
}

TEST(ProxyPlugin, StartProxyRejectsMissingArguments) {
  ProxyPlugin plugin;
  std::string error_code;
  plugin.HandleMethodCall(
      MethodCall("StartProxy", std::make_unique<EncodableValue>(EncodableMap())),
      std::make_unique<MethodResultFunctions<>>(
          nullptr,
          [&error_code](
              const std::string& code,
              const std::string& message,
              const EncodableValue* details) { error_code = code; },
          nullptr));

  EXPECT_EQ(error_code, "bad_args");
}

TEST(ProxyPlugin, StartProxyRejectsInvalidPort) {
  ProxyPlugin plugin;
  std::string error_code;
  EncodableMap arguments = {
      {EncodableValue("port"), EncodableValue(70000)},
      {EncodableValue("bypassDomain"), EncodableValue(EncodableList())}};

  plugin.HandleMethodCall(
      MethodCall(
          "StartProxy",
          std::make_unique<EncodableValue>(std::move(arguments))),
      std::make_unique<MethodResultFunctions<>>(
          nullptr,
          [&error_code](
              const std::string& code,
              const std::string& message,
              const EncodableValue* details) { error_code = code; },
          nullptr));

  EXPECT_EQ(error_code, "bad_args");
}

TEST(ProxyPlugin, StartProxyRejectsNonStringBypassDomain) {
  ProxyPlugin plugin;
  std::string error_code;
  EncodableList bypass_domain = {
      EncodableValue("localhost"),
      EncodableValue(1)};
  EncodableMap arguments = {
      {EncodableValue("port"), EncodableValue(7890)},
      {EncodableValue("bypassDomain"),
       EncodableValue(std::move(bypass_domain))}};

  plugin.HandleMethodCall(
      MethodCall(
          "StartProxy",
          std::make_unique<EncodableValue>(std::move(arguments))),
      std::make_unique<MethodResultFunctions<>>(
          nullptr,
          [&error_code](
              const std::string& code,
              const std::string& message,
              const EncodableValue* details) { error_code = code; },
          nullptr));

  EXPECT_EQ(error_code, "bad_args");
}

TEST(ProxyPlugin, StopProxyDetailedRejectsInvalidExpectedPort) {
  ProxyPlugin plugin;
  std::string error_code;
  EncodableMap arguments = {
      {EncodableValue("expectedPort"), EncodableValue(0)}};

  plugin.HandleMethodCall(
      MethodCall(
          "StopProxyDetailed",
          std::make_unique<EncodableValue>(std::move(arguments))),
      std::make_unique<MethodResultFunctions<>>(
          nullptr,
          [&error_code](
              const std::string& code,
              const std::string& message,
              const EncodableValue* details) { error_code = code; },
          nullptr));

  EXPECT_EQ(error_code, "bad_args");
}

TEST(ProxyPlugin, InspectProxyRejectsMissingExpectedPort) {
  ProxyPlugin plugin;
  std::string error_code;

  plugin.HandleMethodCall(
      MethodCall(
          "InspectProxy",
          std::make_unique<EncodableValue>(EncodableMap())),
      std::make_unique<MethodResultFunctions<>>(
          nullptr,
          [&error_code](
              const std::string& code,
              const std::string& message,
              const EncodableValue* details) { error_code = code; },
          nullptr));

  EXPECT_EQ(error_code, "bad_args");
}

TEST(ProxyPlugin, DetailedStartAndStopRoundTripCurrentUserProxy) {
  ProxyPlugin plugin;
  bool start_called = false;
  bool start_success = false;
  bool start_enabled = false;
  std::string start_server;
  EncodableMap start_arguments = {
      {EncodableValue("port"), EncodableValue(7890)},
      {EncodableValue("bypassDomain"),
       EncodableValue(EncodableList{EncodableValue("localhost")})}};

  plugin.HandleMethodCall(
      MethodCall(
          "StartProxyDetailed",
          std::make_unique<EncodableValue>(std::move(start_arguments))),
      std::make_unique<MethodResultFunctions<>>(
          [&start_called, &start_success, &start_enabled, &start_server](
              const EncodableValue* value) {
            start_called = true;
            const auto* map = std::get_if<EncodableMap>(value);
            if (map == nullptr) {
              return;
            }
            const auto success = map->find(EncodableValue("success"));
            const auto enabled = map->find(EncodableValue("enabled"));
            const auto server = map->find(EncodableValue("server"));
            if (success != map->end()) {
              start_success = std::get<bool>(success->second);
            }
            if (enabled != map->end()) {
              start_enabled = std::get<bool>(enabled->second);
            }
            if (server != map->end()) {
              start_server = std::get<std::string>(server->second);
            }
          },
          nullptr,
          nullptr));

  bool stop_called = false;
  bool stop_success = false;
  bool stop_enabled = true;
  EncodableMap stop_arguments = {
      {EncodableValue("expectedPort"), EncodableValue(7890)}};
  plugin.HandleMethodCall(
      MethodCall(
          "StopProxyDetailed",
          std::make_unique<EncodableValue>(std::move(stop_arguments))),
      std::make_unique<MethodResultFunctions<>>(
          [&stop_called, &stop_success, &stop_enabled](
              const EncodableValue* value) {
            stop_called = true;
            const auto* map = std::get_if<EncodableMap>(value);
            if (map == nullptr) {
              return;
            }
            const auto success = map->find(EncodableValue("success"));
            const auto enabled = map->find(EncodableValue("enabled"));
            if (success != map->end()) {
              stop_success = std::get<bool>(success->second);
            }
            if (enabled != map->end()) {
              stop_enabled = std::get<bool>(enabled->second);
            }
          },
          nullptr,
          nullptr));

  EXPECT_TRUE(start_called);
  EXPECT_TRUE(start_success);
  EXPECT_TRUE(start_enabled);
  EXPECT_EQ(start_server, "127.0.0.1:7890");
  EXPECT_TRUE(stop_called);
  EXPECT_TRUE(stop_success);
  EXPECT_FALSE(stop_enabled);
}

}  // namespace test
}  // namespace proxy
