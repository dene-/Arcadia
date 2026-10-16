@tool

class_name RegionArt
extends RefCounted

## Atlas regions use the original, unmodified 8px Minifantasy sheets.
## Every region is made of whole 8px cells and holds one complete sprite.
const ROOT: String = "res://assets/art/world_packs/"
const PLAINS: String = "Minifantasy_ForgottenPlainsProps.png"
const SWAMP: String = "Minifantasy_MurkySwampProps.png"
const TOWN: String = "Minifantasy_TownsProps.png"
const TOWN_II: String = "Minifantasy_TownsIIProps.png"
const FARM: String = "Minifantasy_FarmProps.png"
const FARM_TILES: String = "Minifantasy_FarmTileset.png"
const SMITH: String = "Minifantasy_CraftingAndProfessionsBlacksmithProps.png"
const TAILOR: String = "Minifantasy_CraftingAndProfessionsTailorProps.png"
const WOODWORK: String = "Minifantasy_CraftingAndProfessionsWoodworkProps.png"
const BRIDGE: String = "Minifantasy_TownsIIStoneBridgeTileset.png"
const SHADOWS: Dictionary[String, String] = {
	PLAINS: "Minifantasy_ForgottenPlainsPropsShadows.png",
	SWAMP: "Minifantasy_MurkySwampPropsShadows.png",
	TOWN: "Minifantasy_TownsPropsShadows.png",
}
## Named props: [sheet, region, collision footprint in region pixels or an empty Rect2].
const PROPS: Dictionary[String, Array] = {
	"well": [TOWN, Rect2i(8, 48, 24, 32), Rect2(7, 20, 12, 8)],
	"pot_red": [TOWN, Rect2i(32, 48, 16, 16), Rect2(5, 11, 7, 4)],
	"pot_white": [TOWN, Rect2i(48, 48, 8, 16), Rect2(1, 11, 6, 4)],
	"pot_green": [TOWN, Rect2i(56, 48, 8, 16), Rect2(2, 12, 4, 3)],
	"sign_tavern": [TOWN, Rect2i(8, 80, 24, 24), Rect2(4, 20, 16, 3)],
	"sign_potion": [TOWN, Rect2i(32, 80, 24, 24), Rect2(4, 20, 16, 3)],
	"sign_smith": [TOWN, Rect2i(56, 80, 24, 24), Rect2(4, 20, 16, 3)],
	"sign_watch": [TOWN, Rect2i(80, 80, 24, 24), Rect2(4, 20, 16, 3)],
	"sign_jewels": [TOWN, Rect2i(104, 88, 24, 16), Rect2(5, 12, 14, 3)],
	"desk": [TOWN, Rect2i(8, 224, 16, 16), Rect2(2, 7, 12, 9)],
	"chair": [TOWN, Rect2i(136, 224, 16, 16), Rect2(4, 10, 8, 5)],
	"sign_board": [TOWN, Rect2i(128, 88, 16, 16), Rect2(3, 12, 10, 3)],
	"signpost": [TOWN, Rect2i(144, 88, 16, 16), Rect2(5, 12, 6, 3)],
	"spear_rack": [TOWN, Rect2i(96, 120, 8, 24), Rect2(0, 19, 5, 4)],
	"weapon_bin": [TOWN, Rect2i(112, 120, 16, 24), Rect2(1, 15, 15, 4)],
	"weapon_crate": [TOWN, Rect2i(128, 128, 16, 16), Rect2(1, 11, 15, 5)],
	"furnace": [SMITH, Rect2i(32, 0, 32, 32), Rect2(7, 24, 18, 6)],
	"anvil": [SMITH, Rect2i(8, 16, 16, 16), Rect2(2, 6, 12, 4)],
	"quench": [SMITH, Rect2i(64, 16, 16, 16), Rect2(6, 6, 7, 4)],
	"spinning_wheel": [TAILOR, Rect2i(0, 8, 24, 16), Rect2(7, 12, 17, 4)],
	"sawhorse": [WOODWORK, Rect2i(128, 8, 32, 24), Rect2(7, 14, 21, 5)],
	"haystack": [FARM, Rect2i(8, 8, 40, 32), Rect2(4, 19, 32, 8)],
	"hay_bale": [FARM, Rect2i(56, 8, 16, 32), Rect2(2, 18, 12, 4)],
	"hay_fork": [FARM, Rect2i(80, 8, 24, 32), Rect2(4, 22, 16, 7)],
	"trough": [FARM, Rect2i(120, 24, 16, 8), Rect2(1, 3, 14, 4)],
	"chest": [FARM, Rect2i(120, 40, 16, 8), Rect2(0, 3, 16, 5)],
	"crate": [FARM, Rect2i(144, 40, 8, 8), Rect2(0, 2, 8, 5)],
	"bales": [FARM, Rect2i(16, 48, 32, 8), Rect2(0, 2, 32, 6)],
	"bale": [FARM, Rect2i(56, 48, 8, 8), Rect2(0, 3, 8, 5)],
	"scarecrow": [FARM, Rect2i(72, 48, 16, 16), Rect2(6, 12, 4, 3)],
	"bucket": [FARM, Rect2i(120, 56, 8, 8), Rect2()],
	"milk_can": [FARM, Rect2i(128, 56, 8, 8), Rect2()],
	"tree": [PLAINS, Rect2i(152, 0, 24, 32), Rect2(9, 21, 10, 7)],
	"tree_fruit": [PLAINS, Rect2i(152, 32, 24, 32), Rect2(9, 21, 10, 7)],
	"willow": [SWAMP, Rect2i(104, 120, 40, 48), Rect2(15, 38, 15, 8)],
	"standing_stone": [PLAINS, Rect2i(0, 0, 16, 32), Rect2(4, 23, 8, 5)],
	"standing_stone_b": [PLAINS, Rect2i(16, 0, 16, 32), Rect2(4, 23, 8, 5)],
	"standing_stone_c": [PLAINS, Rect2i(32, 0, 16, 32), Rect2(3, 23, 10, 5)],
	"menhir": [PLAINS, Rect2i(48, 8, 16, 24), Rect2(3, 16, 10, 5)],
	"grave_tall": [PLAINS, Rect2i(64, 16, 16, 16), Rect2(4, 9, 8, 4)],
	"grave_wide": [PLAINS, Rect2i(80, 16, 16, 16), Rect2(3, 9, 9, 4)],
	"grave_small": [PLAINS, Rect2i(96, 16, 16, 16), Rect2(3, 10, 9, 3)],
	"stone_slim": [PLAINS, Rect2i(112, 16, 16, 16), Rect2(5, 9, 6, 4)],
	"rubble": [PLAINS, Rect2i(0, 40, 56, 24), Rect2(8, 16, 38, 8)],
	"pillar": [PLAINS, Rect2i(64, 32, 8, 48), Rect2(0, 41, 8, 6)],
	"boulder": [SWAMP, Rect2i(80, 72, 16, 16), Rect2(1, 9, 14, 6)],
	"boulder_mossy": [SWAMP, Rect2i(80, 96, 16, 16), Rect2(1, 10, 14, 6)],
	"log": [SWAMP, Rect2i(56, 176, 16, 16), Rect2(2, 8, 12, 5)],
	"log_b": [SWAMP, Rect2i(80, 176, 16, 16), Rect2(2, 8, 12, 5)],
	"stump": [SWAMP, Rect2i(112, 176, 16, 16), Rect2(3, 8, 10, 6)],
	"snag": [SWAMP, Rect2i(8, 176, 16, 16), Rect2(5, 11, 6, 4)],
	"snag_b": [SWAMP, Rect2i(32, 176, 16, 16), Rect2(5, 11, 6, 4)],
}
## Low ground cover that never blocks movement: [sheet, region].
const GROUND_COVER: Dictionary[String, Array] = {
	"flowers": [PLAINS, Rect2i(72, 64, 24, 16)],
	"flower_red": [PLAINS, Rect2i(72, 72, 8, 8)],
	"flower_purple": [PLAINS, Rect2i(80, 72, 8, 8)],
	"flower_white": [PLAINS, Rect2i(88, 72, 8, 8)],
	"sprouts": [PLAINS, Rect2i(104, 72, 8, 8)],
	"reed": [PLAINS, Rect2i(112, 32, 8, 24)],
	"reeds": [PLAINS, Rect2i(120, 32, 16, 24)],
	"weeds": [PLAINS, Rect2i(96, 40, 16, 16)],
	"bush": [SWAMP, Rect2i(8, 8, 8, 8)],
	"bush_small": [SWAMP, Rect2i(24, 8, 8, 8)],
	"fern": [SWAMP, Rect2i(8, 32, 8, 8)],
	"fern_b": [SWAMP, Rect2i(24, 32, 8, 8)],
	"mushroom": [SWAMP, Rect2i(72, 8, 8, 8)],
	"daisy": [SWAMP, Rect2i(88, 8, 8, 8)],
	"pebble": [SWAMP, Rect2i(8, 80, 8, 8)],
	"pebbles": [SWAMP, Rect2i(56, 80, 16, 8)],
	"cattail": [SWAMP, Rect2i(8, 128, 8, 16)],
	"cattail_b": [SWAMP, Rect2i(24, 128, 8, 16)],
	"rush": [SWAMP, Rect2i(56, 128, 8, 16)],
}
## Farm fence cells (FarmTileset): a nine-slice enclosure plus a free-standing rail.
const FENCE_RAIL_LEFT := Vector2i(448, 120)
const FENCE_RAIL := Vector2i(408, 120)
const FENCE_RAIL_RIGHT := Vector2i(464, 120)
const FENCE_POST_TOP := Vector2i(0, 96)
const FENCE_POST := Vector2i(0, 104)
const FENCE_POST_BOTTOM := Vector2i(0, 112)
const FENCE_POST_COLUMNS: Array[int] = [400, 416, 432]
const FENCE_JOINTS: Dictionary[int, Vector2i] = {
	0b0110: Vector2i(400, 120), 0b1010: Vector2i(432, 120),
	0b0101: Vector2i(400, 152), 0b1001: Vector2i(432, 152),
	0b1110: Vector2i(416, 120), 0b1101: Vector2i(416, 152),
	0b0111: Vector2i(400, 136), 0b1011: Vector2i(432, 136), 0b1111: Vector2i(416, 136),
}

