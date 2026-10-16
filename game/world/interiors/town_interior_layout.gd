class_name TownInteriorLayout
extends RefCounted

## Authored room plans for every enterable building: wall style, floor zones, partition walls
## with doorway gaps, furniture and the anchors residents use. Coordinates are room-local pixels;
## navigation grid points are multiples of 8, and every anchor is one of them. Seeded details
## (rug colours, wall pictures) personalize a room without moving anything that blocks a path.

## Furniture: [sheet, whole-sprite region, collision footprint in region pixels]. A footprint's
## bottom centre is the prop's foot; an empty footprint is a decoration without collision.
const PROPS: Dictionary = {
	"bed": [RegionArt.TOWN, Rect2i(80, 360, 16, 16), Rect2(0, 6, 16, 10)],
	"wardrobe": [RegionArt.TOWN, Rect2i(32, 240, 16, 24), Rect2(2, 13, 11, 6)],
	"dresser": [RegionArt.TOWN, Rect2i(48, 240, 16, 24), Rect2(2, 13, 11, 6)],
	"cabinet": [RegionArt.TOWN, Rect2i(64, 240, 16, 24), Rect2(2, 13, 11, 6)],
	"cupboard": [RegionArt.TOWN, Rect2i(80, 240, 16, 24), Rect2(2, 13, 11, 6)],
	"pantry": [RegionArt.TOWN, Rect2i(96, 240, 16, 24), Rect2(2, 13, 11, 6)],
	"table": [RegionArt.TOWN, Rect2i(8, 224, 16, 16), Rect2(3, 7, 11, 7)],
	"table_work": [RegionArt.TOWN, Rect2i(24, 224, 16, 16), Rect2(3, 7, 11, 7)],
	"table_papers": [RegionArt.TOWN, Rect2i(40, 224, 16, 16), Rect2(3, 7, 11, 7)],
	"table_tools": [RegionArt.TOWN, Rect2i(56, 224, 16, 16), Rect2(3, 7, 11, 7)],
	"table_cloth": [RegionArt.TOWN, Rect2i(72, 224, 16, 16), Rect2(3, 7, 11, 7)],
	"table_dishes": [RegionArt.TOWN, Rect2i(88, 224, 16, 16), Rect2(3, 7, 11, 7)],
	"table_feast": [RegionArt.TOWN, Rect2i(104, 224, 16, 16), Rect2(3, 7, 11, 7)],
	"table_meal": [RegionArt.TOWN, Rect2i(120, 224, 16, 16), Rect2(3, 7, 11, 7)],
	"chair": [RegionArt.TOWN, Rect2i(136, 224, 16, 16), Rect2(4, 10, 9, 5)],
	"stool": [RegionArt.TOWN, Rect2i(120, 368, 8, 8), Rect2()],
	"footstool": [RegionArt.TOWN, Rect2i(152, 232, 16, 8), Rect2()],
	"seat": [RegionArt.TOWN, Rect2i(168, 224, 8, 16), Rect2()],
	"counter": [RegionArt.TOWN, Rect2i(24, 208, 16, 16), Rect2(0, 10, 16, 6)],
	"counter_ledger": [RegionArt.TOWN, Rect2i(64, 208, 16, 16), Rect2(0, 10, 16, 6)],
	"counter_cloth": [RegionArt.TOWN, Rect2i(104, 208, 16, 16), Rect2(0, 10, 16, 6)],
	"counter_kitchen": [RegionArt.TOWN, Rect2i(144, 208, 16, 16), Rect2(0, 10, 16, 6)],
	"counter_side": [RegionArt.TOWN, Rect2i(8, 208, 8, 16), Rect2(0, 6, 8, 10)],
	"counter_side_ledger": [RegionArt.TOWN, Rect2i(48, 208, 8, 16), Rect2(0, 6, 8, 10)],
	"counter_side_cloth": [RegionArt.TOWN, Rect2i(88, 208, 8, 16), Rect2(0, 6, 8, 10)],
	"counter_side_potions": [RegionArt.TOWN, Rect2i(128, 208, 8, 16), Rect2(0, 6, 8, 10)],
	"shelf": [RegionArt.TOWN, Rect2i(8, 320, 8, 16), Rect2(0, 6, 8, 5)],
	"shelf_books": [RegionArt.TOWN, Rect2i(72, 320, 8, 16), Rect2(0, 6, 8, 5)],
	"shelf_jars": [RegionArt.TOWN, Rect2i(104, 320, 8, 16), Rect2(0, 6, 8, 5)],
	"shelf_crafts": [RegionArt.TOWN, Rect2i(56, 320, 8, 16), Rect2(0, 6, 8, 5)],
	"rack_potions": [RegionArt.TOWN, Rect2i(136, 312, 8, 24), Rect2(0, 13, 8, 6)],
	"rack_books": [RegionArt.TOWN, Rect2i(88, 312, 8, 24), Rect2(0, 13, 8, 6)],
	"shelf_glass": [RegionArt.TOWN, Rect2i(80, 344, 16, 16), Rect2(0, 6, 16, 5)],
	"shelf_wares": [RegionArt.TOWN, Rect2i(152, 344, 16, 16), Rect2(0, 6, 16, 5)],
	"shelf_low_books": [RegionArt.TOWN, Rect2i(176, 344, 16, 16), Rect2(0, 6, 16, 5)],
	"shelf_low": [RegionArt.TOWN, Rect2i(8, 344, 16, 16), Rect2(0, 6, 16, 5)],
	"bookcase": [RegionArt.TOWN, Rect2i(104, 336, 16, 24), Rect2(0, 13, 16, 6)],
	"bookcase_tall": [RegionArt.TOWN, Rect2i(128, 336, 16, 24), Rect2(0, 13, 16, 6)],
	"bookcase_full": [RegionArt.TOWN, Rect2i(200, 336, 16, 24), Rect2(0, 13, 16, 6)],
	"armchair_wood": [RegionArt.TOWN, Rect2i(32, 64, 16, 16), Rect2(2, 10, 14, 6)],
	"plant": [RegionArt.TOWN, Rect2i(48, 48, 8, 16), Rect2(1, 11, 7, 4)],
	"plant_red": [RegionArt.TOWN, Rect2i(32, 48, 16, 16), Rect2(4, 11, 9, 4)],
	"plant_small": [RegionArt.TOWN, Rect2i(56, 48, 8, 16), Rect2(2, 12, 5, 3)],
	"hearth": [RegionArt.TOWN, Rect2i(8, 104, 24, 40), Rect2(3, 30, 18, 10)],
	"oven": [RegionArt.TOWN, Rect2i(32, 120, 24, 24), Rect2(3, 16, 18, 8)],
	"stove": [RegionArt.TOWN, Rect2i(8, 144, 24, 32), Rect2(4, 25, 19, 7)],
	"anvil_block": [RegionArt.TOWN, Rect2i(160, 128, 16, 16), Rect2(2, 10, 12, 5)],
	"quench_box": [RegionArt.TOWN, Rect2i(144, 136, 16, 8), Rect2(3, 2, 10, 5)],
	"water_barrel": [RegionArt.TOWN, Rect2i(176, 128, 8, 16), Rect2(0, 10, 7, 5)],
	"spear_rack": [RegionArt.TOWN, Rect2i(96, 120, 8, 24), Rect2(0, 19, 5, 4)],
	"weapon_bin": [RegionArt.TOWN, Rect2i(112, 120, 16, 24), Rect2(1, 15, 15, 4)],
	"weapon_crate": [RegionArt.TOWN, Rect2i(128, 128, 16, 16), Rect2(1, 11, 15, 5)],
	"board": [RegionArt.TOWN, Rect2i(128, 88, 16, 16), Rect2(2, 12, 12, 3)],
	"frame_bright": [RegionArt.TOWN, Rect2i(8, 184, 16, 8), Rect2()],
	"frame_night": [RegionArt.TOWN, Rect2i(8, 192, 16, 8), Rect2()],
	"frame_sea": [RegionArt.TOWN, Rect2i(8, 200, 16, 8), Rect2()],
	"portrait": [RegionArt.TOWN, Rect2i(24, 184, 16, 8), Rect2()],
	"portrait_b": [RegionArt.TOWN, Rect2i(48, 184, 8, 8), Rect2()],
	"portrait_c": [RegionArt.TOWN, Rect2i(64, 184, 8, 8), Rect2()],
	"frame_small": [RegionArt.TOWN, Rect2i(80, 184, 8, 8), Rect2()],
	"sofa": [RegionArt.TOWN_II, Rect2i(8, 8, 32, 16), Rect2(2, 6, 27, 6)],
	"settee": [RegionArt.TOWN_II, Rect2i(8, 24, 24, 16), Rect2(2, 6, 19, 6)],
	"armchair": [RegionArt.TOWN_II, Rect2i(8, 40, 16, 16), Rect2(2, 6, 12, 6)],
	"stool_round": [RegionArt.TOWN_II, Rect2i(80, 8, 8, 8), Rect2()],
	"bench": [RegionArt.TOWN_II, Rect2i(80, 24, 16, 8), Rect2(0, 3, 16, 5)],
	"bench_side": [RegionArt.TOWN_II, Rect2i(104, 16, 8, 16), Rect2(0, 4, 8, 12)],
	"table_long": [RegionArt.TOWN_II, Rect2i(80, 40, 16, 16), Rect2(0, 6, 16, 10)],
	"mirror": [RegionArt.TOWN_II, Rect2i(160, 0, 16, 24), Rect2(4, 17, 8, 4)],
	"bath": [RegionArt.TOWN_II, Rect2i(184, 8, 16, 16), Rect2(0, 5, 15, 8)],
	"washstand": [RegionArt.TOWN_II, Rect2i(168, 48, 8, 16), Rect2()],
	"flour": [RegionArt.TOWN_II, Rect2i(16, 72, 8, 8), Rect2()],
	"bread": [RegionArt.TOWN_II, Rect2i(16, 80, 8, 8), Rect2()],
	"garlic": [RegionArt.TOWN_II, Rect2i(16, 88, 8, 8), Rect2()],
	"spice_cabinet": [RegionArt.TOWN_II, Rect2i(168, 88, 8, 16), Rect2(0, 5, 8, 5)],
	"iron_stove": [RegionArt.TOWN_II, Rect2i(232, 8, 8, 8), Rect2(0, 3, 8, 4)],
	"furnace": [RegionArt.SMITH, Rect2i(32, 0, 32, 32), Rect2(7, 24, 18, 6)],
	"anvil": [RegionArt.SMITH, Rect2i(8, 16, 16, 16), Rect2(2, 6, 12, 4)],
	"quench": [RegionArt.SMITH, Rect2i(64, 16, 16, 16), Rect2(6, 6, 7, 4)],
	"grindstone": [RegionArt.SMITH, Rect2i(0, 32, 16, 16), Rect2(3, 11, 13, 5)],
	"spinning_wheel": [RegionArt.TAILOR, Rect2i(0, 8, 24, 16), Rect2(7, 12, 17, 4)],
	"loom": [RegionArt.TAILOR, Rect2i(32, 0, 32, 32), Rect2(4, 18, 24, 6)],
	"workbench": [RegionArt.WOODWORK, Rect2i(8, 8, 48, 48), Rect2(5, 13, 38, 30)],
	"sawhorse": [RegionArt.WOODWORK, Rect2i(128, 8, 32, 24), Rect2(7, 14, 21, 5)],
	"hay_bale": [RegionArt.FARM, Rect2i(56, 8, 16, 32), Rect2(2, 18, 12, 4)],
	"trough": [RegionArt.FARM, Rect2i(120, 24, 16, 8), Rect2(1, 3, 14, 4)],
	"feed_trough": [RegionArt.FARM, Rect2i(120, 16, 16, 8), Rect2(1, 3, 14, 4)],
	"chest": [RegionArt.FARM, Rect2i(120, 40, 16, 8), Rect2(0, 3, 16, 5)],
	"crate": [RegionArt.FARM, Rect2i(144, 40, 8, 8), Rect2(0, 2, 8, 5)],
	"bucket": [RegionArt.FARM, Rect2i(120, 56, 8, 8), Rect2()],
	"milk_can": [RegionArt.FARM, Rect2i(128, 56, 8, 8), Rect2()],
	"vat": [RegionArt.FARM, Rect2i(136, 16, 8, 16), Rect2(1, 6, 6, 8)],
	"vat_blue": [RegionArt.FARM, Rect2i(144, 16, 8, 16), Rect2(1, 6, 6, 8)],
	"side_shelf_l": [RegionArt.TOWN, Rect2i(8, 288, 8, 24), Rect2(0, 19, 6, 5)],
	"side_shelf_l_low": [RegionArt.TOWN, Rect2i(16, 296, 8, 16), Rect2(0, 11, 6, 5)],
	"side_cabinet_l": [RegionArt.TOWN, Rect2i(8, 264, 8, 24), Rect2(0, 19, 5, 5)],
	"side_cabinet_l_low": [RegionArt.TOWN, Rect2i(16, 272, 8, 16), Rect2(0, 11, 5, 5)],
	"side_shelf_r": [RegionArt.TOWN, Rect2i(96, 288, 8, 24), Rect2(2, 19, 6, 5)],
	"side_shelf_r_low": [RegionArt.TOWN, Rect2i(88, 296, 8, 16), Rect2(2, 11, 6, 5)],
	"side_cabinet_r": [RegionArt.TOWN, Rect2i(96, 264, 8, 24), Rect2(3, 19, 5, 5)],
	"side_cabinet_r_low": [RegionArt.TOWN, Rect2i(88, 272, 8, 16), Rect2(3, 11, 5, 5)],
	"wall_rack": [RegionArt.TOWN, Rect2i(32, 200, 16, 8), Rect2()],
	"wall_swords": [RegionArt.TOWN, Rect2i(64, 200, 8, 8), Rect2()],
	"wall_shield": [RegionArt.TOWN, Rect2i(80, 200, 8, 8), Rect2()],
}

