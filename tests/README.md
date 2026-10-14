# Tests

Validation and test scripts live here.

Use this folder for permanent Godot tests and temporary validation scripts that load scenes, exercise resource behavior, or check gameplay systems. Temporary scripts should be removed after the validation run unless they are useful as repeatable tests.

## Test Runner

Run all committed tests with:

```powershell
.\tools\run_godot_tests.ps1
```

```bash
./tools/run_godot_tests.sh
```

The wrapper scripts resolve the project root automatically, so they also work when launched from the `tools/` directory.

The runner discovers `tests/unit/*_test.gd` recursively. Test scripts must extend `"res://tests/test_case.gd"` and expose zero-argument `test_*` methods.

Reusable test doubles live in `tests/fixtures/`. Prefer pure Resource, RefCounted, and helper-method tests before adding scene-level tests that require physics, rendering, autoloads, or backend services.

## Unit tests and integration scripts

`tests/unit/` holds the discovered unit tests; `ARCADIA_TEST_FILTER=<substring>` focuses the runner on matching paths. `tests/integration/` holds standalone `SceneTree` scripts for scene, world and HTTP checks (run with `--script res://tests/integration/<name>.gd`, `--fixed-fps 60` for physics scenarios); the unit runner does not execute them. Cognition scripts: `npc_cognition_scenarios_test`, `npc_cognition_matrix_test`, `npc_cognition_soak_test`, `npc_runtime_smoke_test`, `npc_memory_http_test`, `npc_reset_world_test`.

`tools/run_npc_cognition_checks.sh` (`.ps1` on Windows) runs the full unit runner, the 13 town/actor integration scripts plus `npc_cognition_matrix_test`, `npc_cognition_soak_test` and `npc_runtime_smoke_test`, and the backend tests (`npm test` in `tools/server`, which includes the mocked evaluator run in `test/cognition-evaluation.test.js`), then prints a summary table. The live evaluator is opt-in and spends provider requests.

Fixtures: `tests/fixtures/cognition/` (legacy save shapes), `tests/fixtures/cognition_contract/` (backend request/response examples), `npc_simulation_fixture.gd` and `npc_fake_decision_service.gd`.

See `docs/godot_testing.md` for setup, direct Godot commands, and assertion helpers, and `docs/npc_cognition_architecture.md` for the extension recipe.
