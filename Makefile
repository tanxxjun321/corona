APP_NAME := Corona
APP_DIR := .build/app/$(APP_NAME).app
DIST_DIR := .build/dist
XCODE_BUILD_DIR := .build/xcode-build
CONFIGURATION ?= Debug
SIGN_IDENTITY ?= -

# Only override the Xcode project's signing settings when the caller
# explicitly provides an identity; otherwise the pbxproj configuration
# (Debug: Apple Development, Release: Developer ID Application) applies.
ifneq ($(filter command line environment environment override,$(origin SIGN_IDENTITY)),)
SIGN_IDENTITY_OVERRIDE := CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)"
else
SIGN_IDENTITY_OVERRIDE :=
endif

.PHONY: build swift-build test check-manifest app release-app notarize verify release xcode-app run-app clean

build:
	xcodebuild -project Corona.xcodeproj -target CoronaApp -configuration Debug build

swift-build:
	swift build

test:
	swift test

check-manifest:
	bash scripts/check-pbxproj-manifest.sh

app:
	rm -rf "$(XCODE_BUILD_DIR)"
	xcodebuild -project Corona.xcodeproj -scheme CoronaApp -configuration "$(CONFIGURATION)" -destination 'platform=macOS' BUILD_DIR="$(XCODE_BUILD_DIR)" SYMROOT="$(XCODE_BUILD_DIR)" $(SIGN_IDENTITY_OVERRIDE) build
	rm -rf "$(APP_DIR)"
	mkdir -p "$(dir $(APP_DIR))" "$(DIST_DIR)"
	ditto "$(XCODE_BUILD_DIR)/$(CONFIGURATION)/$(APP_NAME).app" "$(APP_DIR)"
	ditto -c -k --keepParent "$(APP_DIR)" "$(DIST_DIR)/$(APP_NAME)-$(shell echo $(CONFIGURATION) | tr '[:upper:]' '[:lower:]').zip"

release-app:
	$(MAKE) app CONFIGURATION=Release

notarize:
	bash scripts/notarize-app.sh

verify:
	codesign --verify --deep --strict --verbose=2 .build/app/Corona.app
	spctl --assess --type execute --verbose=2 .build/app/Corona.app

release: clean test release-app notarize verify

xcode-app:
	xcodebuild -project Corona.xcodeproj -target CoronaApp -configuration Debug build

run-app: app
	open .build/app/Corona.app

clean:
	rm -rf .build/app .build/dist .build/xcode-build
	xcodebuild -project Corona.xcodeproj -target CoronaApp clean
	swift package clean
