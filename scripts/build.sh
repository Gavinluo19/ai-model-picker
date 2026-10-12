#!/bin/bash
set -euo pipefail
TASK_ROUTER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_ROUTER_BUILD="$TASK_ROUTER_ROOT/.build"
TASK_ROUTER_APP="$TASK_ROUTER_ROOT/dist/AI选模助手.app"
TASK_ROUTER_SDK="$(xcrun --show-sdk-path)"
mkdir -p "$TASK_ROUTER_BUILD" "$TASK_ROUTER_APP/Contents/MacOS" "$TASK_ROUTER_APP/Contents/Resources"
cp -X "$TASK_ROUTER_ROOT/Resources/DefaultRules.md" "$TASK_ROUTER_APP/Contents/Resources/DefaultRules.md"
cp -X "$TASK_ROUTER_ROOT/Resources/DefaultRules.en.md" "$TASK_ROUTER_APP/Contents/Resources/DefaultRules.en.md"
cp -X "$TASK_ROUTER_ROOT/Resources/ModelCatalog.json" "$TASK_ROUTER_APP/Contents/Resources/"
cp -X "$TASK_ROUTER_ROOT/Resources/APIPrices.json" "$TASK_ROUTER_ROOT/Resources/AppIcon.icns" "$TASK_ROUTER_APP/Contents/Resources/"
for TASK_ROUTER_ARCH in arm64 x86_64; do
  xcrun swiftc -O -parse-as-library -sdk "$TASK_ROUTER_SDK" -target "$TASK_ROUTER_ARCH-apple-macosx13.0" \
    "$TASK_ROUTER_ROOT"/Sources/*.swift -o "$TASK_ROUTER_BUILD/TaskRouter-$TASK_ROUTER_ARCH" \
    -framework AppKit -framework Carbon -framework Security -framework ApplicationServices
done
lipo -create "$TASK_ROUTER_BUILD/TaskRouter-arm64" "$TASK_ROUTER_BUILD/TaskRouter-x86_64" -output "$TASK_ROUTER_APP/Contents/MacOS/TaskRouter"
cp -X "$TASK_ROUTER_ROOT/Resources/Info.plist" "$TASK_ROUTER_APP/Contents/Info.plist"
# Remove Finder decoration metadata on this generated bundle only (not quarantine).
xattr -r -d com.apple.FinderInfo "$TASK_ROUTER_APP" 2>/dev/null || true
xattr -r -d com.apple.ResourceFork "$TASK_ROUTER_APP" 2>/dev/null || true
if [[ -n "${TASKROUTER_SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$TASKROUTER_SIGN_IDENTITY" "$TASK_ROUTER_APP"
else
  codesign --force --sign - "$TASK_ROUTER_APP"
fi
codesign --verify --deep --strict "$TASK_ROUTER_APP"
printf '%s\n' "$TASK_ROUTER_APP"
