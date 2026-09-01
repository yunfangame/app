SHELL := /bin/bash

PLATFORM ?= macos
LOCAL_FLUTTER := $(lastword $(sort $(wildcard $(CURDIR)-toolchains/flutter-*/flutter/bin/flutter)))
FLUTTER_BIN ?= $(if $(LOCAL_FLUTTER),$(LOCAL_FLUTTER),flutter)
DART_BIN ?= $(if $(LOCAL_FLUTTER),$(dir $(LOCAL_FLUTTER))dart,dart)
BUILDKIT := plugins/setup/buildkit/run_build_tool.sh
ARCH_ARG := $(if $(ARCH),--arch $(ARCH),)
TARGET_PLATFORM_ARG := $(if $(TARGET_PLATFORM),--target-platform $(TARGET_PLATFORM),)
FORCE_ARG := $(if $(filter 1 true yes,$(FORCE)),--force,)
CONFIG_URL_ARG := $(if $(CONFIG_URL),--config-url "$(CONFIG_URL)",)

.PHONY: help debug submodules core core-macos core-linux core-windows core-android

help:
	@echo 'make debug                        # run Debug with encrypted config keys'
	@echo 'make debug DEVICE=<device-id>'
	@echo 'make debug CONFIG_URL=<encrypted-config-url>'
	@echo 'make core                         # build macOS core by default'
	@echo 'make core PLATFORM=linux ARCH=amd64'
	@echo 'make core-macos ARCH=arm64'
	@echo 'make core-android ARCH=arm64'
	@echo 'make core-android TARGET_PLATFORM=android-arm64'
	@echo 'make core-macos FORCE=1            # bypass setup build cache'

debug:
	"$(DART_BIN)" run tooling/run_debug.dart --device $(if $(DEVICE),$(DEVICE),macos) --flutter "$(FLUTTER_BIN)" $(CONFIG_URL_ARG)

submodules:
	git submodule update --init --recursive

core:
	bash $(BUILDKIT) $(PLATFORM) $(ARCH_ARG) $(TARGET_PLATFORM_ARG) $(FORCE_ARG)

core-macos:
	$(MAKE) core PLATFORM=macos

core-linux:
	$(MAKE) core PLATFORM=linux

core-windows:
	$(MAKE) core PLATFORM=windows

core-android:
	$(MAKE) core PLATFORM=android
