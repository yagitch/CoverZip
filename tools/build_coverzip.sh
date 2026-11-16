#!/bin/bash
# 通常の更新はこの入口を使い、ビルド出力を未整理の.appとして残さない。
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+$ ]]; then
    echo "使い方: bash tools/build_coverzip.sh <ビルド番号>" >&2
    exit 2
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cleanup_failed_update() {
    local result=$?
    trap - EXIT
    if [[ $result -ne 0 ]]; then
        python3 tools/app_install.py --apply || true
    fi
    exit "$result"
}
trap cleanup_failed_update EXIT
xcodebuild -project CoverZip.xcodeproj -scheme CoverZip -configuration Release \
    -derivedDataPath .build-local build DEVELOPMENT_TEAM=6KCX8JYZB7 \
    CODE_SIGN_STYLE=Manual 'CODE_SIGN_IDENTITY=Apple Development' \
    PROVISIONING_PROFILE_SPECIFIER= REGISTER_APP_GROUPS=NO CURRENT_PROJECT_VERSION="$1"
python3 tools/app_install.py --install-from .build-local/Build/Products/Release/CoverZip.app --apply
