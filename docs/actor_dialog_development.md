# Actor And Dialog Development Guide

This guide describes the current actor and dialog architecture for developers and AI agents. The goal is to make new features fit the existing project without turning `BasePlayer`, `BaseNpc`, or `DialogManager` into broad managers.

## Core Structure

`BaseActor` is the shared root for actor scenes that use combat areas, animation, and a state machine.

Shared actor scene contract:

- Root node extends `BaseActor` through a child class such as `BasePlayer` or `BaseNpc`.
- Required children:
  - `AnimatedSprite2D`
  - `HitBox`
  - `HitBox/CollisionShape2D`
  - `HurtBox`
  - `StateMachine`
- Optional NPC-only children:
  - `InteractionArea`
  - `BloodParticles`

`BaseActor` owns:

- `state_changed`, `attack_connected`, `hurtbox_triggered`, and `died` signals
- `facing` and `health`
- shared sprite frame setup
- hitbox and hurtbox collision layer setup
- hitbox metadata (`owner`, `damage`)
- animation playback and sprite flipping
- common hitbox/hurtbox signal handling

`BasePlayer` owns:

- player data setup
- movement input reads
- attack hold and charged attack behavior
- player-specific speed helpers
- dialog lock behavior

`BaseNpc` owns:

- NPC data setup
- patrol and roam decisions
- interaction prompt behavior
- dialog backend profile methods
- hurt knockback and blood particles
- NPC-specific animation fallback from `run` to `walk`

## Adding A New NPC

Use data and resources before adding new code.

1. Create or duplicate an `NpcProfile` resource under `game/resources/actors/humans/`.
2. Create or duplicate an `NpcData` resource under `game/resources/actors/humans/`.
3. Assign:
   - `profile`
   - `sprite_frames`
   - `combat_layers`
   - movement, combat, interaction, and dialog flags
4. Instance `game/actors/npcs/base_npc.tscn` in the world.
5. Assign the new `NpcData` resource on the instance.

Add a new NPC script only when the NPC needs behavior that cannot be expressed through `NpcData`, state scripts, or existing resources.

Good extension points:

- Add new NPC states under `game/actors/npcs/states/` when behavior is stateful.
- Add fields to `NpcData` when the feature is tunable per NPC.
- Override methods in a derived NPC scene only for behavior unique to that NPC type.

Avoid:

- Hard-coding NPC names or jobs inside `BaseNpc`.
- Adding one-off behavior branches to `BaseNpc` for a single NPC.
- Having state scripts read `npc_data` directly unless the value is truly state-specific and no narrow NPC method exists yet.

## Adding Player Types Or Races

For player variants such as race, class, or character differences, prefer data and inherited scenes.

Recommended path:

1. Create a new `PlayerData` resource or a derived resource if new exported fields are needed.
2. Assign different:
   - `sprite_frames`
   - movement speeds
   - attack damage
   - charge settings
   - combat layers
3. Use an inherited `base_player.tscn` scene when the variant needs different child nodes or visuals.
4. Add narrow methods to `BasePlayer` for state scripts to call.

Examples of narrow player methods:

- `current_move_speed()`
- `current_walk_animation_speed()`
- `is_jump_just_pressed()`
- `set_charged_attack_damage()`

If a feature only changes numbers, put it in `PlayerData`. If it changes scene composition, use an inherited scene. If it changes behavior across states, add a small method to `BasePlayer` and keep state scripts decoupled from the data resource.

Avoid:

- Reading `player_data` directly from state scripts.
- Creating separate player state scripts for every race unless the behavior truly differs.
- Adding runtime `InputMap` setup to actor scripts.

## Adding Actor Combat Features

Use `BaseActor` for shared combat-area mechanics only.

Add to `BaseActor` when all actor types should share the behavior:

- hitbox metadata conventions
- hurtbox filtering
- animation playback mechanics
- collision layer setup

Keep in `BasePlayer` or `BaseNpc` when behavior differs:

- player damage overrides
- NPC hurt knockback
- death transition timing
- blood particle visuals

For new damage rules, prefer adding a focused method or resource rather than broad conditionals. For example, a future `DamagePolicy` resource can be assigned from actor data if damage calculation becomes more complex.

## Input Actions

Player input actions are configured in `project.godot` under `[input]`.

Current actions:

- `player_left`
- `player_right`
- `player_up`
- `player_down`
- `player_attack`
- `player_interact`
- `player_jump`
- `player_run`

Scripts may read actions, but they should not create, remove, or mutate `InputMap` actions at runtime.

When adding a new input:

1. Add it in Project Settings > Input Map, or edit `project.godot`.
2. Add a named constant or narrow method on the owning actor script.
3. Have states call the owning actor method.

## Dialog Architecture

`DialogManager` is an Autoload scene at `/root/DialogManager`.

It owns dialog session flow:

- opening and closing dialog
- binding the current scene UI nodes
- requesting backend/fallback dialog text
- paginating text
- typewriter reveal
- voice character ticks
- reply buttons and free chat input

Helper classes:

- `DialogBackendClient`: HTTP request and response parsing
- `DialogPaginator`: text pagination
- `DialogTypewriter`: text reveal timing
- `DialogVoicePlayer`: generated voice ticks

Dialog source contract:

- `get_backend_profile() -> Dictionary`
- `get_dialog_text() -> String`
- `is_able_to_chat() -> bool`

`BaseNpc` implements this contract from `NpcData` and `NpcProfile`.

When adding dialog features:

- Add backend request/parse behavior to `DialogBackendClient`.
- Add pagination behavior to `DialogPaginator`.
- Add reveal behavior to `DialogTypewriter`.
- Add sound behavior to `DialogVoicePlayer`.
- Keep `DialogManager` focused on orchestration and UI state.

Avoid:

- Adding backend parsing directly to `DialogManager`.
- Having NPC state scripts know about dialog UI nodes.
- Adding broad dictionary payloads where a typed method or resource would be clearer.

## Sprite Animation Resources

Use `ActorSpriteFrames` and `ActorAnimationClip` for both player and NPC animations.

`ActorSpriteFrames` exports:

- `frame_size`
- `clips: Array[ActorAnimationClip]`

Each `ActorAnimationClip` defines:

- animation name
- sprite path
- frame duration
- source row and column range
- whether the source art faces right
- loop setting

Do not add player-specific or NPC-specific SpriteFrames builder scripts unless their building logic actually differs.

## Validation Checklist

After actor, NPC, player, input, resource, or dialog changes:

1. Run `--check-only` for changed scripts.
2. Run `--headless --path . --quit-after 2`.
3. For resource changes, open or load scenes that reference those resources.
4. Search for stale script paths after deleting or renaming scripts.

Common searches:

```powershell
Get-ChildItem -Recurse -File -Include *.gd,*.tres,*.tscn | Select-String -Pattern 'OldClassName|old_script.gd'
Get-ChildItem -Recurse -File -Include *.gd | Select-String -Pattern 'InputMap|player_data|npc_data'
```
