# Godot Testing

This project uses a small Godot-native GDScript test runner instead of an external addon. It runs headlessly with the same Godot executable used by the project, so there is no package install step for agents, local development, or CI.

## Configure Godot

Set `GODOT` to the Godot 4.7.1 executable when `godot` is not already on `PATH`.

PowerShell:

```powershell
$env:GODOT = "C:\Path\To\Godot_v4.7.1-stable_win64.exe"
```

macOS or Linux:

```bash
export GODOT="/path/to/godot"
```

On macOS, the executable inside the app bundle is usually:

```bash
export GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
```

## Run Tests

PowerShell:

```powershell
.\tools\run_godot_tests.ps1
```

macOS or Linux:

```bash
./tools/run_godot_tests.sh
```

The wrapper scripts can be run from the project root or from inside `tools/`; they resolve the Godot project path automatically.

Direct Godot command:

```bash
$GODOT --headless --path . --script res://tests/test_runner.gd
```

Run the direct command from the project root. If `godot` is on `PATH`, replace `$GODOT` with `godot`.

## Write Tests

Add test scripts under `tests/unit/` with filenames ending in `_test.gd`.

The runner awaits test methods, so synchronous and asynchronous tests are supported.

Each test script must:

- extend `"res://tests/test_case.gd"`
- use typed GDScript
- define one or more zero-argument methods named `test_*`

Example:

```gdscript
extends "res://tests/test_case.gd"

func test_example() -> void:
	var value := 2 + 2

	assert_eq(value, 4)
```

Optional `before_each()` and `after_each()` methods run around every test method in a test script.

Available assertions:

- `assert_true(value, message)`
- `assert_false(value, message)`
- `assert_eq(actual, expected, message)`
- `assert_ne(actual, expected, message)`
- `assert_null(value, message)`
- `assert_not_null(value, message)`

## Current Coverage

The unit suite (`tests/unit`, about 60 scripts) covers inventory, items, NPC profile payloads, dialog pagination/typewriter/backend helpers, the actor state machine and the NPC cognition stack: decision tickets, service and policy, evidence inbox and appraisal, knowledge, commitments, the brain and task controller, goal selection, memory admission and retrieval, saves, migration and legacy fixtures (`npc_save_migration_test`, `npc_legacy_fixture_test`).

`ARCADIA_TEST_FILTER=<substring>` limits a run to unit scripts whose path contains the substring (for example `ARCADIA_TEST_FILTER=npc_brain ./tools/run_godot_tests.sh`). The runner points `NpcCognition` at a temporary save and an unreachable backend (`127.0.0.1:1`), so unit tests never touch the player's save or a provider.

Put small reusable test doubles in `tests/fixtures/`. Prefer pure `Resource`, `RefCounted`, and helper-method tests before adding scene-level tests that depend on physics, rendering, autoloads, or backend services.

## Integration Scripts

Scene- and world-level checks live in `tests/integration/` and are not discovered by the unit runner. Each is a `SceneTree` script run directly, from the project root:

```bash
$GODOT --headless --path . --fixed-fps 60 --script res://tests/integration/<name>.gd
```

They exit non-zero on failure. Several need the locally installed licensed world assets or `GODOT` and skip otherwise (for example the full-world town scenarios); `pixel_camera_test` should also be run without `--headless` to check rendering. The town and navigation scripts (`town_life_world_test`, `town_traffic_test`, `town_interiors_test`, `actor_contacts_test`, `actor_navigation_test`) are described in [Town life](town_life.md#validation). The cognition scripts are:

| Script | Purpose |
| --- | --- |
| `npc_cognition_scenarios_test` | Save isolation, reload stability, no information without evidence, routine goal choice, sleepers, safety sessions, reload mid-travel and player takeover |
| `npc_cognition_matrix_test` | Acceptance-matrix rows 7, 13, 14, 15, 19 and 20 of the cognition plan end to end |
| `npc_cognition_soak_test` | A long simulated run checking save size growth and bounded queues and counters |
| `npc_runtime_smoke_test` | The autoload, scene and save boundary start together and run briefly |
| `npc_memory_http_test` | A real HTTP exchange with the in-process mock server (`/v2/dialogue/chat`, v2 judgments, `/v2/dialogue/say`) |
| `npc_reset_world_test` | The explicit world reset tool and its backup |

Scenarios build on `tests/fixtures/npc_simulation_fixture.gd` and `npc_fake_decision_service.gd`; legacy save shapes are in `tests/fixtures/cognition/` and the server contract examples in `tests/fixtures/cognition_contract/`.

## Cognition Checks

`tools/run_npc_cognition_checks.sh` (`tools/run_npc_cognition_checks.ps1` on Windows) runs, in one command, the full unit runner, the town/actor integration scripts above plus the cognition matrix, soak and runtime smoke scripts, and the backend suite (which includes the mocked evaluator run). Use it after changing anything under `game/actors/npcs/cognition/`, `game/actors/npcs/tasks/`, `NpcCognition`, `TownLife` or the server routes. The soak script alone takes about five minutes.

Backend pieces can also run alone:

```bash
cd tools/server && npm test
npm --prefix tools/server run evaluate -- --mock
```

`evaluate -- --mock` is the offline labeled-case evaluation: a deterministic fake answers each case and every request is validated by the real route contract. The live evaluation (`--live --limit N --yes`) spends provider requests and is opt-in only; see [the server README](../tools/server/README.md#provider-evaluation). The recipe for adding a behavior and its tests is in [the cognition architecture](npc_cognition_architecture.md#recipe-add-a-goal-or-task).

## Agent Validation

Agents should run tests after changing gameplay, UI, Resources, scenes, autoloads, or input behavior:

```bash
$GODOT --headless --path . --script res://tests/test_runner.gd
```

For changed `.gd` files, also run Godot's script check when supported:

```bash
$GODOT --headless --path . --script res://path/to/changed_script.gd --check-only
```

After scene, resource, actor, input, or autoload changes, run a short smoke test:

```bash
$GODOT --headless --path . --quit-after 2
```
