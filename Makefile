SHELL := /bin/bash
.SHELLFLAGS := -e -u -o pipefail -c

PROJECT ?= nodeseek.xcodeproj
SCHEME ?= nodeseek
CONFIGURATION ?= Debug
SIMULATOR_ID ?= F1FA4EFA-0399-438E-AC84-9326D32938E4
DERIVED_DATA ?= .build/XcodeDerivedData
SOURCE_PACKAGES ?= .build/SourcePackages
export TEST

RUNTIME_TEST_CLASSES := \
	NodeSeekServiceTests \
	NodeSeekCommentSubmitterTests \
	CookieBridgeTests \
	HTMLContentRendererTests \
	DTCoreTextHTMLContentRendererTests \
	LoginWebViewControllerTests

XCODE_COMMON = \
	-project "$(PROJECT)" \
	-scheme "$(SCHEME)" \
	-configuration "$(CONFIGURATION)" \
	-destination "platform=iOS Simulator,id=$(SIMULATOR_ID)" \
	-derivedDataPath "$(DERIVED_DATA)" \
	-clonedSourcePackagesDirPath "$(SOURCE_PACKAGES)" \
	CODE_SIGNING_ALLOWED=NO \
	-parallel-testing-enabled NO \
	-maximum-concurrent-test-simulator-destinations 1

.PHONY: help spm-test xcode-build-tests xcode-test-runtime-core xcode-test-core xcode-test-class xcode-test-full

help:
	@printf '%s\n' \
		'Available commands:' \
		'  make help' \
		'  make spm-test' \
		'  make xcode-build-tests' \
		'  make xcode-test-runtime-core' \
		'  make xcode-test-core  # alias' \
		'  make xcode-test-class TEST=NodeSeekServiceTests' \
		'  make xcode-test-class TEST=NodeSeekServiceTests SIMULATOR_ID=<simulator-udid>' \
		'  make xcode-test-full' \
		'' \
		'Variables:' \
		'  SIMULATOR_ID defaults to $(SIMULATOR_ID) and is local/machine-specific; override as needed.'

spm-test:
	swift test

xcode-build-tests:
	xcodebuild -quiet build-for-testing $(XCODE_COMMON)

xcode-test-runtime-core: xcode-build-tests
	xcodebuild -quiet test-without-building $(XCODE_COMMON) $(addprefix -only-testing:nodeseekTests/,$(RUNTIME_TEST_CLASSES))

xcode-test-core: xcode-test-runtime-core

xcode-test-class:
	@if [[ -z "$${TEST:-}" ]]; then \
		echo "Usage: make xcode-test-class TEST=NodeSeekServiceTests" >&2; \
		exit 2; \
	fi
	@if [[ ! "$${TEST}" =~ ^[A-Za-z_][A-Za-z0-9_]*$$ ]]; then \
		echo "Invalid TEST: $${TEST}" >&2; \
		echo "TEST must be a simple XCTest class identifier: letters, numbers, underscore." >&2; \
		echo "Usage: make xcode-test-class TEST=NodeSeekServiceTests" >&2; \
		exit 2; \
	fi
	$(MAKE) xcode-build-tests
	xcodebuild -quiet test-without-building $(XCODE_COMMON) -only-testing:nodeseekTests/$$TEST

xcode-test-full:
	xcodebuild -quiet test $(XCODE_COMMON)
