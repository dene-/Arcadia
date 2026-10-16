@tool

class_name RegionTown
extends RefCounted

const TILES: TileSet = preload("res://game/resources/world/town_tileset.tres")
const COTTAGE_WALLS: TileMapPattern = preload("res://game/resources/world/cottage_walls_pattern.tres")
const COTTAGE_ROOF: TileMapPattern = preload("res://game/resources/world/cottage_roof_pattern.tres")
const NPC: PackedScene = preload("res://game/actors/npcs/base_npc.tscn")
const PROCEDURAL_PROFILE: GDScript = preload("res://game/world/life/npc_procedural_profile.gd")
## Perimeter fence lines, in terrain cells.
const FENCE_TOP: int = -34
const FENCE_BOTTOM: int = 50
const FENCE_LEFT: int = -46
const FENCE_RIGHT: int = 56
## Cemetery enclosure (terrain cells); its south side is the town fence.
const CEMETERY := Rect2i(-38, 28, 24, 22)
const CEMETERY_GATE: Array[int] = [44, 45, 46]
## Farm field (terrain cells), shared with the terrain's tilled ground.
const FIELD := Rect2i(36, 8, 20, 13)
## Fenced kitchen gardens behind the houses (terrain cells), tilled like the field.
const GARDENS: Array[Rect2i] = [Rect2i(-40, -31, 8, 5), Rect2i(-22, -31, 9, 5),
	Rect2i(-38, 8, 8, 6), Rect2i(17, 7, 10, 5)]
## Each trade's shop sign, standing in its dooryard beside the door (side -1 left, 1 right),
## and its yard props. Yard offsets are pixels from the door, placed by hand into the gaps
## beside each house so no prop stands on a street or a wall.
const SIGNS: Dictionary[String, Array] = {
	"alchemist": ["sign_potion", -1], "jeweller": ["sign_jewels", -1],
	"tailor": ["sign_board", -1], "blacksmith": ["sign_smith", -1], "cooker": ["sign_tavern", 1],
	"carpenter": ["sign_board", -1], "dyer": ["sign_board", -1], "butcher": ["sign_board", -1],
	"furrier": ["signpost", -1], "watch_house": ["sign_watch", -1],
}
const YARDS: Dictionary[String, Array] = {
	"alchemist": [["pot_white", Vector2(36, -2)], ["pot_green", Vector2(36, -14)]],
	"jeweller": [["crate", Vector2(28, -4)]],
	"tailor": [["spinning_wheel", Vector2(40, -6)], ["crate", Vector2(42, 6)]],
	"blacksmith": [["furnace", Vector2(42, -4)], ["anvil", Vector2(62, -2)],
		["quench", Vector2(78, -4)]],
	"cooker": [["crate", Vector2(52, -4)], ["bucket", Vector2(52, -16)]],
	"carpenter": [["sawhorse", Vector2(52, -8)], ["log", Vector2(44, -28)]],
	"dyer": [["trough", Vector2(32, -4)], ["bucket", Vector2(30, 8)], ["milk_can", Vector2(40, 8)]],
	"butcher": [["chest", Vector2(32, -4)], ["bucket", Vector2(30, 6)]],
	"furrier": [["bales", Vector2(40, -6)], ["crate", Vector2(36, -24)]],
	"voss_house": [["pot_red", Vector2(36, -4)], ["pot_green", Vector2(36, -18)]],
	"watch_house": [["spear_rack", Vector2(32, -4)]],
	"rowan_farm": [["haystack", Vector2(56, 0)], ["trough", Vector2(52, 16)],
		["bales", Vector2(-64, -24)]],
}
## Shade and fruit trees in yards and on the town's edges, in pixels.
const TREES: Array[Vector2] = [Vector2(-336, -192), Vector2(-48, -192), Vector2(288, -160),
	Vector2(352, -128), Vector2(288, 280), Vector2(384, 304), Vector2(160, 320),
	Vector2(240, 368), Vector2(96, 272), Vector2(-64, 256), Vector2(-352, 112)]
const NO_TILE := Vector2i(-1, -1)
## Two-tile door and window choices from the town tileset (top tile of each pair).
const DOORS: Array[Vector2i] = [Vector2i(31, 5), Vector2i(31, 8)]
const WINDOWS: Array[Vector2i] = [Vector2i(31, 11), Vector2i(33, 11), Vector2i(32, 14)]
const WALL_TINTS: Array[Color] = [Color.WHITE, Color(0.86, 0.9, 1), Color(1, 0.92, 0.8),
	Color(0.92, 0.88, 0.84)]