var _textures: Dictionary[String, Texture2D] = {}
var _offsets: Dictionary[String, Vector2] = {}
var _shadowed: Dictionary[String, bool] = {}

func available() -> bool:
	for sheet: String in [PLAINS, SWAMP, TOWN, TOWN_II, FARM, FARM_TILES, SMITH, TAILOR,
		WOODWORK, BRIDGE, "Minifantasy_TownsIIStuccoBuildingIndoorTileset.png",
		"Minifantasy_ForgottenPlainsPropsShadows.png", "Minifantasy_MurkySwampPropsShadows.png",
		"Minifantasy_TownsPropsShadows.png", "Minifantasy_MurkySwampGrassToGrass.png",
		"Minifantasy_TownsIIWindmillFrames.png"]:
		if not ResourceLoader.exists(ROOT + sheet):
			return false
	return true

func texture(sheet: String) -> Texture2D:
	if not _textures.has(sheet):
		_textures[sheet] = load(ROOT + sheet)
	return _textures[sheet]

func sprite(parent: Node2D, sheet: String, region: Rect2i, foot: Vector2,
		footprint: Rect2 = Rect2()) -> Sprite2D:
	var prop := Sprite2D.new()
	prop.centered = false
	prop.texture = texture(sheet)
	prop.region_enabled = true
	prop.region_rect = region
	prop.position = foot
	var key: String = sheet + str(region)
	if not _offsets.has(key):
		var used: Rect2i = prop.texture.get_image().get_region(region).get_used_rect()
		_offsets[key] = Vector2(-region.size.x * 0.5, -used.end.y).round()
	prop.offset = _offsets[key]
	if footprint.has_area():
		# Art and collision share an authored anchor at the bottom of the footprint.
		var anchor := Vector2(footprint.get_center().x, footprint.end.y)
		# Integer texture origins avoid texel sampling wobble on odd-width footprints.
		# Only the drawing is aligned; physics keeps the exact authored footprint.
		prop.offset = -anchor.round()
	parent.add_child(prop)
	if footprint.has_area():
		barrier(prop, Vector2(0, -footprint.size.y * 0.5), footprint.size)
	return prop