## Towns II rugs, one 24 px crop per colour; drawn under actors and furniture.
const RUG_REGIONS: Array[Rect2i] = [Rect2i(120, 0, 24, 24), Rect2i(120, 24, 24, 24),
	Rect2i(120, 48, 24, 24), Rect2i(120, 72, 24, 24), Rect2i(120, 96, 24, 24)]
## Wall pictures of one width are interchangeable; a room's seed picks among them.
const WALL_PICTURES: Array[Array] = [["frame_bright", "frame_night", "frame_sea"],
	["portrait_b", "portrait_c", "frame_small"]]
## A partition doorway is two 8 px cells wide: one grid point with clearance on both sides.
const DOORWAY_CELLS: int = 2
## Matches `TownNavigation` clearance for the town's resident footprint.
const CLEARANCE: float = 5.25
## Rooms by HOMES job or PUBLIC_BUILDINGS id. `floors` paint in order over the whole floor; a
## partition runs along row/column `at` from `from` to `to` (cells), with an optional doorway at
## `gap`. Beds, meals and works are listed in household order (the founder, then elders first);
## public rooms name their `seats` and `spots` instead.
const BUILDINGS: Dictionary = {
	"alchemist": {
		"floor": Rect2i(-5, -4, 11, 7), "wall": "plank", "door_x": -16.0,
		"floors": [[Rect2i(-5, -4, 11, 7), "oak"], [Rect2i(1, -4, 5, 7), "parquet"]],
		"partitions": [{"axis": "v", "at": 0, "from": -4, "to": -1}],
		"props": [["rack_potions", Vector2(-36, -24)], ["shelf_glass", Vector2(-24, -24)],
			["bookcase", Vector2(-8, -24)], ["table_tools", Vector2(-24, 0)],
			["side_shelf_l", Vector2(-37, 12)], ["flour", Vector2(-36, -4)],
			["garlic", Vector2(-12, -4)], ["bed", Vector2(24, -16)], ["chest", Vector2(40, -20)],
			["plant_small", Vector2(12, -24)], ["table", Vector2(16, 16)],
			["iron_stove", Vector2(44, 4)], ["stool", Vector2(36, 10)], ["plant", Vector2(-36, 24)],
			["bucket", Vector2(44, 22)], ["crate", Vector2(0, 24)], ["milk_can", Vector2(-36, 4)],
			["bread", Vector2(-4, -4)]],
		"rugs": [[1, Vector2(16, 20)], [3, Vector2(-8, 12)]],
		"decor": [["frame_small", Vector2(28, -36)], ["portrait_b", Vector2(-28, -36)]],
		"windows": [[-16, 0], [40, 0]],
		"beds": [Vector2(24, -16)],
		"meals": [Vector2(16, 0)],
		"works": [Vector2(-24, 8)],
	},
	"jeweller": {
		"floor": Rect2i(-5, -4, 10, 7), "wall": "stucco", "door_x": 16.0,
		"floors": [[Rect2i(-5, -4, 10, 7), "parquet"], [Rect2i(-5, -4, 4, 7), "oak"]],
		"partitions": [{"axis": "v", "at": -1, "from": -4, "to": -1}],
		"props": [["bed", Vector2(-24, -16)], ["crate", Vector2(-12, -24)],
			["plant_small", Vector2(-36, -24)], ["side_cabinet_l", Vector2(-37, 24)],
			["shelf_glass", Vector2(8, -24)], ["shelf_wares", Vector2(24, -24)],
			["mirror", Vector2(36, -24)], ["counter_cloth", Vector2(24, -4)],
			["table", Vector2(-32, 16)], ["iron_stove", Vector2(36, 4)], ["stool", Vector2(32, 12)],
			["plant", Vector2(-12, 24)], ["footstool", Vector2(-20, 26)],
			["shelf_jars", Vector2(-4, 16)]],
		"rugs": [[3, Vector2(-32, 20)], [0, Vector2(16, 12)]],
		"decor": [["portrait", Vector2(-20, -36)], ["frame_sea", Vector2(16, -36)]],
		"windows": [[0, 1], [-32, 1]],
		"beds": [Vector2(-24, -16)],
		"meals": [Vector2(-32, 0)],
		"works": [Vector2(24, -16)],
	},
	"tailor": {
		"floor": Rect2i(-6, -5, 13, 9), "wall": "stucco", "door_x": -24.0,
		"floors": [[Rect2i(-6, -5, 13, 9), "oak"], [Rect2i(2, -5, 5, 9), "parquet"]],
		"partitions": [{"axis": "v", "at": 1, "from": -5, "to": 4, "gap": 0}],
		"props": [["loom", Vector2(-28, -32)], ["spinning_wheel", Vector2(-4, -32)],
			["side_shelf_l", Vector2(-45, -8)], ["side_shelf_l_low", Vector2(-45, 8)],
			["table_cloth", Vector2(-28, 8)], ["table_papers", Vector2(-12, 8)],
			["iron_stove", Vector2(-44, 28)], ["stool", Vector2(-44, 18)], ["flour", Vector2(4, 28)],
			["bed", Vector2(24, -24)], ["bed", Vector2(48, -24)], ["bed", Vector2(48, 8)],
			["chest", Vector2(32, 32)], ["plant_small", Vector2(52, 28)]],
		"rugs": [[1, Vector2(-20, 12)], [0, Vector2(36, -4)]],
		"decor": [["frame_bright", Vector2(-28, -44)], ["portrait_b", Vector2(36, -44)]],
		"windows": [[-40, 2], [8, 3]],
		"beds": [Vector2(24, -24), Vector2(48, 8), Vector2(48, -24)],
		"meals": [Vector2(-32, 16), Vector2(-8, 16), Vector2(-24, -8)],
		"works": [Vector2(-32, -24), Vector2(-8, -24), Vector2(-16, -8)],
	},
	"blacksmith": {
		"floor": Rect2i(-8, -5, 17, 10), "wall": "stucco", "door_x": -40.0,
		"floors": [[Rect2i(-8, -5, 17, 10), "oak"], [Rect2i(-8, -5, 7, 10), "cobble"]],
		"partitions": [{"axis": "v", "at": -1, "from": -5, "to": 5, "gap": 0}],
		"props": [["furnace", Vector2(-40, -32)], ["grindstone", Vector2(-20, -32)],
			["anvil", Vector2(-32, -8)], ["quench", Vector2(-52, -8)],
			["water_barrel", Vector2(-60, 16)], ["water_barrel", Vector2(-60, 24)],
			["weapon_bin", Vector2(-16, 40)], ["spear_rack", Vector2(-58, 40)],
			["weapon_crate", Vector2(-56, -24)], ["bed", Vector2(16, -24)], ["bed", Vector2(40, -24)],
			["bed", Vector2(64, -24)], ["bed", Vector2(64, 16)], ["crate", Vector2(28, -28)],
			["crate", Vector2(52, -28)], ["table", Vector2(24, 16)], ["table", Vector2(40, 16)],
			["iron_stove", Vector2(12, 40)], ["stool", Vector2(20, 38)], ["cupboard", Vector2(64, 40)],
			["plant_small", Vector2(36, 38)], ["anvil_block", Vector2(-20, 24)]],
		"rugs": [[4, Vector2(32, 20)], [2, Vector2(40, -8)]],
		"decor": [["frame_night", Vector2(40, -44)], ["portrait_c", Vector2(-16, -44)],
			["wall_rack", Vector2(-28, -44)], ["wall_shield", Vector2(56, -44)]],
		"windows": [[-56, 0], [16, 1], [56, 1]],
		"beds": [Vector2(16, -24), Vector2(40, -24), Vector2(64, -24), Vector2(64, 16)],
		"meals": [Vector2(24, 0), Vector2(48, 0), Vector2(24, 32), Vector2(48, 32)],
		"works": [Vector2(-32, 0), Vector2(-48, 24)],
	},
	"cooker": {
		"floor": Rect2i(-9, -5, 18, 11), "wall": "plank", "door_x": -8.0,
		"floors": [[Rect2i(-9, -5, 18, 11), "oak"], [Rect2i(-9, -5, 10, 2), "cobble"],
			[Rect2i(5, -5, 4, 11), "oak"]],
		"partitions": [{"axis": "v", "at": 4, "from": -5, "to": 6, "gap": -1}],
		"props": [["stove", Vector2(-60, -32)], ["oven", Vector2(-36, -32)],
			["pantry", Vector2(-16, -32)], ["spice_cabinet", Vector2(-4, -32)],
			["flour", Vector2(4, -26)], ["bread", Vector2(-68, -14)], ["counter", Vector2(-56, -8)],
			["counter_ledger", Vector2(-40, -8)], ["counter_kitchen", Vector2(-24, -8)],
			["water_barrel", Vector2(-68, 0)], ["table_meal", Vector2(-48, 24)],
			["table_feast", Vector2(-32, 24)], ["table_dishes", Vector2(0, 24)],
			["table_cloth", Vector2(16, 24)], ["plant_red", Vector2(28, -28)],
			["crate", Vector2(-68, 48)], ["bed", Vector2(56, -24)], ["crate", Vector2(68, -28)],
			["table", Vector2(56, 24)], ["side_cabinet_r", Vector2(69, 8)], ["chest", Vector2(56, 48)],
			["washstand", Vector2(44, 46)], ["seat", Vector2(-64, 23)], ["stool", Vector2(-48, 7)],
			["stool", Vector2(-24, 7)], ["seat", Vector2(-48, 39)], ["stool", Vector2(-24, 39)],
			["stool", Vector2(0, 7)], ["stool", Vector2(24, 39)]],
		"rugs": [[3, Vector2(-40, 28)], [1, Vector2(8, 28)], [0, Vector2(56, 28)]],
		"decor": [["frame_bright", Vector2(-20, -44)], ["portrait", Vector2(16, -44)],
			["frame_small", Vector2(56, -44)], ["wall_shield", Vector2(-56, -44)]],
		"windows": [[-48, 0], [0, 0], [48, 0]],
		"beds": [Vector2(56, -24)],
		"meals": [Vector2(56, 8)],
		"works": [Vector2(-40, -24)],
		"seats": {"tavern": [Vector2(-64, 24), Vector2(-48, 8), Vector2(-24, 8), Vector2(-48, 40),
			Vector2(-24, 40), Vector2(0, 8), Vector2(24, 8), Vector2(24, 40)]},
		"spots": {"tavern": Vector2(-8, 0)},
	},
	"carpenter": {
		"floor": Rect2i(-7, -5, 14, 10), "wall": "plank", "door_x": -24.0,
		"floors": [[Rect2i(-7, -5, 14, 10), "oak"], [Rect2i(-7, 0, 14, 5), "earth"]],
		"partitions": [{"axis": "h", "at": -1, "from": -7, "to": 7, "gap": 2}],
		"props": [["bed", Vector2(-40, -24)], ["bed", Vector2(-16, -24)], ["bed", Vector2(40, -24)],
			["crate", Vector2(-28, -28)], ["crate", Vector2(52, -28)], ["table", Vector2(8, -24)],
			["table", Vector2(24, -24)], ["plant_small", Vector2(-4, -36)],
			["sawhorse", Vector2(8, 32)], ["table_work", Vector2(40, 32)],
			["side_shelf_r_low", Vector2(53, 24)], ["side_shelf_l_low", Vector2(-53, 32)],
			["crate", Vector2(-48, 40)], ["chest", Vector2(-4, 40)], ["iron_stove", Vector2(-52, 24)],
			["stool", Vector2(-44, 20)], ["bucket", Vector2(20, 38)], ["flour", Vector2(-52, -4)]],
		"rugs": [[2, Vector2(16, -20)], [0, Vector2(40, 36)]],
		"decor": [["frame_sea", Vector2(-28, -44)], ["portrait_b", Vector2(16, -44)]],
		"windows": [[-48, 0], [32, 0]],
		"beds": [Vector2(-40, -24), Vector2(-16, -24), Vector2(40, -24)],
		"meals": [Vector2(0, -16), Vector2(24, -16), Vector2(48, -16)],
		"works": [Vector2(8, 16), Vector2(-24, -16), Vector2(40, 16)],
	},
	"dyer": {
		"floor": Rect2i(-6, -4, 12, 8), "wall": "stucco", "door_x": 24.0,
		"floors": [[Rect2i(-6, -4, 12, 8), "oak"], [Rect2i(-6, -4, 5, 8), "parquet"]],
		"partitions": [{"axis": "v", "at": -1, "from": -4, "to": 4, "gap": 0}],
		"props": [["bed", Vector2(-32, -16)], ["bed", Vector2(-32, 16)],
			["crate", Vector2(-20, -20)], ["plant_small", Vector2(-44, -28)],
			["side_cabinet_l", Vector2(-45, 32)], ["vat_blue", Vector2(12, -24)],
			["vat", Vector2(20, -24)], ["vat_blue", Vector2(28, -24)],
			["water_barrel", Vector2(44, -24)], ["table", Vector2(40, 0)],
			["iron_stove", Vector2(8, 28)], ["stool", Vector2(4, 20)],
			["side_shelf_r_low", Vector2(45, 32)], ["bucket", Vector2(36, -18)]],
		"rugs": [[1, Vector2(40, 4)], [2, Vector2(-20, 0)]],
		"decor": [["frame_small", Vector2(-24, -36)], ["portrait_c", Vector2(24, -36)]],
		"windows": [[-40, 1], [0, 2]],
		"beds": [Vector2(-32, -16), Vector2(-32, 16)],
		"meals": [Vector2(24, 0), Vector2(40, 16)],
		"works": [Vector2(16, -16), Vector2(32, -16)],
	},
	"butcher": {
		"floor": Rect2i(-7, -4, 14, 8), "wall": "plank", "door_x": -32.0,
		"floors": [[Rect2i(-7, -4, 14, 8), "oak"], [Rect2i(-7, -4, 5, 8), "cobble"]],
		"partitions": [{"axis": "v", "at": -2, "from": -4, "to": 4, "gap": 0}],
		"props": [["hearth", Vector2(-40, -16)], ["counter_cloth", Vector2(-48, 8)],
			["side_shelf_l", Vector2(-53, -8)], ["crate", Vector2(-24, -24)], ["bed", Vector2(0, -16)],
			["bed", Vector2(24, -16)], ["bed", Vector2(48, -16)], ["table", Vector2(16, 24)],
			["table", Vector2(32, 24)], ["iron_stove", Vector2(52, 32)], ["stool", Vector2(44, 30)]],
		"rugs": [[3, Vector2(24, 28)]],
		"decor": [["portrait_c", Vector2(12, -36)], ["frame_night", Vector2(36, -36)]],
		"windows": [[-48, 0], [32, 0]],
		"beds": [Vector2(0, -16), Vector2(48, -16), Vector2(24, -16)],
		"meals": [Vector2(16, 8), Vector2(40, 8), Vector2(0, 24)],
		"works": [Vector2(-40, -8), Vector2(24, 8), Vector2(-32, 0)],
	},
	"furrier": {
		"floor": Rect2i(-6, -4, 12, 9), "wall": "stucco", "door_x": -40.0,
		"floors": [[Rect2i(-6, -4, 12, 9), "oak"], [Rect2i(2, -4, 4, 8), "parquet"]],
		"partitions": [{"axis": "v", "at": 1, "from": -4, "to": 0}],
		"props": [["bed", Vector2(32, -16)], ["bed", Vector2(32, 24)], ["crate", Vector2(44, -20)],
			["iron_stove", Vector2(44, 8)], ["stool", Vector2(44, 20)],
			["table_work", Vector2(-24, -24)], ["cupboard", Vector2(-8, -24)],
			["hay_bale", Vector2(-42, -24)], ["counter_cloth", Vector2(-40, 8)],
			["table", Vector2(-20, 16)], ["plant", Vector2(4, -28)], ["chest", Vector2(-4, 40)],
			["side_shelf_l_low", Vector2(-45, 0)]],
		"rugs": [[0, Vector2(-20, 20)], [4, Vector2(32, 0)]],
		"decor": [["frame_small", Vector2(-24, -36)], ["portrait", Vector2(32, -36)]],
		"windows": [[-40, 0], [16, 3]],
		"beds": [Vector2(32, -16), Vector2(32, 24)],
		"meals": [Vector2(-32, 16), Vector2(-8, 16)],
		"works": [Vector2(-24, -16), Vector2(-8, -16)],
	},
	"voss_house": {
		"floor": Rect2i(-6, -5, 13, 9), "wall": "plank", "door_x": -40.0,
		"floors": [[Rect2i(-6, -5, 13, 9), "oak"], [Rect2i(-6, -5, 8, 4), "oak"]],
		"partitions": [{"axis": "h", "at": -1, "from": -6, "to": 2, "gap": -4},
			{"axis": "v", "at": 2, "from": -5, "to": -1}],
		"props": [["bed", Vector2(-40, -24)], ["bed", Vector2(-16, -24)], ["bed", Vector2(8, -24)],
			["stove", Vector2(44, -32)], ["side_shelf_r", Vector2(53, -8)],
			["garlic", Vector2(28, -28)], ["table", Vector2(-20, 32)], ["table", Vector2(4, 32)],
			["table", Vector2(28, 32)], ["spear_rack", Vector2(53, 32)], ["table_work", Vector2(48, 12)]],
		"rugs": [[1, Vector2(0, 36)], [2, Vector2(-24, -12)]],
		"decor": [["frame_night", Vector2(-24, -44)], ["portrait_b", Vector2(40, -44)],
			["wall_swords", Vector2(8, -44)]],
		"windows": [[-48, 0], [24, 0]],
		"beds": [Vector2(-40, -24), Vector2(-16, -24), Vector2(8, -24)],
		"meals": [Vector2(-32, 24), Vector2(-8, 24), Vector2(16, 24)],
		"works": [Vector2(32, -16), Vector2(40, 24)],
	},
	"watch_house": {
		"floor": Rect2i(-7, -5, 14, 9), "wall": "stucco", "door_x": -48.0,
		"floors": [[Rect2i(-7, -5, 14, 9), "oak"], [Rect2i(3, -5, 4, 9), "parquet"]],
		"partitions": [{"axis": "v", "at": 2, "from": -5, "to": 4, "gap": 0}],
		"props": [["bed", Vector2(-40, -24)], ["bed", Vector2(-16, -24)],
			["crate", Vector2(-28, -28)], ["oven", Vector2(8, -32)], ["flour", Vector2(-4, -36)],
			["table_cloth", Vector2(-24, 16)], ["table_cloth", Vector2(-8, 16)],
			["spear_rack", Vector2(-53, 0)], ["bread", Vector2(4, 28)], ["bed", Vector2(40, -24)],
			["bed", Vector2(48, 8)], ["crate", Vector2(52, -28)], ["footstool", Vector2(36, 28)],
			["side_shelf_r_low", Vector2(53, 32)]],
		"rugs": [[4, Vector2(-16, 20)], [3, Vector2(40, -8)]],
		"decor": [["frame_bright", Vector2(-28, -44)], ["portrait", Vector2(40, -44)],
			["wall_swords", Vector2(-48, -44)], ["wall_rack", Vector2(24, -44)]],
		"windows": [[-48, 1], [-8, 1], [32, 2]],
		"beds": [Vector2(-40, -24), Vector2(-16, -24), Vector2(40, -24), Vector2(48, 8)],
		"meals": [Vector2(-24, 0), Vector2(0, 0), Vector2(-32, 24), Vector2(-8, 24)],
		"works": [Vector2(-40, -8), Vector2(8, -24)],
	},
	"rowan_farm": {
		"floor": Rect2i(-8, -5, 16, 11), "wall": "plank", "door_x": -48.0,
		"floors": [[Rect2i(-8, -5, 16, 11), "earth"], [Rect2i(-8, -5, 16, 4), "oak"]],
		"partitions": [{"axis": "h", "at": -1, "from": -8, "to": 8, "gap": 4}],
		"props": [["bed", Vector2(-56, -24)], ["bed", Vector2(-32, -24)], ["bed", Vector2(-8, -24)],
			["bed", Vector2(16, -24)], ["bed", Vector2(40, -24)], ["crate", Vector2(56, -28)],
			["table", Vector2(-16, 32)], ["table", Vector2(0, 32)], ["table", Vector2(16, 32)],
			["bed", Vector2(56, 24)], ["hay_bale", Vector2(-56, 16)], ["iron_stove", Vector2(56, 48)],
			["bucket", Vector2(-8, 46)], ["garlic", Vector2(28, 46)], ["flour", Vector2(8, 46)],
			["milk_can", Vector2(-60, 4)], ["chest", Vector2(40, 48)], ["stool", Vector2(52, 40)]],
		"rugs": [[0, Vector2(0, 36)], [4, Vector2(-20, -12)]],
		"decor": [["frame_sea", Vector2(-28, -44)], ["portrait_c", Vector2(24, -44)]],
		"windows": [[-48, 0], [0, 0], [48, 0]],
		"beds": [Vector2(-56, -24), Vector2(-32, -24), Vector2(-8, -24), Vector2(16, -24),
			Vector2(40, -24), Vector2(56, 24)],
		"meals": [Vector2(-24, 16), Vector2(0, 16), Vector2(24, 16), Vector2(-24, 40),
			Vector2(0, 40), Vector2(24, 40)],
		"works": [Vector2(40, 32)],
	},
	"school": {
		"floor": Rect2i(-9, -4, 17, 9), "wall": "stucco", "door_x": -64.0,
		"floors": [[Rect2i(-9, -4, 17, 9), "boards"], [Rect2i(-9, 1, 2, 4), "planks"],
			[Rect2i(-3, -4, 6, 2), "parquet"]],
		"partitions": [{"axis": "v", "at": -7, "from": 1, "to": 5}],
		"props": [["table_papers", Vector2(0, -24)], ["board", Vector2(-24, -24)],
			["bookcase_full", Vector2(24, -24)], ["bookcase", Vector2(40, -24)],
			["shelf_low_books", Vector2(-48, -24)], ["plant", Vector2(60, -24)],
			["bench", Vector2(-40, 0)], ["bench", Vector2(-40, 24)], ["bench", Vector2(-8, 0)],
			["bench", Vector2(-8, 24)], ["bench", Vector2(24, 0)], ["bench", Vector2(24, 24)],
			["bench", Vector2(56, 0)], ["bench", Vector2(56, 24)], ["stool_round", Vector2(-40, 7)],
			["stool_round", Vector2(-8, 7)], ["stool_round", Vector2(24, 7)],
			["stool_round", Vector2(56, 7)], ["stool_round", Vector2(-40, 31)],
			["stool_round", Vector2(-8, 31)], ["stool_round", Vector2(24, 31)],
			["stool_round", Vector2(56, 31)], ["chest", Vector2(-64, -24)],
			["plant_red", Vector2(8, 40)]],
		"rugs": [],
		"decor": [["portrait", Vector2(-8, -36)], ["frame_small", Vector2(56, -36)]],
		"windows": [[-64, 1], [8, 1], [48, 2]],
		"works": [Vector2(0, -16)],
		"seats": {"pupils": [Vector2(-40, 8), Vector2(-8, 8), Vector2(24, 8), Vector2(56, 8),
			Vector2(-40, 32), Vector2(-8, 32), Vector2(24, 32), Vector2(56, 32)]},
		"spots": {"teacher": Vector2(0, -16)},
	},
}

