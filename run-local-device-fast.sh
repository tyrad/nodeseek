#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="${PROJECT_PATH:-nodeseek.xcodeproj}"
SCHEME="${SCHEME:-nodeseek}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-.build/DerivedData}"
BUNDLE_ID="${BUNDLE_ID:-com.mistj.nodeseek}"
DEVICE_ID_CACHE="${DEVICE_ID_CACHE:-.build/local-device-id}"
DEVICE_ID="${DEVICE_ID:-${1:-}}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: missing command: $1" >&2
    exit 1
  fi
}

now_ms() {
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf "%d\n", time() * 1000'
  else
    echo "$(($(date +%s) * 1000))"
  fi
}

print_elapsed() {
  local label="$1"
  local start_ms="$2"
  local end_ms elapsed_ms seconds millis
  end_ms="$(now_ms)"
  elapsed_ms=$((end_ms - start_ms))
  seconds=$((elapsed_ms / 1000))
  millis=$((elapsed_ms % 1000))
  printf "%s took %d.%03ds\n" "$label" "$seconds" "$millis"
}

detect_device_id() {
  xcodebuild -showdestinations -project "$PROJECT_PATH" -scheme "$SCHEME" 2>/dev/null \
    | sed -n '/Available destinations/,/Ineligible destinations/p' \
    | sed -nE 's/.*platform:iOS, arch:arm64, id:([^,]+),.*/\1/p' \
    | head -n 1
}

require_command xcodebuild
require_command xcrun

SCRIPT_START_MS="$(now_ms)"

if [[ -z "$DEVICE_ID" && -f "$DEVICE_ID_CACHE" ]]; then
  DEVICE_ID="$(tr -d '[:space:]' < "$DEVICE_ID_CACHE")"
fi

if [[ -n "$DEVICE_ID" ]]; then
  mkdir -p "$(dirname "$DEVICE_ID_CACHE")"
  printf '%s\n' "$DEVICE_ID" > "$DEVICE_ID_CACHE"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "No cached device id. Detecting once..."
  DEVICE_ID="$(detect_device_id)"
  if [[ -n "$DEVICE_ID" ]]; then
    mkdir -p "$(dirname "$DEVICE_ID_CACHE")"
    printf '%s\n' "$DEVICE_ID" > "$DEVICE_ID_CACHE"
  fi
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "error: no connected eligible iOS device found." >&2
  echo "hint: connect and unlock your iPhone, enable Developer Mode, then run again." >&2
  echo "hint: or pass a device id once: DEVICE_ID=<udid> ./run-local-device-fast.sh" >&2
  exit 1
fi

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION-iphoneos/$SCHEME.app"
BUILD_ARGS=(
  xcodebuild build
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "platform=iOS,id=$DEVICE_ID"
  -derivedDataPath "$DERIVED_DATA_PATH"
  COMPILER_INDEX_STORE_ENABLE=NO
  DEBUG_INFORMATION_FORMAT=dwarf
  ONLY_ACTIVE_ARCH=YES
)

if [[ "${ALLOW_PACKAGE_RESOLUTION:-0}" != "1" ]]; then
  BUILD_ARGS+=(-disableAutomaticPackageResolution)
fi

if [[ "${ALLOW_PROVISIONING_UPDATES:-0}" == "1" ]]; then
  BUILD_ARGS+=(-allowProvisioningUpdates)
fi

echo "Building $SCHEME for device $DEVICE_ID..."
BUILD_START_MS="$(now_ms)"
"${BUILD_ARGS[@]}"
print_elapsed "Build" "$BUILD_START_MS"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: built app not found at $APP_PATH" >&2
  exit 1
fi

echo "Installing $APP_PATH..."
INSTALL_START_MS="$(now_ms)"
xcrun devicectl device install app \
  --device "$DEVICE_ID" \
  "$APP_PATH"
print_elapsed "Install" "$INSTALL_START_MS"

echo "Launching $BUNDLE_ID..."
LAUNCH_ARGS=(xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing)
if [[ "${CONSOLE:-0}" == "1" ]]; then
  LAUNCH_ARGS+=(--console)
fi
LAUNCH_ARGS+=("$BUNDLE_ID")
LAUNCH_START_MS="$(now_ms)"
"${LAUNCH_ARGS[@]}"
print_elapsed "Launch command" "$LAUNCH_START_MS"

print_elapsed "Total" "$SCRIPT_START_MS"
echo "Done."
