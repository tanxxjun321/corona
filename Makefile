.PHONY: build test app run-app clean

build:
	swift build

test:
	swift test

app:
	bash scripts/build-app.sh

run-app: app
	open .build/app/Corona.app

clean:
	rm -rf .build/app
	swift package clean
