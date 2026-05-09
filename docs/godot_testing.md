# Godot Testing

This project uses a small Godot-native GDScript test runner instead of an external addon. It runs headlessly with the same Godot executable used by the project, so there is no package install step for agents, local development, or CI.

## Configure Godot

Set `GODOT` to the Godot 4.6 executable when `godot` is not already on `PATH`.

PowerShell:

```powershell
$env:GODOT = "C:\Path\To\Godot_v4.6.2-stable_win64.exe"
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

Direct Godot command:

```bash
$GODOT --headless --path . --script res://tests/test_runner.gd
```

If `godot` is on `PATH`, replace `$GODOT` with `godot`.

## Write Tests

Add test scripts under `tests/unit/` with filenames ending in `_test.gd`.

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