## The room plan for `job`, with anchors assigned to `residents` in the given household order.
static func create(job: String, seed_value: int, id: String,
		residents: Array[String] = []) -> Dictionary:
	var plan: Dictionary = BUILDINGS.get(job, {})
	if plan.is_empty():
		push_error("No interior plan for " + job)
		plan = BUILDINGS.alchemist
	var random := NpcRoutinePlan.random_for(seed_value, id + ":interior")
	var props: Array[Dictionary] = []
	for entry: Array in plan.props:
		props.append({"kind": entry[0], "foot": entry[1]})
	var rugs: Array[Dictionary] = []
	var shade: int = random.randi_range(0, RUG_REGIONS.size() - 1)
	for entry: Array in plan.rugs:
		rugs.append({"color": (int(entry[0]) + shade) % RUG_REGIONS.size(), "foot": entry[1]})
	var decor: Array[Dictionary] = []
	for entry: Array in plan.decor:
		decor.append({"kind": _picture(entry[0], random), "foot": entry[1]})
	var bed_list: Array = plan.get("beds", [])
	var meal_list: Array = plan.get("meals", [])
	var work_list: Array = plan.get("works", [])
	var beds: Dictionary = {}
	var meals: Dictionary = {}
	var works: Dictionary = {}
	for index: int in range(residents.size()):
		if index < bed_list.size():
			beds[residents[index]] = bed_list[index]
		if not meal_list.is_empty():
			meals[residents[index]] = meal_list[index % meal_list.size()]
		if not work_list.is_empty():
			works[residents[index]] = work_list[index % work_list.size()]
	var floor_area: Rect2i = plan.floor
	var work: Vector2 = work_list[0] if not work_list.is_empty() \
		else Vector2(plan.door_x, floor_area.end.y * 8 - 16)
	var layout: Dictionary = {"floor": floor_area, "wall": plan.wall, "door_x": plan.door_x,
		"floors": plan.floors, "partitions": plan.partitions, "props": props, "rugs": rugs,
		"decor": decor, "windows": plan.windows, "beds": beds, "meals": meals, "works": works,
		"work": work, "meal": meal_list[0] if not meal_list.is_empty() else work,
		"seats": plan.get("seats", {}), "spots": plan.get("spots", {})}
	if not residents.is_empty() and beds.has(residents[0]):
		layout.bed = beds[residents[0]]
	return layout

