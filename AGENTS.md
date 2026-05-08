# Project Agent Guide

This Godot project targets Godot 4.6. Use typed GDScript for gameplay and UI work.

## Required Skill

When working with OpenAI Codex, always use the `godot-4-6-best-practices` skill before planning, implementing, refactoring, reviewing, documenting, or validating Godot project files.

For tools that do not support Codex skills, follow the same Godot 4.6 rules from this file and prefer the local skill reference at `.agents/skills/godot-4-6-best-practices/SKILL.md` when available.

## Validation

Use the `GODOT` environment variable when available:

```powershell
& ([Environment]::GetEnvironmentVariable('GODOT','User')) --headless --path . --script res://path/to/script.gd --check-only
& ([Environment]::GetEnvironmentVariable('GODOT','User')) --headless --path . --quit-after 2
```

Run script checks for changed `.gd` files and a short smoke test after scene, resource, actor, input, or autoload changes.

## Commit Messages

When creating commits, use Conventional Commit messages:

```text
<type>(<optional scope>): <description>
```

Examples:

```text
feat(inventory): add item drag and drop
fix(enemy-ai): prevent attacks while dead
docs: document project folder structure
chore: init
```

Allowed types:

- `feat`: add, adjust, or remove API/UI/gameplay features.
- `fix`: fix a bug from a previous feature.
- `refactor`: restructure code without changing behavior.
- `perf`: improve performance without changing behavior.
- `style`: formatting or code style only.
- `test`: add or correct tests.
- `docs`: documentation-only changes.
- `build`: build tools, dependencies, project version, or packaging.
- `ops`: CI/CD, deployment, infrastructure, backups, monitoring, or recovery.
- `chore`: repository maintenance such as initial commit or ignore files.

Rules:

- Use imperative, present tense descriptions: `add`, not `added` or `adds`.
- Do not capitalize the first description letter.
- Do not end the description with a period.
- Do not use issue identifiers as scopes.
- Use `!` before `:` for breaking changes, for example `feat(save)!: replace inventory save format`.
- Add `BREAKING CHANGE:` in the footer for breaking changes.
- Use default Git messages for merge and revert commits.

## Architecture Rules

- Keep reusable actor scene child names stable: `AnimatedSprite2D`, `HitBox`, `HitBox/CollisionShape2D`, `HurtBox`, and `StateMachine`.
- Put shared actor mechanics in `BaseActor`.
- Put player-only input, charge attack, and player tuning access in `BasePlayer`.
- Put NPC-only patrol, dialog source data, interaction, blood particles, and hurt knockback in `BaseNpc`.
- State scripts should call narrow actor methods instead of reading data resources directly.
- Input actions belong in `project.godot`, not runtime scripts.
- Dialog remains a narrow Autoload at `/root/DialogManager`; prefer adding helper classes under `game/ui/dialog/` over growing the manager directly.

See `docs/actor_dialog_development.md` for extension recipes.
