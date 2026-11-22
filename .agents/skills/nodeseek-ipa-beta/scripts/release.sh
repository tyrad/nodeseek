#!/bin/bash
# 从当前工作区归档，按已登记设备导出，再发布到 iOS Shelf。
set -euo pipefail
publisher="$(cd "$(dirname "$0")" && pwd)/publish.py"
cd "$(git rev-parse --show-toplevel)"
if [[ ! -f nodeseek.xcodeproj/project.pbxproj ]]; then
  echo "请从 NodeSeek 工作区执行。" >&2
  exit 1
fi
publish() (
  if [[ -z "${IOS_SHELF_API_KEY:-}" && -r "$HOME/.config/ios-shelf/nodeseek.env" ]]; then
    source "$HOME/.config/ios-shelf/nodeseek.env"
  fi
  python3 "$publisher" "$@"
)
# 在耗时的归档前确认该 Mac 可以访问内测服务。
publish list --worktree "$(basename "$PWD")" >/dev/null
mkdir -p .build
stage=$(mktemp -d "$PWD/.build/shelf-release.XXXXXXXX")
commit=$(git rev-parse --short=12 HEAD)
branch=$(git branch --show-current)
echo "归档与导出目录 $stage"
run_xcode() {
  local log=$1
  shift
  if ! env -u IOS_SHELF_API_KEY xcodebuild "$@" >"$log" 2>&1; then
    grep -E "(error:|^error:|^error |FAILED)" "$log" | tail -20 >&2 || true
    echo "详见 $log" >&2
    return 1
  fi
}
run_xcode "$stage/archive.log" -project nodeseek.xcodeproj -scheme nodeseek \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$PWD/.build/ShelfDerivedData" \
  -clonedSourcePackagesDirPath "$PWD/.build/SourcePackages" \
  -archivePath "$stage/nodeseek.xcarchive" -allowProvisioningUpdates \
  CRASHLYTICS_SKIP_BUILD_PHASE_UPLOAD=1 DEVELOPMENT_TEAM=Z9K94479DQ CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY='Apple Development' PROVISIONING_PROFILE_SPECIFIER= archive
python3 - "$stage/ExportOptions.plist" <<'PY'
import plistlib
import sys
with open(sys.argv[1], "wb") as f:
    plistlib.dump(dict(method="release-testing", destination="export",
                       signingStyle="manual", teamID="Z9K94479DQ",
                       signingCertificate="Apple Distribution",
                       provisioningProfiles={bid: "Shelf Ad Hoc " + bid for bid in
                           ("com.mistj.nodeseek", "com.mistj.nodeseek.ProbeWidget")},
                       manageAppVersionAndBuildNumber=False), f)
PY
run_xcode "$stage/export.log" -exportArchive -archivePath "$stage/nodeseek.xcarchive" \
  -exportPath "$stage/export" -exportOptionsPlist "$stage/ExportOptions.plist"
shopt -s nullglob
ipas=("$stage"/export/*.ipa)
if [[ ${#ipas[@]} != 1 ]]; then
  echo "导出目录中应有一个 IPA：$stage/export" >&2
  exit 1
fi
publish upload "${ipas[0]}" --branch "$branch" --commit "$commit"