## A catalogued prop with its collision and, when the pack draws one, its cast shadow.
func prop(parent: Node2D, prop_name: String, foot: Vector2, mirrored: bool = false) -> Sprite2D:
	var entry: Array = PROPS[prop_name]
	var art: Sprite2D = sprite(parent, entry[0], entry[1], foot, entry[2])
	art.name = prop_name.to_pascal_case()
	# Mirroring keeps the footprint centred: the anchor lies on the footprint's centre line.
	if mirrored:
		art.flip_h = true
		art.offset.x = -art.offset.x - entry[1].size.x
	_add_shadow(parent, art, entry[0], entry[1])
	return art

## Ground cover drawn beneath actors, without collision.
func cover(parent: Node2D, cover_name: String, foot: Vector2, mirrored: bool = false) -> Sprite2D:
	var entry: Array = GROUND_COVER[cover_name]
	var art: Sprite2D = decoration(parent, entry[0], entry[1], foot)
	if mirrored:
		art.flip_h = true
		art.offset.x = -art.offset.x - entry[1].size.x
	return art

func decoration(parent: Node2D, sheet: String, region: Rect2i, foot: Vector2) -> Sprite2D:
	var art: Sprite2D = sprite(parent, sheet, region, foot)
	art.z_index = -3
	return art

