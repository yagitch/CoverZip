#!/bin/bash
# 呼出元のビルドだけにXcode・署名・アーキテクチャを指定する。
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
: "${COVERZIP_SIGN_IDENTITY:?本体と同じチームの署名証明書のSHA-1を指定してください}"
COVERZIP_TEAM_ID="${COVERZIP_TEAM_ID:-6KCX8JYZB7}"
xcrun --find swiftc >/dev/null
xcrun --find coremlcompiler >/dev/null
[ "$(uname -m)" = arm64 ] || { echo 'このビルド手順はpeterのarm64用です' >&2; exit 1; }

verify_plugin_team() {
    codesign --verify --deep --strict "$1"
    codesign -dv "$1" 2>&1 | awk -v team="$COVERZIP_TEAM_ID" '$0 == "TeamIdentifier=" team { found=1 } END { exit !found }'
}
