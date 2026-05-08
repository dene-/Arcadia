# Copilot Repository Instructions

This is a Godot 4.6 project. Follow the root `AGENTS.md` as the main project guide.

For Godot work, always apply the Godot 4.6 practices from `.agents/skills/godot-4-6-best-practices/SKILL.md` when that file is available. Use typed GDScript for gameplay and UI work.

Keep changes scoped and preserve project architecture:

- Shared actor mechanics belong in `BaseActor`.
- Player-only input, charge attack, and player tuning access belong in `BasePlayer`.
- NPC-only patrol, dialog source data, interaction, blood particles, and hurt knockback belong in `BaseNpc`.
- State scripts should call narrow actor methods instead of reading data resources directly.
- Input actions belong in `project.godot`, not runtime scripts.
- Dialog remains a narrow Autoload at `/root/DialogManager`; add helpers under `game/ui/dialog/` instead of growing the manager broadly.

Validation:

```powershell
& ([Environment]::GetEnvironmentVariable('GODOT','User')) --headless --path . --script res://path/to/script.gd --check-only
& ([Environment]::GetEnvironmentVariable('GODOT','User')) --headless --path . --quit-after 2
```

Run script checks for changed `.gd` files and a short smoke test after scene, resource, actor, input, or autoload changes.

Commit messages must use Conventional Commits:

```text
<type>(<optional scope>): <description>
```

Use one of `feat`, `fix`, `refactor`, `perf`, `style`, `test`, `docs`, `build`, `ops`, or `chore`. Use imperative present tense, lowercase the first description letter, and do not end the description with a period. Use `!` before `:` and a `BREAKING CHANGE:` footer for breaking changes. Use default Git merge and revert messages.
