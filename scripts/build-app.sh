#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Debug}"
APP_NAME="Corona"
XCODE_CONFIGURATION="$CONFIGURATION"
PACKAGE_CONFIGURATION="debug"
APP_DIR="$ROOT_DIR/.build/app/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/.build/dist"
XCODE_BUILD_DIR="$ROOT_DIR/build"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

case "$CONFIGURATION" in
  debug) XCODE_CONFIGURATION="Debug" ;;
  release) XCODE_CONFIGURATION="Release"; PACKAGE_CONFIGURATION="release" ;;
  Release) PACKAGE_CONFIGURATION="release" ;;
esac

cd "$ROOT_DIR"

XCODE_ARGS=(
  -project Corona.xcodeproj
  -target CoronaApp
  -configuration "$XCODE_CONFIGURATION"
  BUILD_DIR="$XCODE_BUILD_DIR"
  SYMROOT="$XCODE_BUILD_DIR"
)

if [[ "$XCODE_CONFIGURATION" == "Release" ]]; then
  if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
  fi
  if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "Release signing requires SIGN_IDENTITY or DEVELOPER_ID_APPLICATION." >&2
    exit 1
  fi
  XCODE_ARGS+=(CODE_SIGN_IDENTITY="$SIGN_IDENTITY")
fi

xcodebuild "${XCODE_ARGS[@]}" build

rm -rf "$APP_DIR"
mkdir -p "$(dirname "$APP_DIR")" "$DIST_DIR"
ditto "$XCODE_BUILD_DIR/$XCODE_CONFIGURATION/$APP_NAME.app" "$APP_DIR"
ditto -c -k --keepParent "$APP_DIR" "$DIST_DIR/$APP_NAME-$PACKAGE_CONFIGURATION.zip"

echo "$APP_DIR"
