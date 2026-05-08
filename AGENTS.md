# Project Agent Guide

This Godot project targets Godot 4.6. Use typed GDScript for gameplay and UI work.

## Validation

Use the `GODOT` environment variable when available:

```powershell
& ([Environment]::GetEnvironmentVariable('GODOT','User')) --headless --path . --script res://path/to/script.gd --check-only
& ([Environment]::GetEnvironmentVariable('GODOT','User')) --headless --path . --quit-after 2
```

Run script checks for changed `.gd` files and a short smoke test after scene, resource, actor, input, or autoload changes.

## Architecture Rules

- Keep reusable actor scene child names stable: `AnimatedSprite2D`, `HitBox`, `HitBox/CollisionShape2D`, `HurtBox`, and `StateMachine`.
- Put shared actor mechanics in `BaseActor`.
- Put player-only input, charge attack, and player tuning access in `BasePlayer`.
- Put NPC-only patrol, dialog source data, interaction, blood particles, and hurt knockback in `BaseNpc`.
- State scripts should call narrow actor methods instead of reading data resources directly.
- Input actions belong in `project.godot`, not runtime scripts.
- Dialog remains a narrow Autoload at `/root/DialogManager`; prefer adding helper classes under `game/ui/dialog/` over growing the manager directly.

See `docs/actor_dialog_development.md` for extension recipes.
