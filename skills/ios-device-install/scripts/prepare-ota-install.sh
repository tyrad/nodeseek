#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="${PROJECT_PATH:-nodeseek.xcodeproj}"
SCHEME="${SCHEME:-nodeseek}"
CONFIGURATION="${CONFIGURATION:-Debug}"
TEAM_ID="${TEAM_ID:-Z9K94479DQ}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-.build/DerivedData-ota}"
OUTPUT_DIR="${OUTPUT_DIR:-.build/ota}"
SERVE_DIR="${SERVE_DIR:-/tmp/nodeseek-ota}"
SERVE_PORT="${SERVE_PORT:-8765}"
LAUNCHD_LABEL="${LAUNCHD_LABEL:-local.nodeseek.ota}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage: bash skills/ios-device-install/scripts/prepare-ota-install.sh

Builds an iOS .ipa, creates an OTA manifest/install page, and exposes it via Tailscale Serve.

Environment overrides:
  PROJECT_PATH       default: nodeseek.xcodeproj
  SCHEME             default: nodeseek
  CONFIGURATION      default: Debug
  TEAM_ID            default: Z9K94479DQ
  DERIVED_DATA_PATH  default: .build/DerivedData-ota
  OUTPUT_DIR         default: .build/ota
  SERVE_DIR          default: /tmp/nodeseek-ota
  SERVE_PORT         default: 8765
  LAUNCHD_LABEL      default: local.nodeseek.ota
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: missing command: $1" >&2
    exit 1
  fi
}

require_command xcodebuild
require_command tailscale
require_command jq
require_command python3

TAILSCALE_DNS="$(tailscale status --json | jq -r '.Self.DNSName // empty' | sed 's/\.$//')"
if [[ -z "$TAILSCALE_DNS" ]]; then
  echo "error: Tailscale MagicDNS name not found. Is Tailscale connected?" >&2
  exit 1
fi

ARCHIVE_PATH="$OUTPUT_DIR/$SCHEME.xcarchive"
EXPORT_PATH="$OUTPUT_DIR/export"
EXPORT_OPTIONS_PLIST="$OUTPUT_DIR/ExportOptions.plist"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

cat > "$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>destination</key>
	<string>export</string>
	<key>method</key>
	<string>debugging</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>stripSwiftSymbols</key>
	<false/>
	<key>thinning</key>
	<string>&lt;none&gt;</string>
</dict>
</plist>
EOF

echo "Archiving $SCHEME..."
xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -allowProvisioningUpdates \
  COMPILER_INDEX_STORE_ENABLE=NO \
  DEBUG_INFORMATION_FORMAT=dwarf

echo "Exporting IPA..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  -allowProvisioningUpdates

IPA_PATH="$(find "$EXPORT_PATH" -maxdepth 1 -type f -name '*.ipa' | head -n 1)"
if [[ -z "$IPA_PATH" || ! -f "$IPA_PATH" ]]; then
  echo "error: exported IPA not found in $EXPORT_PATH" >&2
  exit 1
fi

APP_INFO="$(python3 - "$IPA_PATH" <<'PY'
import plistlib, sys, zipfile
ipa = sys.argv[1]
with zipfile.ZipFile(ipa) as z:
    info_path = next(n for n in z.namelist() if n.startswith("Payload/") and n.endswith(".app/Info.plist"))
    info = plistlib.loads(z.read(info_path))
print(info["CFBundleIdentifier"])
print(info.get("CFBundleVersion", "1"))
print(info.get("CFBundleDisplayName") or info.get("CFBundleName") or "iOS App")
PY
)"

BUNDLE_ID="$(printf '%s\n' "$APP_INFO" | sed -n '1p')"
BUNDLE_VERSION="$(printf '%s\n' "$APP_INFO" | sed -n '2p')"
APP_TITLE="$(printf '%s\n' "$APP_INFO" | sed -n '3p')"
IPA_NAME="$(basename "$IPA_PATH")"

rm -rf "$SERVE_DIR"
mkdir -p "$SERVE_DIR"
cp "$IPA_PATH" "$SERVE_DIR/$IPA_NAME"

ICON_SOURCE="$(find "$(dirname "$PROJECT_PATH")" -path '*/AppIcon.appiconset/AppIcon.png' -type f | head -n 1)"
if [[ -n "$ICON_SOURCE" && -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$SERVE_DIR/icon.png"
else
  python3 - "$SERVE_DIR/icon.png" <<'PY'
from pathlib import Path
import base64, sys
png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
Path(sys.argv[1]).write_bytes(base64.b64decode(png))
PY
fi

python3 - "$SERVE_DIR" "$TAILSCALE_DNS" "$IPA_NAME" "$BUNDLE_ID" "$BUNDLE_VERSION" "$APP_TITLE" <<'PY'
from __future__ import annotations

from html import escape as html_escape
from pathlib import Path
import plistlib
import sys

serve_dir = Path(sys.argv[1])
host = sys.argv[2]
ipa_name = sys.argv[3]
bundle_id = sys.argv[4]
bundle_version = sys.argv[5]
app_title = sys.argv[6]

manifest = {
    "items": [
        {
            "assets": [
                {"kind": "software-package", "url": f"https://{host}/{ipa_name}"},
                {"kind": "display-image", "needs-shine": False, "url": f"https://{host}/icon.png"},
                {"kind": "full-size-image", "needs-shine": False, "url": f"https://{host}/icon.png"},
            ],
            "metadata": {
                "bundle-identifier": bundle_id,
                "bundle-version": bundle_version,
                "kind": "software",
                "title": app_title,
            },
        }
    ]
}
manifest_path = serve_dir / "manifest.xml"
with manifest_path.open("wb") as f:
    plistlib.dump(manifest, f, fmt=plistlib.FMT_XML, sort_keys=False)

title_html = html_escape(app_title)
bundle_id_html = html_escape(bundle_id)
page = f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Install {title_html}</title>
  <style>
    body {{ font: -apple-system-body; margin: 32px; }}
    a {{ display: inline-block; font-size: 20px; padding: 12px 16px; border-radius: 10px; background: #0a84ff; color: white; text-decoration: none; }}
  </style>
</head>
<body>
  <p>{title_html} ({bundle_id_html})</p>
  <a href="itms-services://?action=download-manifest&amp;url=https://{host}/manifest.xml">安装到 iPhone</a>
</body>
</html>
"""
(serve_dir / "index.html").write_text(page, encoding="utf-8")
PY

echo "Starting local HTTP server on 127.0.0.1:$SERVE_PORT..."
launchctl remove "$LAUNCHD_LABEL" 2>/dev/null || true
launchctl submit -l "$LAUNCHD_LABEL" -- /usr/bin/python3 -m http.server "$SERVE_PORT" --bind 127.0.0.1 --directory "$SERVE_DIR"
sleep 1

curl --connect-timeout 2 --max-time 5 -fsSI "http://127.0.0.1:$SERVE_PORT/manifest.xml" >/dev/null

echo "Configuring Tailscale Serve..."
tailscale serve --yes --bg "$SERVE_PORT" >/dev/null

curl --connect-timeout 3 --max-time 8 -fsSI "https://$TAILSCALE_DNS/manifest.xml" >/dev/null
curl --connect-timeout 3 --max-time 8 -fsSI "https://$TAILSCALE_DNS/$IPA_NAME" >/dev/null

echo
echo "Install URL:"
echo "https://$TAILSCALE_DNS/"
echo
echo "Open this URL in iPhone Safari while Tailscale is connected."
echo "If iOS refuses to install, register the iPhone UDID in the development provisioning profile and rerun this script."
