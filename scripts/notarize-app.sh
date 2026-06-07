#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Corona"
APP_DIR="${APP_DIR:-$ROOT_DIR/.build/app/$APP_NAME.app}"
ZIP_PATH="${ZIP_PATH:-$ROOT_DIR/.build/dist/$APP_NAME-release.zip}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Set NOTARY_PROFILE to a notarytool keychain profile name." >&2
  exit 1
fi

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Missing package: $ZIP_PATH" >&2
  exit 1
fi

xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
spctl --assess --type execute --verbose=2 "$APP_DIR"

echo "$APP_DIR"