const ROOF_TINTS: Array[Color] = [Color.WHITE, Color(0.8, 0.62, 0.55), Color(0.7, 0.66, 0.72),
	Color(1, 0.8, 0.72), Color(0.62, 0.5, 0.45)]

var art := RegionArt.new()

func build(parent: Node2D, spawn_actors: bool, layout: RegionLayout) -> void:
	var population := TownPopulation.new()
	var save: NpcWorldSave
	if spawn_actors:
		save = parent.get_node("/root/NpcCognition").save_game
		population = save.population
	population.ensure_population(save.region_seed if save != null else 274415)
	var cemetery := TownCemetery.new()
	cemetery.name = "Cemetery"
	cemetery.residents.assign(population.people.keys())
	parent.add_child(cemetery)
	for index: int in range(RegionLayout.HOMES.size()):
		var home: Dictionary = RegionLayout.HOMES[index]
		var foot: Vector2 = Vector2(home.cell * 8)
		_house(parent, foot, index, layout)
		_workplace(parent, home.job, foot)
		var household: String = TownPopulation.FOUNDERS.get(home.job, home.job)
		var members: Array[String] = population.members_of(household)
		for member_index: int in range(members.size()):
			var id: String = members[member_index]
			var person: Dictionary = population.people[id]
			var data: NpcData
			if TownPopulation.FOUNDERS.values().has(id):
				data = load("res://game/resources/actors/humans/%s_npc_data.tres" % person.job).duplicate()
			else:
				data = NpcData.new()
				data.able_to_chat = true
				data.combat_layers = preload("res://game/resources/combat/combat_layers_default.tres")
				data.sprite_frames = TownResidentArt.frames_for(person)
				# Guards must be able to hold off a lone orc and, in pairs, a camp raid.
				data.max_health = 10 if person.job == "guard" else 3
				if person.job == "guard":
					data.attack_damage = 2
			data.profile = population.profile_for(id)
			data.roam_radius = 12.0
			var spawn := foot + Vector2((member_index % 3 - 1) * 12, 24 + (member_index / 3) * 12)
			if spawn_actors:
				if save.is_dead(StringName(id)):
					continue
				var temperament: Dictionary = save.life.personality_for(id, save.get_npc_seed())
				NpcTemperament.apply(data.profile, temperament)
				if not TownPopulation.FOUNDERS.values().has(id):
					PROCEDURAL_PROFILE.apply(data.profile, person, temperament)
				var npc: BaseNpc = NPC.instantiate()
				npc.name = id.to_pascal_case()
				npc.npc_data = data
				npc.position = spawn
				npc.add_to_group(&"town_residents")
				if person.job == "guard":
					npc.add_to_group(&"town_guards")
				parent.add_child(npc)
			else:
				RegionArt.actor_preview(parent, data, spawn, id)
	_square(parent)
	_farm(parent)
	_gardens(parent)
	_public_buildings(parent)
	_outbuildings(parent)
	_tavern(parent)
	for index: int in range(TREES.size()):
		art.prop(parent, "tree_fruit" if index % 3 == 0 else "tree", TREES[index], index % 2 == 1)
	# An orchard climbs the slope north of the eastern lanes.
	for row: int in range(2):
		for column: int in range(5):
			var cell := Vector2i(8 + column * 5 + row * 2, -31 + row * 4)
			art.prop(parent, "tree_fruit" if (row + column) % 2 == 0 else "tree",
				Vector2(cell * 8), column % 2 == 1)
	_fences(parent, layout)
	_greenery(parent, layout)

func _half_width(index: int) -> int:
	return 20 + _extra(index) * 4

func _extra(index: int) -> int:
	return RegionLayout.HOMES[index].extra

func _house(parent: Node2D, foot: Vector2, index: int, layout: RegionLayout) -> void:
	var front: Dictionary = {"door": DOORS[index % DOORS.size()],
		"window": WINDOWS[(index * 2 + 1) % WINDOWS.size()]}
	_building(parent, foot, _extra(index), "House%s" % index, index, front)
	# A potted plant by the door, on the side the shop sign leaves free.
	var job: String = RegionLayout.HOMES[index].job
	var side: int = -SIGNS[job][1] if SIGNS.has(job) else 1
	art.prop(parent, ["pot_red", "pot_green", "pot_white"][index % 3], foot + Vector2(side * 12, 6))
	# A flower bed at the wall corner, unless a street runs past it.
	var corner: Vector2 = foot + Vector2(-_half_width(index) - 6.0, -2.0)
	if not _on_road(layout, Vector2i((corner / 8.0).floor())):
		art.cover(parent, "flowers", corner)

