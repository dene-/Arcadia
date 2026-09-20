# Rekala region

The main scene now builds a 304 × 240 tile region (2,432 × 1,920 pixels). Rekala is fixed: nine named residents, workshops, a well and square, farm fields and an animated windmill. Three bridges connect the woodland routes across the river. Nine clearings contain 27 goblins/orcs; monsters retain their existing restart behavior.

The first game launch assigns `world.region_seed` in `user://npc_world.json`. Subsequent launches recreate the same tree, ground-detail and enemy placements. Town buildings, roads, crossings and encounter landmarks are authored coordinates, independent of the seed. Named NPC IDs and persistent deaths are preserved. Older saves gain a seed without resetting their memories. The existing explicit world reset also clears the seed; do not delete a save just to change the scenery.

## Local art setup

Minifantasy art is by **Krishna Palacio**. The public repository excludes the newly purchased raw sheets. Obtain these packs through your own itch.io purchases:

- Forgotten Plains, commercial v3.6
- Towns v3.0
- Towns II v1.5
- Silent Swamp v1.0
- Crafting and Professions v1.0
- Farm v3.0

Keep their ZIPs in one directory, then run:

```bash
"$GODOT" --headless --path . --script res://tools/art/import_world_packs.gd -- /path/to/zips
"$GODOT" --headless --path . --editor --import
```

The importer copies selected original sheets to ignored `assets/art/world_packs/`. No account tokens or purchase URLs are needed or stored. The world displays a setup message if required sheets are unavailable. Import the packs before exporting a playable build. Preserve the downloaded license files; their terms require credit and a project link to the creator upon completion. See [credits](../CREDITS.md).

## Editing and extension

- `game/world/region/region_layout.gd`: pure seeded placement, fixed town homes, roads, clearings and reserved space. Coordinates are terrain cells, eight pixels each.
- `region_terrain.gd`: grass/dirt/stone terrain connections, animated river shores, wetland transition tiles, crossings and boundary collision.
- `region_town.gd`: cottage patterns, work props, farm, windmill and named NPC instances. NPC data is duplicated before local roam tuning; profiles keep their stable IDs.
- `region_art.gd`: cached atlas textures, prop origins and solid footprints. Trees sort at their feet and collide only at their trunks.
- `rekala_region.gd`: scene composition and save integration. Generated nodes appear beneath `World/Region` in the Remote tree.
- `game/resources/world/`: extracted reusable TileSets and the cottage TileMapPattern, retaining the original atlas coordinates.

Select the World node in the editor to change `Preview Seed` and click **Rebuild region preview**. Editor previews never touch the player save. Runtime actors are spawned when the game runs. The runtime seed comes from the save, not the preview setting. New landmarks should reserve their footprint before the tree pass and connect to the road graph. Keep saved landmark positions stable when extending a released world.

Houses are exterior scenery. Enemy movement still uses the existing local chasing/roaming behavior; this change supplies clear encounters and routes, not a new navigation system. Forest placements are procedural; town layout and route topology are authored.

## Verification

```bash
"$GODOT" --headless --path . --script res://tests/test_runner.gd
"$GODOT" --headless --path . --script res://tools/world/check_region.gd
```

The second check requires the local art. It instantiates the real world with an isolated temporary save, disables provider endpoints and actor processing, checks nine NPCs and 27 enemies, and verifies clear bridge crossings, solid houses/water, and unobstructed NPC spawn points. It never writes the player's save.
