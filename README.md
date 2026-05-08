# Test

Godot 4.6 project for a top-down pixel RPG prototype with actor state machines, NPC dialog, enemies, drops, inventory, and HUD UI.

## Run And Validate

Open the project with Godot 4.6. The main scene is:

```text
res://game/world/scenes/world.tscn
```

Use the `GODOT` user environment variable when available:

```powershell
& ([Environment]::GetEnvironmentVariable('GODOT','User')) --headless --path . --script res://path/to/script.gd --check-only
& ([Environment]::GetEnvironmentVariable('GODOT','User')) --headless --path . --quit-after 2
```

Run script checks for changed `.gd` files and a short smoke test after scene, resource, actor, input, or autoload changes.

## Folder Map

- `game/`: game-authored scenes, scripts, and gameplay resources.
- `assets/`: imported raw art and audio assets.
- `addons/`: Godot editor/runtime addons.
- `docs/`: long-form development notes.
- `tests/`: validation and test scripts.
- `tools/`: non-exported development tools, including the local dialog server.
- `AGENTS.md`: agent-facing architecture and validation rules.