## `front` picks the door and window tiles; a building without a door shows its back.
func _building(parent: Node2D, foot: Vector2, extra: int, building_name: String, tint: int,
		front: Dictionary) -> void:
	var house := Node2D.new()
	house.name = building_name
	house.position = foot
	parent.add_child(house)
	# Keep walls underneath transparent roof pixels, including the triangular gable.
	# Child order draws the roof over the walls; the whole house still sorts at its feet.
	_house_layer(house, "Walls", COTTAGE_WALLS, extra, front.get("door", NO_TILE),
		front.get("window", NO_TILE))
	_house_layer(house, "Roof", COTTAGE_ROOF, extra)
	# Lime washes and weathered tiles differ from house to house.
	house.get_node("Walls").modulate = WALL_TINTS[tint % WALL_TINTS.size()]
	house.get_node("Roof").modulate = ROOF_TINTS[(tint * 3 + 1) % ROOF_TINTS.size()]
	RegionArt.barrier(house, Vector2(0, -9), Vector2(40 + extra * 8, 18))

# The schoolhouse: a long pale building with a notice board, and the children's play
# green across its lane.
func _public_buildings(parent: Node2D) -> void:
	for building: Dictionary in RegionLayout.PUBLIC_BUILDINGS:
		var foot := Vector2(building.cell * 8)
		var half_width: int = 20 + int(building.extra) * 4
		_building(parent, foot, building.extra, String(building.id).to_pascal_case(), 0,
			{"door": DOORS[1], "window": WINDOWS[2]})
		art.prop(parent, "sign_board", foot + Vector2(-half_width + 6, 3))
		art.prop(parent, "pot_white", foot + Vector2(half_width - 4, 6))
	var green: Vector2 = RegionLayout.TOWN_PLACES.playground
	art.prop(parent, "bales", green + Vector2(-8, -14))
	art.prop(parent, "bale", green + Vector2(26, 10))
	art.prop(parent, "hay_bale", green + Vector2(24, -12))
	for flowers: Vector2 in [Vector2(-8, -12), Vector2(20, -10), Vector2(-20, 22), Vector2(10, 26)]:
		art.cover(parent, "flowers", green + flowers)

func _outbuildings(parent: Node2D) -> void:
	for index: int in range(RegionLayout.OUTBUILDINGS.size()):
		var building: Dictionary = RegionLayout.OUTBUILDINGS[index]
		_building(parent, Vector2(building.cell * 8), building.extra, "Outbuilding%s" % index,
			index + 5, {"window": WINDOWS[index % WINDOWS.size()]})

# The cook's house is Rekala's inn; its drinkers spill out onto the market place.
func _tavern(parent: Node2D) -> void:
	for home: Dictionary in RegionLayout.HOMES:
		if home.job != "cooker":
			continue
		var table: Vector2 = Vector2(home.cell * 8) + Vector2(-40, 26)
		art.prop(parent, "desk", table)
		art.prop(parent, "chair", table + Vector2(-12, 0))
		art.prop(parent, "chair", table + Vector2(12, 0), true)

## Builds the cottage walls or roof `extra` columns wider. Walls take a `door` (the top of
## a two-tile door, centred) and alternate `window`s along the ground floor; without a
## door the centre takes a window too, so the wall reads as the back of a house.
func _house_layer(house: Node2D, layer_name: String, source: TileMapPattern, extra: int,
		door: Vector2i = DOORS[0], window: Vector2i = NO_TILE) -> void:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = TILES
	var pattern := TileMapPattern.new()
	var middle: int = 3 + extra / 2
	for cell: Vector2i in source.get_used_cells():
		var target: Vector2i = cell + Vector2i(extra if cell.x > 3 else 0, 0)
		var repetitions: int = extra + 1 if cell.x == 3 else 1
		for offset: int in range(repetitions):
			var atlas_cell: Vector2i = source.get_cell_atlas_coords(cell)
			var column: int = target.x + offset
			if layer_name == "Walls" and cell.y >= 4 and column > 1 and column < 5 + extra:
				# The ground floor: plain stone unless a door or window is chosen here.
				atlas_cell = source.get_cell_atlas_coords(Vector2i(2, cell.y))
				var row := Vector2i(0, cell.y - 4)
				var odd: bool = absi(column - middle) % 2 == 1
				if column == middle and door != NO_TILE:
					atlas_cell = door + row
				elif window != NO_TILE and odd == (door != NO_TILE):
					atlas_cell = window + row
			pattern.set_cell(target + Vector2i(offset, 0), 0, atlas_cell, 0)
	layer.position = Vector2(-(COTTAGE_ROOF.get_size().x + extra) * 4, -48)
	layer.set_pattern(Vector2i.ZERO, pattern)
	house.add_child(layer)

