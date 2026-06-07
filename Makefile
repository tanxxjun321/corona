.PHONY: build swift-build test app release-app notarize verify release xcode-app run-app clean

build:
	xcodebuild -project Corona.xcodeproj -target CoronaApp -configuration Debug build

swift-build:
	swift build

test:
	swift test

app:
	bash scripts/build-app.sh

release-app:
	CONFIGURATION=Release bash scripts/build-app.sh

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
	rm -rf .build/app .build/dist
	xcodebuild -project Corona.xcodeproj -target CoronaApp clean
	swift package clean
