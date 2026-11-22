SHELL := /bin/bash
.SHELLFLAGS := -e -u -o pipefail -c

PROJECT ?= nodeseek.xcodeproj
SCHEME ?= nodeseek
CONFIGURATION ?= Debug
SIMULATOR_NAME ?= iPhone 16
SIMULATOR_OS ?= 18.0
SIMULATOR_ID ?=
BUILD_DESTINATION ?= generic/platform=iOS Simulator
DERIVED_DATA ?= .build/XcodeDerivedData
SOURCE_PACKAGES ?= .build/SourcePackages
SWIFTLINT ?= swiftlint
SWIFTLINT_CONFIG ?= .swiftlint.yml
export TEST

ifneq ($(strip $(SIMULATOR_ID)),)
TEST_DESTINATION ?= platform=iOS Simulator,id=$(SIMULATOR_ID)
else ifneq ($(strip $(SIMULATOR_OS)),)
TEST_DESTINATION ?= platform=iOS Simulator,name=$(SIMULATOR_NAME),OS=$(SIMULATOR_OS)
else
TEST_DESTINATION ?= platform=iOS Simulator,name=$(SIMULATOR_NAME)
endif

RUNTIME_TEST_CLASSES := \
	NodeSeekServiceTests \
	NodeSeekCommentSubmitterTests \
	CookieBridgeTests \
	HTMLContentRendererTests \
	DTCoreTextHTMLContentRendererTests \
	LoginWebViewControllerTests

XCODE_BASE = \
	-project "$(PROJECT)" \
	-scheme "$(SCHEME)" \
	-configuration "$(CONFIGURATION)" \
	-derivedDataPath "$(DERIVED_DATA)" \
	-clonedSourcePackagesDirPath "$(SOURCE_PACKAGES)" \
	CODE_SIGNING_ALLOWED=NO \
	-parallel-testing-enabled NO \
	-maximum-concurrent-test-simulator-destinations 1

XCODE_BUILD_COMMON = \
	$(XCODE_BASE) \
	-destination "$(BUILD_DESTINATION)"

# 测试结束后 xcodebuild 默认会跑 simctl diagnose 收集模拟器诊断，常卡到 600 秒超时才退出。
XCODE_TEST_COMMON = \
	$(XCODE_BASE) \
	-destination "$(TEST_DESTINATION)" \
	-collect-test-diagnostics never

.PHONY: help lint lint-fix quality spm-test xcode-build-tests xcode-test-runtime-core xcode-test-core xcode-test-class xcode-test-full

help:
	@printf '%s\n' \
		'Available commands:' \
		'  make help' \
		'  make lint' \
		'  make lint-fix' \
		'  make quality' \
		'  make spm-test' \
		'  make xcode-build-tests' \
		'  make xcode-test-runtime-core' \
		'  make xcode-test-core  # alias' \
		'  make xcode-test-class TEST=NodeSeekServiceTests' \
		'  make xcode-test-class TEST="NodeSeekServiceTests CookieBridgeTests"' \
		'  make xcode-test-class TEST=NodeSeekServiceTests SIMULATOR_NAME="iPhone 16" SIMULATOR_OS=18.0' \
		'  make xcode-test-full' \
		'  make e2e-list  # List case IDs, profiles and account requirements' \
		'  make e2e-case CASE=member-compose' \
		'  make e2e-draft  # Verify local draft recovery and discard after relaunch' \
		'  make e2e-comment  # Publish and edit a real reply in the designated thread' \
		'  make e2e-login  # NodeSeek sign-in and session persistence' \
		'  make e2e-smoke  # Midscene on NodeSeek E2E' \
		'' \
		'Variables:' \
		'  BUILD_DESTINATION defaults to $(BUILD_DESTINATION)' \
		'  TEST_DESTINATION defaults to $(TEST_DESTINATION)' \
		'  Override BUILD_DESTINATION or TEST_DESTINATION directly; set SIMULATOR_ID for a specific simulator UDID.' \
		'  SWIFTLINT defaults to $(SWIFTLINT), config: $(SWIFTLINT_CONFIG).'

lint:
	@if ! command -v "$(SWIFTLINT)" >/dev/null 2>&1; then \
		echo "SwiftLint not found. Install it with: brew install swiftlint" >&2; \
		exit 127; \
	fi
	$(SWIFTLINT) lint --quiet --config "$(SWIFTLINT_CONFIG)"

lint-fix:
	@if ! command -v "$(SWIFTLINT)" >/dev/null 2>&1; then \
		echo "SwiftLint not found. Install it with: brew install swiftlint" >&2; \
		exit 127; \
	fi
	$(SWIFTLINT) --fix --quiet --config "$(SWIFTLINT_CONFIG)"

quality: lint spm-test

spm-test:
	swift test

xcode-build-tests:
	xcodebuild -quiet build-for-testing $(XCODE_BUILD_COMMON)

xcode-test-runtime-core: xcode-build-tests
	xcodebuild -quiet test-without-building $(XCODE_TEST_COMMON) $(addprefix -only-testing:nodeseekTests/,$(RUNTIME_TEST_CLASSES))

xcode-test-core: xcode-test-runtime-core

xcode-test-class:
	@if [[ -z "$${TEST:-}" ]]; then \
		echo "Usage: make xcode-test-class TEST=\"NodeSeekServiceTests [OtherTests ...]\"" >&2; \
		exit 2; \
	fi
	@for name in $${TEST}; do \
		if [[ ! "$${name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$$ ]]; then \
			echo "Invalid TEST: $${name}" >&2; \
			echo "TEST must be space-separated XCTest class identifiers: letters, numbers, underscore." >&2; \
			exit 2; \
		fi; \
	done
	$(MAKE) xcode-build-tests
	xcodebuild -quiet test-without-building $(XCODE_TEST_COMMON) $(addprefix -only-testing:nodeseekTests/,$(TEST))

xcode-test-full:
	xcodebuild -quiet test $(XCODE_TEST_COMMON)

.PHONY: e2e-list e2e-case e2e-smoke e2e-login e2e-comment e2e-draft
e2e-list:
	@bash .agents/skills/nodeseek-e2e/scripts/run.sh --list

e2e-case:
	@bash .agents/skills/nodeseek-e2e/scripts/run.sh --case "$$CASE"

e2e-draft:
	E2E_PROFILE=draft bash .agents/skills/nodeseek-e2e/scripts/run.sh

e2e-comment:
	E2E_PROFILE=comment bash .agents/skills/nodeseek-e2e/scripts/run.sh

e2e-login:
	E2E_PROFILE=login bash .agents/skills/nodeseek-e2e/scripts/run.sh

e2e-smoke:
	bash .agents/skills/nodeseek-e2e/scripts/run.sh
