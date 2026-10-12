#!/bin/bash
set -euo pipefail
TASK_ROUTER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$TASK_ROUTER_ROOT/.build"
swiftc -parse-as-library "$TASK_ROUTER_ROOT/Sources/Localization.swift" "$TASK_ROUTER_ROOT/Sources/Prices.swift" "$TASK_ROUTER_ROOT/Sources/Updates.swift" "$TASK_ROUTER_ROOT/Sources/DataTable.swift" "$TASK_ROUTER_ROOT/Sources/Shortcuts.swift" "$TASK_ROUTER_ROOT/Sources/TextInput.swift" "$TASK_ROUTER_ROOT/Sources/Offline.swift" "$TASK_ROUTER_ROOT/Sources/Rules.swift" "$TASK_ROUTER_ROOT/Sources/Routing.swift" \
  "$TASK_ROUTER_ROOT/Sources/Services.swift" "$TASK_ROUTER_ROOT/Sources/Desktop.swift" "$TASK_ROUTER_ROOT/Tests/CoreTests.swift" \
  -o "$TASK_ROUTER_ROOT/.build/CoreTests" -framework AppKit -framework Carbon -framework Security -framework ApplicationServices
"$TASK_ROUTER_ROOT/.build/CoreTests" "$TASK_ROUTER_ROOT/Resources/DefaultRules.md"
