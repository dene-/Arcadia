#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${GODOT:-godot}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

"$GODOT_BIN" --headless --path "$PROJECT_ROOT" --script res://tests/test_runner.gd
