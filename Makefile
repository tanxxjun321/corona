.PHONY: build test app xcode-app run-app clean

build:
	swift build

test:
	swift test

app:
	bash scripts/build-app.sh

xcode-app:
	xcodebuild -project Corona.xcodeproj -target CoronaApp -configuration Debug build

run-app: app
	open .build/app/Corona.app

clean:
	rm -rf .build/app
	swift package clean