## One 8px cell drawn with its bottom edge on `cell`'s bottom edge, so it sorts like a prop.
func tile(parent: Node2D, sheet: String, atlas: Vector2i, cell: Vector2i) -> Sprite2D:
	var art := Sprite2D.new()
	art.centered = false
	art.texture = texture(sheet)
	art.region_enabled = true
	art.region_rect = Rect2(atlas, Vector2(8, 8))
	art.position = Vector2(cell.x * 8, cell.y * 8 + 8)
	art.offset = Vector2(0, -8)
	parent.add_child(art)
	return art

## Wooden farm fencing along `cells` (8px terrain cells). Joints, corners and rail ends
## follow the neighbouring cells; straight runs share one collision strip each.
func fence(parent: Node2D, cells: Dictionary[Vector2i, bool]) -> void:
	var runs := Node2D.new()
	runs.name = "Fence"
	runs.y_sort_enabled = true
	parent.add_child(runs)
	for cell: Vector2i in cells:
		var left: bool = cells.has(cell + Vector2i.LEFT)
		var right: bool = cells.has(cell + Vector2i.RIGHT)
		var up: bool = cells.has(cell + Vector2i.UP)
		var down: bool = cells.has(cell + Vector2i.DOWN)
		var mask: int = int(left) << 3 | int(right) << 2 | int(up) << 1 | int(down)
		var atlas: Vector2i
		if FENCE_JOINTS.has(mask):
			atlas = FENCE_JOINTS[mask]
		elif up or down:
			var column: int = _fence_column(cells, cell)
			var row: Vector2i = FENCE_POST
			if not up:
				row = FENCE_POST_TOP
			elif not down:
				row = FENCE_POST_BOTTOM
			atlas = Vector2i(column, row.y)
		elif left and right:
			atlas = FENCE_RAIL
		elif right:
			atlas = FENCE_RAIL_LEFT
		else:
			atlas = FENCE_RAIL_RIGHT
		tile(runs, FARM_TILES, atlas, cell)
		# Horizontal collision covers the rail's base; vertical posts block their own column.
		if left or right or not (up or down):
			if not left:
				var end: Vector2i = cell
				while cells.has(end + Vector2i.RIGHT):
					end += Vector2i.RIGHT
				barrier(runs, Vector2((cell.x + end.x + 1) * 4.0, cell.y * 8 + 5.5),
					Vector2((end.x - cell.x + 1) * 8, 5))
		if (up or down) and not up:
			var bottom: Vector2i = cell
			while cells.has(bottom + Vector2i.DOWN):
				bottom += Vector2i.DOWN
			barrier(runs, Vector2(cell.x * 8 + 4, (cell.y + bottom.y + 1) * 4.0),
				Vector2(5, (bottom.y - cell.y + 1) * 8))

static func fence_line(cells: Dictionary[Vector2i, bool], from: Vector2i, to: Vector2i) -> void:
	var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	var cell: Vector2i = from
	cells[cell] = true
	while cell != to:
		cell += step
		cells[cell] = true

## Editor-only art preview. No AI, physics, persistence, or provider calls.
static func actor_preview(parent: Node2D, data: NpcData, foot: Vector2, label: String) -> void:
	var frames: SpriteFrames = data.sprite_frames
	if frames is ActorSpriteFrames:
		frames.ensure_built()
	var preview := AnimatedSprite2D.new()
	preview.name = label + "Preview"
	preview.position = foot
	preview.sprite_frames = frames
	preview.animation = &"idle"
	parent.add_child(preview)

static func barrier(parent: Node2D, center: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body

# Vertical posts align with the joint they hang from: left sides, middles or right sides.
func _fence_column(cells: Dictionary[Vector2i, bool], cell: Vector2i) -> int:
	for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN]:
		var probe: Vector2i = cell
		while cells.has(probe):
			var left: bool = cells.has(probe + Vector2i.LEFT)
			var right: bool = cells.has(probe + Vector2i.RIGHT)
			if left and right:
				return FENCE_POST_COLUMNS[1]
			if left:
				return FENCE_POST_COLUMNS[2]
			if right:
				return FENCE_POST_COLUMNS[0]
			probe += direction
	return FENCE_POST_COLUMNS[0]

func _add_shadow(parent: Node2D, art: Sprite2D, sheet: String, region: Rect2i) -> void:
	if not SHADOWS.has(sheet):
		return
	var key: String = sheet + str(region)
	if not _shadowed.has(key):
		var image: Image = texture(SHADOWS[sheet]).get_image()
		_shadowed[key] = image.get_region(region).get_used_rect().has_area()
	if not _shadowed[key]:
		return
	var shadow := Sprite2D.new()
	shadow.centered = false
	shadow.texture = texture(SHADOWS[sheet])
	shadow.region_enabled = true
	shadow.region_rect = region
	shadow.position = art.position
	shadow.offset = art.offset
	shadow.flip_h = art.flip_h
	shadow.z_index = -2
	parent.add_child(shadow)
