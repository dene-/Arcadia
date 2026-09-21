# Addons

Godot addons and plugins belong here.

Keep third-party addon folder names and structure intact unless the addon documentation says otherwise. Project gameplay code should stay under `res://game/...`; only addon/plugin code should live here.

When adding an addon, document whether it must be enabled in Project Settings > Plugins and whether it affects exported builds.

## NPC Debug

The bundled `npc_debug` plugin is enabled in Project Settings > Plugins. It adds a
**Reset NPCs** button to the editor's main toolbar and does not add runtime UI to exports.
Stop the game (including any separately launched copies), click the button, then confirm.
The next Play starts with everyone alive, cleared learned memories, rumors, bodies and
guard reports, fresh personalities, relationships and routines, and reset time/economy.
Authored knowledge and core memories remain part of each NPC's initial profile.

The default keeps the map seed, resident identities and families. A separate saved NPC
seed makes rerolled personalities persist across restarts without changing the forest.
Uncheck the map option for a fresh region too. The previous combined save is backed up
beside `user://npc_world.json` before replacement. The same operation is available via
`--script res://tools/reset_npc_world.gd -- --confirm --keep-region --reroll-npcs`.
