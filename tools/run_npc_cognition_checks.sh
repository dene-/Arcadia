#!/usr/bin/env bash
# Runs every NPC cognition check: the Godot unit runner, the fixed list of integration scripts and
# the backend tests (with GODOT exported so the Godot-driven server tests run instead of skipping).
# Every step runs even after a failure; a summary table follows and the exit status is non-zero
# when any step failed.
set -uo pipefail

GODOT_BIN="${GODOT:-godot}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAILURE_PATTERN="Godot tests failed|No Godot tests found|SCRIPT ERROR|Can't load script|Failed to load script"

INTEGRATION_TESTS=(
	town_emergency_flow_test
	npc_safety_world_test
	town_watch_test
	town_life_world_test
	town_interiors_test
	town_traffic_test
	actor_navigation_test
	actor_contacts_test
	combat_contact_test
	npc_combat_position_test
	pixel_camera_test
	npc_reset_world_test
	npc_cognition_scenarios_test
	npc_cognition_matrix_test
	npc_cognition_soak_test
	npc_runtime_smoke_test
)

STEP_NAMES=()
STEP_RESULTS=()
STEP_SECONDS=()
FAILED=0

record() {
	STEP_NAMES+=("$1")
	STEP_RESULTS+=("$2")
	STEP_SECONDS+=("$3")
	if [ "$2" != "PASS" ]; then
		FAILED=1
	fi
}

# run_godot <step name> <godot arguments...>: fails on a non-zero exit or a failure pattern.
run_godot() {
	local name="$1"
	shift
	local started=$SECONDS
	echo "==> $name"
	local output
	output="$("$GODOT_BIN" --headless --path "$PROJECT_ROOT" "$@" 2>&1)"
	local code=$?
	printf '%s\n' "$output"
	local result="PASS"
	if [ "$code" -ne 0 ]; then
		result="FAIL (exit $code)"
	elif printf '%s\n' "$output" | grep -E "$FAILURE_PATTERN" >/dev/null; then
		result="FAIL (error output)"
	fi
	record "$name" "$result" "$((SECONDS - started))"
}

run_godot "unit tests" --script res://tests/test_runner.gd

for test in "${INTEGRATION_TESTS[@]}"; do
	if [ ! -f "$PROJECT_ROOT/tests/integration/$test.gd" ]; then
		echo "==> $test"
		echo "Missing tests/integration/$test.gd"
		record "$test" "FAIL (missing)" 0
		continue
	fi
	run_godot "$test" --fixed-fps 60 --script "res://tests/integration/$test.gd"
done

echo "==> backend tests"
started=$SECONDS
GODOT="$GODOT_BIN" npm --prefix "$PROJECT_ROOT/tools/server" test
code=$?
if [ "$code" -eq 0 ]; then
	record "backend tests" "PASS" "$((SECONDS - started))"
else
	record "backend tests" "FAIL (exit $code)" "$((SECONDS - started))"
fi

echo
printf '%-32s %-20s %8s\n' "Step" "Result" "Seconds"
printf '%-32s %-20s %8s\n' "--------------------------------" "--------------------" "--------"
for index in "${!STEP_NAMES[@]}"; do
	printf '%-32s %-20s %8s\n' "${STEP_NAMES[$index]}" "${STEP_RESULTS[$index]}" "${STEP_SECONDS[$index]}"
done

if [ "$FAILED" -ne 0 ]; then
	echo "NPC cognition checks failed"
	exit 1
fi
echo "NPC cognition checks passed"
exit 0
