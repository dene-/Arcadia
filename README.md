# Test

Godot 4.6 project for a top-down pixel RPG prototype with actor state machines, NPC dialog, enemies, drops, inventory, and HUD UI.

## Run And Validate

Open the project with Godot 4.6. The main scene is:

```text
res://game/world/scenes/world.tscn
```

Set `GODOT` to the Godot 4.6 executable when `godot` is not already on `PATH`.

```powershell
$env:GODOT = "C:\Path\To\Godot_v4.6.2-stable_win64.exe"
.\tools\run_godot_tests.ps1
```

```bash
export GODOT="/path/to/godot"
./tools/run_godot_tests.sh
```

The test wrapper scripts can be run from the project root or from inside `tools/`.

Run script checks for changed `.gd` files and a short smoke test after scene, resource, actor, input, or autoload changes:

```bash
$GODOT --headless --path . --script res://path/to/script.gd --check-only
$GODOT --headless --path . --quit-after 2
```

See `docs/godot_testing.md` for test authoring and agent validation steps.

## Folder Map

- `game/`: game-authored scenes, scripts, and gameplay resources.
- `assets/`: imported raw art and audio assets.
- `addons/`: Godot editor/runtime addons.
- `docs/`: long-form development notes.
- `tests/`: validation and test scripts.
- `tools/`: non-exported development tools, including the local dialog server.
- `AGENTS.md`: agent-facing architecture and validation rules.
