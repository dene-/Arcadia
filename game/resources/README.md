# Resources

Authored game data resources live here. These are project-owned `.tres` files and resource scripts, not raw imported art.

- `actors/`: player/NPC data, profiles, and enemy/human actor resources.
- `animation/`: `ActorSpriteFrames` resources that reference raw spritesheets from `res://assets/art/...`.
- `combat/`: combat layer presets and related combat configuration.
- `profiles/`: reserved for future profile-style data that is not tied to a single actor folder.

Prefer resources for tunable gameplay data so scenes can share behavior while varying numbers, animation sets, drops, and dialog metadata.
