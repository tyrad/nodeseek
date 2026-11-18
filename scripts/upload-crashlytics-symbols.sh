#!/bin/sh
set -eu
# CI 在归档完成后同步上传，避免后台进程和 Xcode 脚本沙盒影响归档。
if [ "${CRASHLYTICS_SKIP_BUILD_PHASE_UPLOAD:-0}" = "1" ]; then
    echo "Crashlytics symbols will be uploaded by the dedicated CI step."
    exit 0
fi
# 仅归档时运行；兼容项目 Make 目标与 Xcode 默认的依赖目录。
for root in "${SOURCE_PACKAGES:-${SRCROOT}/.build/SourcePackages}" "${BUILD_DIR%/Build/*}/SourcePackages"; do
    runner="${root}/checkouts/firebase-ios-sdk/Crashlytics/run"
    if [ -f "$runner" ]; then
        exec "$runner"
    fi
done
echo "error: Firebase Crashlytics script not found. Resolve package dependencies before archiving." >&2
exit 1
