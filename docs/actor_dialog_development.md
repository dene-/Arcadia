# Actor And Dialog Development Guide

This guide describes the current actor and dialog architecture for developers and AI agents. The goal is to make new features fit the existing project without turning `BasePlayer`, `BaseNpc`, or `DialogManager` into broad managers.

## Core Structure

`BaseActor` is the shared root for actor scenes that use combat areas, animation, and a state machine.

Shared actor scene contract:

- Root node extends `BaseActor` through a child class such as `BasePlayer` or `BaseNpc`.
- Required children:
  - `CollisionShape2D` (physical feet, separate from combat areas)
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
- rounded body setup, navigation registration cleanup and wall-aware single-hit melee contact

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

## Enemy Attack Positioning

`BaseNpc` treats `soft_collision_distance` as an approach preference. Enemies can attack
closer opponents without backing away to restore that spacing. Shared pursuit aims inside
weapon range while allowing body clearance, and the run state checks attack readiness
after moving so a running target cannot escape the check on every physics tick.

In generated worlds, `NpcPursuit` follows the shared `ActorRoute` to a leased attack approach.
`ActorCrowd` handles nearby bodies independently of combat intent or daily activity.
Static world geometry is layer 1, moving bodies layer 2; hit/hurt areas retain their resource
settings. `attack_connected` fires only when a receiver accepts a contact for that swing.
Outgoing areas remain monitorable; the weapon's collision shape activates only during a
swing. This prevents late contact notifications caused by toggling area monitorability.
See [town movement](town_life.md#routine-and-movement) for ownership and performance diagnostics.

Run `tests/integration/npc_combat_position_test.gd` headlessly with `--fixed-fps 60` to check
real enemy movement and attack transitions from both sides, close range, misalignment,
and spacing beyond weapon reach. This scenario uses no dialogue providers or saved NPCs.
`tests/integration/combat_contact_test.gd` additionally checks actual damage in both
directions, advancing player swings, pursuit of a running player, and wall-blocked strikes.
Run it at 30, 60 and 120 physics ticks using matching `--fixed-fps` and `-- <tick rate>`.

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

- `NpcConversation`: Jev decisions, context construction and successful exchange commits
- `NpcCognition`: shared cognition service, independent of dialogue presentation
- `NpcEventProcessor`: bounded background assessment and separate speech generation
- `WorldEvents` / `NpcPerceptionRouter`: world facts and extensible perception adapters
- `NpcWorldSave`: atomic named-NPC deaths and memory persistence
- `NpcPerception`: sight, hearing and self-injury evidence for NPC observers
- `NpcMemoryStore`: save-owned memory, relationships, recent dialogue and observed events
- `NpcMemoryRetriever`: relevant memory selection and filtered recall
- `DialogBackendClient`: HTTP request and response parsing
- `DialogPaginator`: text pagination
- `DialogTypewriter`: text reveal timing
- `DialogVoicePlayer`: generated voice ticks

Dialog source contract:

- `get_npc_profile() -> NpcProfile`
- `get_cognitive_context() -> Dictionary`
- `get_backend_profile() -> Dictionary` (identity/knowledge only)
- `get_dialog_text() -> String`
- `is_able_to_chat() -> bool`

`BaseNpc` implements this contract from `NpcData` and `NpcProfile`.

See [NPC memory](npc_memory.md) for memory authoring, belief boundaries and persistence.
See [NPC perception](npc_perception.md) for combat observations, relationship effects and speech bubbles.

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