## Room-local collision rectangles of the furniture that blocks movement.
static func footprints(layout: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for item: Dictionary in layout.props:
		var footprint: Rect2 = PROPS[item.kind][2]
		if footprint.has_area():
			result.append(Rect2(item.foot - Vector2(footprint.size.x * 0.5, footprint.size.y),
				footprint.size))
	return result

## Room-local collision rectangles of the partition walls, leaving their doorways open.
static func partition_rects(layout: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for partition: Dictionary in layout.partitions:
		for span: Vector2i in partition_spans(partition):
			if partition.axis == "h":
				result.append(Rect2(span.x * 8, partition.at * 8, (span.y - span.x) * 8, 16))
			else:
				# The thin wall art sits 2..7 px into its column.
				result.append(Rect2(partition.at * 8 + 2, span.x * 8, 5, (span.y - span.x) * 8))
	return result

## The solid [start, end) cell spans of one partition.
static func partition_spans(partition: Dictionary) -> Array[Vector2i]:
	if not partition.has("gap"):
		return [Vector2i(partition["from"], partition["to"])]
	return [Vector2i(partition["from"], partition.gap),
		Vector2i(partition.gap + DOORWAY_CELLS, partition["to"])]

## Geometry problems of a room plan: overlapping or stray furniture, blocked doorways, and anchors
## a resident could not stand on. Reachability itself needs the room's navigation grid.
static func validate(layout: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var floor_rect := Rect2(Vector2(layout.floor.position) * 8, Vector2(layout.floor.size) * 8)
	var solids: Array[Rect2] = footprints(layout)
	var walls: Array[Rect2] = partition_rects(layout)
	var threshold := Rect2(layout.door_x - 12, floor_rect.end.y - 24, 24, 24)
	var doorways: Array[Rect2] = []
	for partition: Dictionary in layout.partitions:
		if partition.has("gap"):
			doorways.append(Rect2(partition.gap * 8, (partition.at - 1) * 8, 16, 32)
				if partition.axis == "h" else Rect2((partition.at - 1) * 8, partition.gap * 8, 24, 16))
	for index: int in range(solids.size()):
		var solid: Rect2 = solids[index]
		if not floor_rect.encloses(solid):
			problems.append("Furniture outside the floor at %s" % solid)
		for other: Rect2 in solids.slice(index + 1) + walls + doorways + [threshold]:
			if solid.intersects(other):
				problems.append("Furniture overlaps at %s and %s" % [solid, other])
	for item: Dictionary in layout.props:
		if not PROPS[item.kind][2].has_area():
			var spot := Rect2(item.foot - Vector2(3, 3), Vector2(6, 3))
			for solid: Rect2 in solids + doorways + [threshold]:
				if spot.intersects(solid):
					problems.append("Decoration %s blocks %s" % [item.kind, solid])
	var anchors: Array[Vector2] = []
	for bed: Vector2 in layout.beds.values():
		anchors.append(bed + Vector2(0, 8))
	anchors.append_array(layout.meals.values())
	anchors.append_array(layout.works.values())
	for seats: Array in layout.seats.values():
		anchors.append_array(seats)
	anchors.append_array(layout.spots.values())
	for anchor: Vector2 in anchors:
		if anchor != (anchor / 8).round() * 8:
			problems.append("Anchor off the navigation grid: %s" % anchor)
		for solid: Rect2 in solids + walls:
			if _distance(anchor, solid) < CLEARANCE:
				problems.append("Anchor %s is blocked by %s" % [anchor, solid])
	for group: Array in [layout.meals.values()] + layout.seats.values():
		for index: int in range(group.size()):
			for other: int in range(index + 1, group.size()):
				if group[index] != group[other] \
						and group[index].distance_to(group[other]) < TownNavigation.PERSONAL_SPACE:
					problems.append("Places closer than personal space: %s" % group[index])
	return problems

static func _distance(point: Vector2, rect: Rect2) -> float:
	return (point - point.clamp(rect.position, rect.end)).length()

static func _picture(kind: String, random: RandomNumberGenerator) -> String:
	for group: Array in WALL_PICTURES:
		if kind in group:
			return group[random.randi_range(0, group.size() - 1)]
	return kind
