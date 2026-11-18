#!/bin/sh
set -eu
# 仅归档时运行；兼容项目 Make 目标与 Xcode 默认的依赖目录。
for root in "${SOURCE_PACKAGES:-${SRCROOT}/.build/SourcePackages}" "${BUILD_DIR%/Build/*}/SourcePackages"; do
    runner="${root}/checkouts/firebase-ios-sdk/Crashlytics/run"
    if [ -f "$runner" ]; then
        exec "$runner"
    fi
done
echo "error: Firebase Crashlytics script not found. Resolve package dependencies before archiving." >&2
exit 1