func _workplace(parent: Node2D, job: String, foot: Vector2) -> void:
	if SIGNS.has(job):
		art.prop(parent, SIGNS[job][0], foot + Vector2(SIGNS[job][1] * 14, 10))
	for item: Array in YARDS.get(job, []):
		art.prop(parent, item[0], foot + item[1])

# A well on the cobbles, and trestle stalls around the market corner of the place.
func _square(parent: Node2D) -> void:
	art.prop(parent, "well", Vector2(32, 44))
	art.cover(parent, "flower_purple", Vector2(46, 46))
	art.cover(parent, "flowers", Vector2(16, 50))
	var market: Vector2 = RegionLayout.TOWN_PLACES.market
	for stall: Vector2 in [Vector2(-22, -2), Vector2(24, -12), Vector2(-28, 20)]:
		art.prop(parent, "desk", market + stall)
	art.prop(parent, "crate", market + Vector2(-30, 14))
	art.prop(parent, "chest", market + Vector2(30, -2))
	art.prop(parent, "bale", market + Vector2(-40, 20))
	art.prop(parent, "bucket", market + Vector2(-14, 22))
	art.prop(parent, "milk_can", market + Vector2(12, 22))

# Kitchen gardens: tilled beds of crops inside a rail fence (fenced in `_fences`).
func _gardens(parent: Node2D) -> void:
	for garden: Rect2i in GARDENS:
		for y: int in range(garden.position.y + 1, garden.end.y, 2):
			for x: int in range(garden.position.x + 1, garden.end.x - 1, 2):
				art.sprite(parent, RegionArt.FARM_TILES, Rect2i(8, 8, 8, 24),
					Vector2(x * 8, y * 8 + 8))

func _farm(parent: Node2D) -> void:
	var mill := AnimatedSprite2D.new()
	mill.centered = false
	mill.position = Vector2(424, -48)
	mill.sprite_frames = SpriteFrames.new()
	var texture: Texture2D = load(RegionArt.ROOT + "Minifantasy_TownsIIWindmillFrames.png")
	var frame_size := Vector2(texture.get_width() / 8.0, texture.get_height())
	var used: Rect2i = texture.get_image().get_region(Rect2i(Vector2i.ZERO, frame_size)).get_used_rect()
	mill.offset = Vector2(-frame_size.x * 0.5, -used.end.y).round()
	for index: int in range(2):
		var frame := AtlasTexture.new()
		frame.atlas = texture
		frame.region = Rect2(Vector2(index * frame_size.x, 0), frame_size)
		mill.sprite_frames.add_frame(&"default", frame)
	mill.sprite_frames.set_animation_speed(&"default", 2.0)
	parent.add_child(mill)
	mill.play()
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var base := CollisionPolygon2D.new()
	base.polygon = PackedVector2Array([Vector2(-18, -18), Vector2(18, -18),
		Vector2(18, -7), Vector2(12, 0), Vector2(-12, 0), Vector2(-18, -7)])
	body.add_child(base)
	mill.add_child(body)
	art.prop(parent, "bales", Vector2(392, -24))
	art.prop(parent, "hay_bale", Vector2(452, -20))
	for y: int in range(FIELD.position.y + 2, FIELD.end.y - 1, 3):
		for x: int in range(FIELD.position.x + 2, FIELD.end.x - 1, 2):
			art.sprite(parent, RegionArt.FARM_TILES, Rect2i(8, 8, 8, 24),
				Vector2(x * 8, y * 8))
	art.prop(parent, "scarecrow", Vector2(372, 118))
	art.prop(parent, "hay_bale", Vector2(364, 140))
	art.prop(parent, "hay_fork", Vector2(272, 152))
	art.prop(parent, "bale", Vector2(288, 186))
	art.prop(parent, "milk_can", Vector2(300, 188))

