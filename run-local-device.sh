#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="${PROJECT_PATH:-nodeseek.xcodeproj}"
SCHEME="${SCHEME:-nodeseek}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-.build/DerivedData}"
DEVICE_ID="${DEVICE_ID:-${1:-}}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: missing command: $1" >&2
    exit 1
  fi
}

detect_device_id() {
  xcodebuild -showdestinations -project "$PROJECT_PATH" -scheme "$SCHEME" 2>/dev/null \
    | sed -n '/Available destinations/,/Ineligible destinations/p' \
    | sed -nE 's/.*platform:iOS, arch:arm64, id:([^,]+),.*/\1/p' \
    | head -n 1
}

require_command xcodebuild
require_command xcrun

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(detect_device_id)"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "error: no connected eligible iOS device found." >&2
  echo "hint: connect and unlock your iPhone, enable Developer Mode, then run again." >&2
  echo "hint: or pass a device id: DEVICE_ID=<udid> ./run-local-device.sh" >&2
  exit 1
fi

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION-iphoneos/$SCHEME.app"

echo "Building $SCHEME for device $DEVICE_ID..."
xcodebuild build \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -allowProvisioningUpdates

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: built app not found at $APP_PATH" >&2
  exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print:CFBundleIdentifier' "$APP_PATH/Info.plist")"

echo "Installing $APP_PATH..."
xcrun devicectl device install app \
  --device "$DEVICE_ID" \
  "$APP_PATH"

echo "Launching $BUNDLE_ID..."
LAUNCH_ARGS=(xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing)
if [[ "${CONSOLE:-0}" == "1" ]]; then
  LAUNCH_ARGS+=(--console)
fi
LAUNCH_ARGS+=("$BUNDLE_ID")
"${LAUNCH_ARGS[@]}"

echo "Done."
