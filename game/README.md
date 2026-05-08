# Game

Game-authored runtime content lives here: gameplay scripts, scenes, UI, world scenes, item systems, and authored resources.

Use `res://game/...` for project code and game data. Keep raw third-party art in `res://assets/...` and reference it from authored resources instead of moving raw packs into this folder.

Primary areas:

- `actors/`: reusable player, NPC, enemy, state, and combat code.
- `items/`: item metadata, drop tables, dropped item scenes, and inventory data.
- `resources/`: authored `.tres` resources for actors, animation, combat, and profiles.
- `ui/`: HUD, inventory, dialog, and reusable UI widgets.
- `world/`: world scenes, terrain helpers, and interaction helpers.
