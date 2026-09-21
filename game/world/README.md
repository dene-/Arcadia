# World

World and level-facing content lives here.

- `scenes/`: playable world scenes, including the project main scene.
- `terrain/`: terrain helper scripts and tile-layer behavior.
- `interaction/`: world interaction prompts and helpers.

World scenes should compose actors, UI, terrain, and interaction nodes. Keep actor behavior in `res://game/actors/...` and item behavior in `res://game/items/...`.

The playable map is the saved-seed Rekala region. See [region setup and extension guide](../../docs/world_region.md) for local art imports, terrain patterns, placement rules and save behavior.
