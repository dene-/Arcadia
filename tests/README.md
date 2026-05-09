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

See `docs/godot_testing.md` for setup, direct Godot commands, and assertion helpers.
