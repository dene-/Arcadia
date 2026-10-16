# Rekala region

The main scene now builds a 304 × 240 tile region (2,432 × 1,920 pixels). Rekala is fixed: 33 residents in twelve households, workshops with trade props, a well and market square, an orchard, a fenced cemetery, a fenced farm field and an animated windmill. Three arched stone bridges connect the woodland routes across the river. Nine forest clearings and four town approaches contain 35 goblins/orcs. The closest encounter is along the west road outside the fence. Monsters retain their existing restart behavior.

The first game launch assigns `world.region_seed` in `user://npc_world.json`. Subsequent launches recreate the same tree, ground-detail and enemy placements. Rocks, fallen wood, undergrowth and bank reeds come from a separate generator seeded from the same value, so adding them did not move existing trees or enemies. Town buildings, roads, crossings, fences and encounter landmarks are authored coordinates, independent of the seed. Named NPC IDs and persistent deaths are preserved. Older saves gain a seed without resetting their memories. The existing explicit world reset also clears the seed; do not delete a save just to change the scenery.

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

- `game/world/region/region_layout.gd`: pure seeded placement, fixed town homes, roads, dooryards, clearings, forest props/ground cover and reserved space. Coordinates are terrain cells, eight pixels each. `is_swamp` is the wetland outline shared by terrain and tree species.
- `region_terrain.gd`: grass/dirt/stone terrain connections, animated river shores, wetland transition tiles, the stone bridges and boundary collision. A bridge's deck is the three rows around its row; the river barrier closes the arches and a strip under the front parapet closes the deck edge.
- `region_town.gd`: cottage patterns, per-trade signs and yard props, square, farm, orchard, windmill, the fence network and named NPC instances. Fences are one cell set (town ring, cemetery, field): rails, posts, corners and T-joints follow neighbouring cells, gaps open wherever a road passes and the fence stops at the river bank. Yard props that would land on a street are skipped. NPC data is duplicated before local roam tuning; profiles keep their stable IDs.
- `region_art.gd`: cached atlas textures and the named prop catalog (`PROPS`: sheet, region, collision footprint; `GROUND_COVER`: sheet, region). Every region is whole 8 px cells around one complete sprite; footprints are in sprite-local pixels and art and collision share the footprint's bottom-centre as their origin. `prop()` adds the pack's cast shadow when one exists and can mirror a prop around its footprint. Trees sort at their feet and collide at their trunks; the windmill uses a polygon matching its base. Ground cover draws below actors and never collides.
- `rekala_region.gd`: scene composition and save integration. Trees vary by mirroring and a slight tint; clearing ruins are placed off the clearing's road. Generated nodes appear beneath `World/Region` in the Remote tree.
- `game/resources/world/`: reusable TileSets and separate cottage wall/roof TileMapPatterns. Each house draws its Roof layer over Walls so transparent roof pixels reveal the building underneath. Both layers share one origin and the house's depth sorting.
- `game/world/life/town_cemetery.gd`: grave plots, headstones and name labels; its enclosure is part of the town fence.

Select the World node in the editor to change `Preview Seed` and click **Rebuild region preview**. Editor previews show static NPC and enemy sprites without AI, physics, provider calls or access to the player save. Runtime actors spawn when the game runs; enemies are named `Enemy00`, `Enemy01`, etc. beneath `World/Region` in the Remote tree. The runtime seed comes from the save, not the preview setting. New landmarks should reserve their footprint before the tree pass and connect to the road graph. Keep saved landmark positions stable when extending a released world.

Houses are exterior scenery. Enemy movement still uses the existing local chasing/roaming behavior; this change supplies clear encounters and routes, not a new navigation system. Forest placements are procedural; town layout and route topology are authored.

## Verification

```bash
"$GODOT" --headless --path . --script res://tests/test_runner.gd
"$GODOT" --headless --path . --script res://tools/world/check_region.gd
"$GODOT" --path . --script res://tools/world/capture_region.gd -- /tmp/rekala 2
```

The second check requires the local art. It instantiates the real world with an isolated temporary save and disabled provider endpoints. It checks every resident and the 35 enemies, walkable bridge decks with closed sides, prop footprints, houses/water, unobstructed spawn spots for each household, open town gates, intact swamp crops, the first encounter's distance from the west gate and a nearby enemy's chase decision. It never writes the player's save.

The capture tool needs a display (omit `--headless`). It renders an overview plus a grid of 1920 × 1080 PNGs at the given camera zoom; pass `x,y` world positions after the zoom to capture specific spots. It uses the same isolated save and freezes actors.
