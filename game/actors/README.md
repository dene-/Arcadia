# Actors

Reusable actor scenes and scripts live here. `BaseActor` owns shared combat, animation, health, and state-machine behavior. `BasePlayer` and `BaseNpc` add player-only and NPC-only behavior.

Keep these reusable child node names stable:

- `AnimatedSprite2D`
- `HitBox`
- `HitBox/CollisionShape2D`
- `HurtBox`
- `StateMachine`

Use `states/` for shared state-machine code, `player/states/` for player state scripts, and `npcs/states/` for NPC/enemy state scripts. State scripts should call narrow actor methods instead of reaching directly into actor data resources.
