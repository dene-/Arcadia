---
applyTo: "**/*.gd,**/*.tscn,**/*.tres,**/*.res,project.godot,.gitignore,.gitattributes,AGENTS.md"
---

# Godot 4.6 Instructions

Always treat this as a Godot 4.6 project.

When using OpenAI Codex, use the `godot-4-6-best-practices` skill for any Godot implementation, refactor, review, documentation, validation, or project-organization work. When using GitHub Copilot or another tool that cannot load Codex skills, follow the equivalent rules from `.agents/skills/godot-4-6-best-practices/SKILL.md` and the root `AGENTS.md`.

Use typed GDScript for gameplay and UI work. Do not introduce Godot 3.x APIs.

Preserve reusable actor child names:

- `AnimatedSprite2D`
- `HitBox`
- `HitBox/CollisionShape2D`
- `HurtBox`
- `StateMachine`

Keep responsibilities narrow:

- Put shared actor mechanics in `BaseActor`.
- Put player-only behavior in `BasePlayer`.
- Put NPC-only behavior in `BaseNpc`.
- Keep state scripts decoupled from data resources where a narrow actor method can be used.
- Keep input actions in `project.godot`.
- Keep dialog orchestration focused in `/root/DialogManager`; add helper classes under `game/ui/dialog/`.

Validate changed scripts with Godot `--check-only` and run a short headless smoke test after scene, resource, actor, input, or autoload changes.

When creating commits for Godot changes, use Conventional Commits:

```text
<type>(<optional scope>): <description>
```

Use one of `feat`, `fix`, `refactor`, `perf`, `style`, `test`, `docs`, `build`, `ops`, or `chore`. Keep descriptions imperative, present tense, lowercase at the start, and without a trailing period. Mark breaking changes with `!` before `:` and a `BREAKING CHANGE:` footer.
