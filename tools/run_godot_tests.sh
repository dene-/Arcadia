#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${GODOT:-godot}"

"$GODOT_BIN" --headless --path . --script res://tests/test_runner.gd
