#!/bin/bash
set -euo pipefail
TASK_ROUTER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$TASK_ROUTER_ROOT/dist"
python3 - "$TASK_ROUTER_ROOT" <<'PY'
from pathlib import Path
import sys, zipfile
root = Path(sys.argv[1])
with zipfile.ZipFile(root / 'dist/AI-Model-Picker-V0.4-source.zip', 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    files = [root / name for name in ['README.md','README.zh-CN.md','PRIVACY.md','CHANGELOG.md','V0.4_实现说明.md','API参考价_来源说明.md','THIRD_PARTY.md','LICENSE','.gitignore','CONTRIBUTING.md','SECURITY.md']]
    for directory in ['Sources','Resources','Tests','scripts','docs','examples','.github']:
        files += sorted(p for p in (root / directory).rglob('*') if p.is_file() and p.name != '.DS_Store')
    for path in files:
        archive.write(path, 'AI-Model-Picker/' + path.relative_to(root).as_posix())
print(root / 'dist/AI-Model-Picker-V0.4-source.zip')
PY