# Farm fencing rings the town, the cemetery and the field. Gaps open wherever a road
# crosses, and the river bank replaces the fence where the water swings close.
func _fences(parent: Node2D, layout: RegionLayout) -> void:
	var cells: Dictionary[Vector2i, bool] = {}
	RegionArt.fence_line(cells, Vector2i(FENCE_LEFT, FENCE_TOP), Vector2i(FENCE_RIGHT, FENCE_TOP))
	RegionArt.fence_line(cells, Vector2i(FENCE_LEFT, FENCE_BOTTOM),
		Vector2i(FENCE_RIGHT, FENCE_BOTTOM))
	RegionArt.fence_line(cells, Vector2i(FENCE_LEFT, FENCE_TOP), Vector2i(FENCE_LEFT, FENCE_BOTTOM))
	RegionArt.fence_line(cells, Vector2i(FENCE_RIGHT, FENCE_TOP),
		Vector2i(FENCE_RIGHT, FENCE_BOTTOM))
	var top_left := CEMETERY.position
	var bottom_right := CEMETERY.end - Vector2i.ONE
	RegionArt.fence_line(cells, top_left, Vector2i(bottom_right.x, top_left.y))
	RegionArt.fence_line(cells, top_left, Vector2i(top_left.x, bottom_right.y))
	RegionArt.fence_line(cells, Vector2i(bottom_right.x, top_left.y), bottom_right)
	RegionArt.fence_line(cells, Vector2i(FIELD.position.x - 1, FIELD.end.y + 1),
		Vector2i(FENCE_RIGHT, FIELD.end.y + 1))
	for row: int in CEMETERY_GATE:
		cells.erase(Vector2i(bottom_right.x, row))
	# Each kitchen garden has a one-rail gate in the middle of its southern side.
	for garden: Rect2i in GARDENS:
		var ring: Rect2i = garden.grow(1)
		var last: Vector2i = ring.end - Vector2i.ONE
		RegionArt.fence_line(cells, ring.position, Vector2i(last.x, ring.position.y))
		RegionArt.fence_line(cells, ring.position, Vector2i(ring.position.x, last.y))
		RegionArt.fence_line(cells, Vector2i(last.x, ring.position.y), last)
		RegionArt.fence_line(cells, Vector2i(ring.position.x, last.y), last)
		cells.erase(Vector2i(ring.get_center().x, last.y))
	for cell: Vector2i in cells.keys():
		if cell.x >= RegionLayout.river_left_at(cell.y) - 2 or _on_road(layout, cell):
			cells.erase(cell)
	art.fence(parent, cells)

func _on_road(layout: RegionLayout, cell: Vector2i) -> bool:
	for y: int in range(-1, 2):
		for x: int in range(-1, 2):
			if layout.roads.has(cell + Vector2i(x, y)):
				return true
	return false

# Small patches of grass and flowers break up the open lawns between houses. The town
# is authored, so its planting uses a fixed generator rather than the region seed.
func _greenery(parent: Node2D, layout: RegionLayout) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7151
	var names: Array[String] = ["sprouts", "sprouts", "weeds", "flower_red", "flower_purple",
		"flower_white", "flowers", "daisy", "weeds", "reeds"]
	var stone: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in layout.stone:
		stone[cell] = true
	var town := RegionLayout.TOWN
	for y: int in range(town.position.y + 2, town.end.y - 1):
		for x: int in range(town.position.x + 2, town.end.x - 1):
			if rng.randf() > 0.016:
				continue
			var first: String = names[rng.randi() % names.size()]
			for index: int in range(rng.randi_range(2, 5)):
				var cell := Vector2i(x + rng.randi_range(-2, 2), y + rng.randi_range(-1, 1))
				if _on_road(layout, cell) or stone.has(cell) or FIELD.grow(1).has_point(cell) \
					or _in_garden(cell):
					continue
				if _near_home(cell) or cell.x >= RegionLayout.river_left_at(cell.y) - 3:
					continue
				var plant: String = first if rng.randf() < 0.7 else names[rng.randi() % names.size()]
				art.cover(parent, plant, Vector2(cell * 8) + Vector2(4, 8), rng.randf() < 0.5)

func _near_home(cell: Vector2i) -> bool:
	for home: Dictionary in RegionLayout.HOMES:
		var offset: Vector2i = cell - home.cell
		if absi(offset.x) <= 10 and offset.y >= -7 and offset.y <= 5:
			return true
	return false

func _in_garden(cell: Vector2i) -> bool:
	for garden: Rect2i in GARDENS:
		if garden.grow(1).has_point(cell):
			return true
	return false
