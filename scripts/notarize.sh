#!/bin/bash
# Only run after explicitly configuring a Developer ID and an Apple notary profile.
# This script uploads the signed package to Apple's notarization service.
set -euo pipefail
: "${TASKROUTER_SIGN_IDENTITY:?请先配置 Developer ID Application 签名身份}"
: "${TASKROUTER_NOTARY_PROFILE:?请先在钥匙串配置 Apple 公证 profile}"
TASK_ROUTER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$TASK_ROUTER_ROOT/scripts/build.sh"
TASK_ROUTER_ZIP="$TASK_ROUTER_ROOT/.build/TaskRouter-notarize.zip"
ditto -c -k --keepParent "$TASK_ROUTER_ROOT/dist/AI选模助手.app" "$TASK_ROUTER_ZIP"
xcrun notarytool submit "$TASK_ROUTER_ZIP" --keychain-profile "$TASKROUTER_NOTARY_PROFILE" --wait
xcrun stapler staple "$TASK_ROUTER_ROOT/dist/AI选模助手.app"
codesign --verify --deep --strict "$TASK_ROUTER_ROOT/dist/AI选模助手.app"
bash "$TASK_ROUTER_ROOT/scripts/package.sh"
TASK_ROUTER_IMAGE="$TASK_ROUTER_ROOT/dist/AI选模助手_V0.4_内测.dmg"
codesign --force --timestamp --sign "$TASKROUTER_SIGN_IDENTITY" "$TASK_ROUTER_IMAGE"
xcrun notarytool submit "$TASK_ROUTER_IMAGE" --keychain-profile "$TASKROUTER_NOTARY_PROFILE" --wait
xcrun stapler staple "$TASK_ROUTER_IMAGE"
shasum -a 256 "$TASK_ROUTER_IMAGE" > "$TASK_ROUTER_ROOT/dist/SHA256.txt"
echo "签名与公证完成；发布前仍需另一台 Mac 验收。"
