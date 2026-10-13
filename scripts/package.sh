#!/bin/bash
set -euo pipefail
TASK_ROUTER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_ROUTER_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/TaskRouterPackage.XXXXXX")"
trap 'rm -rf "$TASK_ROUTER_STAGE"' EXIT
TASK_ROUTER_APP="$TASK_ROUTER_ROOT/dist/AI选模助手.app"
TASK_ROUTER_IMAGE="$TASK_ROUTER_ROOT/dist/AI选模助手_V0.4.1_内测.dmg"
[[ -d "$TASK_ROUTER_APP" ]] || { echo "请先运行 scripts/build.sh" >&2; exit 1; }
python3 - "$TASK_ROUTER_STAGE" "$TASK_ROUTER_APP" "$TASK_ROUTER_ROOT" <<'PY'
from pathlib import Path
import sys, shutil
stage, app, root = map(Path, sys.argv[1:])
if not stage.name.startswith('TaskRouterPackage.'):
    raise SystemExit('非法打包目录')
# Copy bytes and mode bits, not iCloud/Finder decoration metadata.
def clean_copy(src, dst):
    shutil.copyfile(src, dst)
    shutil.copymode(src, dst)
    return dst
shutil.copytree(app, stage / app.name, copy_function=clean_copy)
shutil.copyfile(root / 'Resources/DefaultRules.md', stage / 'DefaultRules.md')
shutil.copyfile(root / 'README.zh-CN.md', stage / '使用说明.md')
shutil.copytree(root / 'docs', stage / 'docs', copy_function=clean_copy)
shutil.copyfile(root / 'README.md', stage / 'README.md')
shutil.copyfile(root / 'README.zh-CN.md', stage / 'README.zh-CN.md')
shutil.copyfile(root / 'PRIVACY.md', stage / 'PRIVACY.md')
shutil.copyfile(root / 'SECURITY.md', stage / 'SECURITY.md')
shutil.copyfile(root / 'CONTRIBUTING.md', stage / 'CONTRIBUTING.md')
shutil.copytree(root / 'Resources', stage / 'Resources', copy_function=clean_copy)
shutil.copyfile(root / 'Resources/DefaultRules.en.md', stage / 'DefaultRules.en.md')
shutil.copyfile(root / 'Resources/APIPrices.json', stage / 'APIPrices.json')
shutil.copyfile(root / 'API参考价_来源说明.md', stage / 'API参考价_来源说明.md')
shutil.copyfile(root / 'THIRD_PARTY.md', stage / 'THIRD_PARTY.md')
shutil.copyfile(root / 'LICENSE', stage / 'LICENSE')
(stage / 'Applications').symlink_to('/Applications')
PY
xattr -r -d com.apple.FinderInfo "$TASK_ROUTER_STAGE/AI选模助手.app" 2>/dev/null || true
xattr -r -d com.apple.ResourceFork "$TASK_ROUTER_STAGE/AI选模助手.app" 2>/dev/null || true
codesign --verify --deep --strict "$TASK_ROUTER_STAGE/AI选模助手.app"
hdiutil create -volname "AI选模助手 V0.4.1 内测" -srcfolder "$TASK_ROUTER_STAGE" -ov -format UDZO "$TASK_ROUTER_IMAGE"
hdiutil verify "$TASK_ROUTER_IMAGE"
shasum -a 256 "$TASK_ROUTER_IMAGE" > "$TASK_ROUTER_ROOT/dist/SHA256.txt"
printf '%s\n' "$TASK_ROUTER_IMAGE"
