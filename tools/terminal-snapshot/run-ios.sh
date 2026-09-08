#!/bin/bash
set -euo pipefail

# 使用独立验证 App，不覆盖 NodeSeek，也不修改其账户与缓存。
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/.build/terminal-snapshot"
SIMULATOR_ID="${1:?Usage: run-ios.sh SIMULATOR_ID}"
APP="$OUT/TerminalSnapshotProbe.app"
mkdir -p "$APP" "$OUT/ios/light" "$OUT/ios/dark"
node "$ROOT/tools/terminal-snapshot/prepare.mjs" "$OUT"
cp "$OUT"/*.html "$APP/"
cp "$OUT/inputs.json" "$OUT/ios/light/inputs.json"
cp "$OUT/inputs.json" "$OUT/ios/dark/inputs.json"
SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
ARCH="$(uname -m)"
xcrun --sdk iphonesimulator swiftc -parse-as-library -sdk "$SDK_PATH" -target "$ARCH-apple-ios18.0-simulator" \
    "$ROOT/tools/terminal-snapshot/Snapshot.swift" -o "$APP/TerminalSnapshotProbe"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TerminalSnapshotProbe</string>
<key>CFBundleIdentifier</key><string>com.nodeseek.TerminalSnapshotProbe</string>
<key>CFBundleName</key><string>TerminalSnapshotProbe</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSRequiresIPhoneOS</key><true/>
<key>UILaunchScreen</key><dict/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
swiftc "$ROOT/tools/terminal-snapshot/VerifyImages.swift" -o "$OUT/verify-images"
xcrun simctl install "$SIMULATOR_ID" "$APP"
CONTAINER="$(xcrun simctl get_app_container "$SIMULATOR_ID" com.nodeseek.TerminalSnapshotProbe data)"
for appearance in light dark; do
  RUN_ID="$(uuidgen)"
  for report in basic ip long-report controls; do
    xcrun simctl launch --terminate-running-process "$SIMULATOR_ID" com.nodeseek.TerminalSnapshotProbe "$report" "$RUN_ID" "$appearance"
    completed=false
    for attempt in {1..40}; do
        if [[ -f "$CONTAINER/Documents/$RUN_ID/$report.error.txt" ]]; then
            cat "$CONTAINER/Documents/$RUN_ID/$report.error.txt" >&2
            exit 1
        fi
        if [[ -f "$CONTAINER/Documents/$RUN_ID/$report.json" ]]; then
            cp "$CONTAINER/Documents/$RUN_ID/$report.png" "$CONTAINER/Documents/$RUN_ID/$report.json" "$OUT/ios/$appearance/"
            completed=true
            break
        fi
        sleep 1
    done
    if [[ "$completed" != true ]]; then
        echo "Timed out: $report" >&2
        exit 1
    fi
  done
  node "$ROOT/tools/terminal-snapshot/verify.mjs" "$OUT/ios/$appearance"
  "$OUT/verify-images" "$OUT/ios/$appearance"
done
xcrun simctl terminate "$SIMULATOR_ID" com.nodeseek.TerminalSnapshotProbe
