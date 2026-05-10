# Project Agent Guide

This Godot project targets Godot 4.6. Use typed GDScript for gameplay and UI work.

## Required Skill

When working with OpenAI Codex, always use the `godot-4-6-best-practices` skill before planning, implementing, refactoring, reviewing, documenting, or validating Godot project files.

For tools that do not support Codex skills, follow the same Godot 4.6 rules from this file and prefer the local skill reference at `.agents/skills/godot-4-6-best-practices/SKILL.md` when available.

## Validation

Use the `GODOT` environment variable when available:

```bash
$GODOT --headless --path . --script res://path/to/script.gd --check-only
$GODOT --headless --path . --script res://tests/test_runner.gd
$GODOT --headless --path . --quit-after 2
```

PowerShell agents can run `.\tools\run_godot_tests.ps1`. macOS and Linux agents can run `./tools/run_godot_tests.sh`. Run script checks for changed `.gd` files, the Godot test runner after gameplay/UI/resource changes, and a short smoke test after scene, resource, actor, input, or autoload changes.

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

## Branch and PR Workflow

- Before implementing any feature, fix, refactor, or other non-trivial change, create or switch to a dedicated branch. Do not implement new work directly on `master`.
- Before creating a new branch from `master`, always update local `master` from `origin/master` first and verify it is up to date.
- Use conventional branch names without tool-specific prefixes:
  - `feat/<short-kebab-description>`
  - `fix/<short-kebab-description>`
  - `refactor/<short-kebab-description>`
  - `docs/<short-kebab-description>`
  - `chore/<short-kebab-description>`
- Choose the branch type to match the expected commit type. Keep the description short, lowercase, and kebab-case.
- Commit and push only on the current feature branch unless explicitly instructed otherwise. Never force push unless explicitly requested.
- After each completed agent chat turn that changes repository files, commit the completed changes with the proper Conventional Commit message and push the current feature branch, unless the user explicitly asks not to, the work is blocked, or the changes are only a checkpoint the user has asked to keep uncommitted.
- Treat user approval phrases such as `feature is ready`, `looks good`, `ship it`, or `ready` as a request to finish the branch: review the diff, run the relevant validation, commit with the proper Conventional Commit message, push the feature branch, and create a PR targeting `master` unless the user explicitly says not to.
- When asked to create a PR or when finishing an approved branch, target `master`.
- Before creating a PR, review all changed code on the branch against `master`, improve anything that does not meet project practices, and run the relevant validation. Then create the PR with a concise title and summary of changes.
- After opening the PR, leave review and merge decisions to the user on GitHub.

## Architecture Rules

- Keep reusable actor scene child names stable: `AnimatedSprite2D`, `HitBox`, `HitBox/CollisionShape2D`, `HurtBox`, and `StateMachine`.
- Put shared actor mechanics in `BaseActor`.
- Put player-only input, charge attack, and player tuning access in `BasePlayer`.
- Put NPC-only patrol, dialog source data, interaction, blood particles, and hurt knockback in `BaseNpc`.
- State scripts should call narrow actor methods instead of reading data resources directly.
- Input actions belong in `project.godot`, not runtime scripts.
- Dialog remains a narrow Autoload at `/root/DialogManager`; prefer adding helper classes under `game/ui/dialog/` over growing the manager directly.

See `docs/actor_dialog_development.md` for extension recipes.
