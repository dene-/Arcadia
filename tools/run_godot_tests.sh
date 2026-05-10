#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${GODOT:-godot}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

set +e
OUTPUT="$("$GODOT_BIN" --headless --path "$PROJECT_ROOT" --script res://tests/test_runner.gd 2>&1)"
GODOT_EXIT_CODE=$?
set -e

printf '%s\n' "$OUTPUT"

if [ "$GODOT_EXIT_CODE" -ne 0 ]; then
	exit "$GODOT_EXIT_CODE"
fi

if printf '%s\n' "$OUTPUT" | grep -E "Godot tests failed|No Godot tests found|SCRIPT ERROR|Can't load script|Failed to load script" >/dev/null; then
	exit 1
fi

exit 0
