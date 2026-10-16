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
## Shop front sign and the props around each trade's yard, by home job.
## Yard offsets are in pixels from the right of the house front.
const SIGNS: Dictionary[String, String] = {
	"alchemist": "sign_potion", "jeweller": "sign_jewels", "tailor": "sign_board",
	"blacksmith": "sign_smith", "cooker": "sign_tavern", "carpenter": "sign_board",
	"dyer": "sign_board", "butcher": "sign_board", "furrier": "signpost",
	"watch_house": "sign_watch",
}
const YARDS: Dictionary[String, Array] = {
	"alchemist": [["pot_red", Vector2(0, 6)], ["pot_white", Vector2(12, 6)],
		["pot_green", Vector2(6, 18)]],
	"jeweller": [["chest", Vector2(4, 8)], ["crate", Vector2(16, 18)]],
	"tailor": [["spinning_wheel", Vector2(6, 10)], ["crate", Vector2(-2, 24)]],
	"blacksmith": [["furnace", Vector2(10, 4)], ["anvil", Vector2(4, 24)],
		["quench", Vector2(22, 24)]],
	"cooker": [["crate", Vector2(0, 6)], ["chest", Vector2(10, 18)], ["bucket", Vector2(20, 8)]],
	"carpenter": [["sawhorse", Vector2(10, 8)], ["log", Vector2(6, 26)]],
	"dyer": [["trough", Vector2(6, 6)], ["bucket", Vector2(0, 18)],
		["milk_can", Vector2(12, 18)]],
	"butcher": [["chest", Vector2(4, 6)], ["bucket", Vector2(0, 18)], ["crate", Vector2(14, 18)]],
	"furrier": [["bales", Vector2(10, 6)], ["crate", Vector2(2, 20)]],
	"voss_house": [["pot_red", Vector2(0, 6)], ["pot_green", Vector2(10, 6)]],
	"watch_house": [["spear_rack", Vector2(0, 6)], ["weapon_bin", Vector2(12, 8)],
		["weapon_crate", Vector2(6, 26)]],
	"rowan_farm": [["haystack", Vector2(22, 8)], ["trough", Vector2(4, 26)],
		["bales", Vector2(26, 30)]],
}

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
		_house(parent, foot, index)
		_workplace(parent, home.job, foot, _half_width(index), layout)
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
	# The southern neighborhood has an outdoor lesson table and a small play green.
	for foot: Vector2 in [Vector2(112, 240), Vector2(144, 240)]:
		art.sprite(parent, RegionArt.TOWN, Rect2i(8, 224, 16, 16), foot, Rect2(2, 7, 12, 9))
	art.prop(parent, "sign_board", Vector2(128, 222))
	for foot: Vector2 in [Vector2(-128, 212), Vector2(-80, 212), Vector2(-104, 252)]:
		art.cover(parent, "flowers", foot)
	art.prop(parent, "bales", Vector2(-104, 206))
	for foot: Vector2 in [Vector2(-80, -160), Vector2(32, -174), Vector2(-90, 160),
		Vector2(184, -165), Vector2(-210, -70), Vector2(190, 100)]:
		art.prop(parent, "tree_fruit" if int(foot.x) % 3 == 0 else "tree", foot, foot.y > 0)
	# An orchard fills the northern lawn behind the western houses.
	for row: int in range(2):
		for column: int in range(6):
			var cell := Vector2i(-37 + column * 5 + row * 2, -29 + row * 5)
			art.prop(parent, "tree_fruit" if (row + column) % 2 == 0 else "tree",
				Vector2(cell * 8), column % 2 == 1)
	art.prop(parent, "bales", Vector2(-100, -212))
	art.prop(parent, "bucket", Vector2(-180, -200))
	_fences(parent, layout)
	_greenery(parent, layout)

func _half_width(index: int) -> int:
	return 20 + _extra(index) * 4

func _extra(index: int) -> int:
	return 4 if index in [4, 11] else (2 if index in [0, 2, 3, 5, 9, 10] else 0)

func _house(parent: Node2D, foot: Vector2, index: int) -> void:
	var house := Node2D.new()
	house.name = "House%s" % index
	house.position = foot
	parent.add_child(house)
	var extra: int = _extra(index)
	var colors: Array[Color] = [Color.WHITE, Color(0.72, 0.87, 1), Color(1, 0.88, 0.72)]
	house.modulate = colors[index % colors.size()]
	# Keep walls underneath transparent roof pixels, including the triangular gable.
	# Child order draws the roof over the walls; the whole house still sorts at its feet.
	_house_layer(house, "Walls", COTTAGE_WALLS, extra)
	_house_layer(house, "Roof", COTTAGE_ROOF, extra)
	RegionArt.barrier(house, Vector2(0, -9), Vector2(40 + extra * 8, 18))
	var side: float = _half_width(index) + 6.0
	art.cover(parent, "flowers", foot + Vector2(-side, -2))
	art.cover(parent, "bush", foot + Vector2(-side - 2, -12))

func _house_layer(house: Node2D, layer_name: String, source: TileMapPattern, extra: int) -> void:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = TILES
	var pattern := TileMapPattern.new()
	for cell: Vector2i in source.get_used_cells():
		var target: Vector2i = cell + Vector2i(extra if cell.x > 3 else 0, 0)
		var repetitions: int = extra + 1 if cell.x == 3 else 1
		for offset: int in range(repetitions):
			var atlas_cell: Vector2i = source.get_cell_atlas_coords(cell)
			if layer_name == "Walls" and cell.x == 3 and cell.y >= 4 and offset != extra / 2:
				atlas_cell = source.get_cell_atlas_coords(Vector2i(2, cell.y))
			pattern.set_cell(target + Vector2i(offset, 0), 0, atlas_cell, 0)
	layer.position = Vector2(-(COTTAGE_ROOF.get_size().x + extra) * 4, -48)
	layer.set_pattern(Vector2i.ZERO, pattern)
	house.add_child(layer)

# A shop sign stands by the door; trade props fill the yard to the right of the house,
# a full walker's width from the wall so the dooryard's side lane stays open.
# Props that would land on a street (rather than the house's own dooryard) are skipped.
func _workplace(parent: Node2D, job: String, foot: Vector2, half_width: int,
		layout: RegionLayout) -> void:
	if SIGNS.has(job):
		art.prop(parent, SIGNS[job], foot + Vector2(-half_width + 4, 14))
	var yard := Rect2i(Vector2i(foot / 8.0) + Vector2i(-3, 0), Vector2i(7, 4))
	for item: Array in YARDS.get(job, []):
		var spot: Vector2 = foot + Vector2(half_width + 16, 0) + item[1]
		var cell := Vector2i((spot / 8.0).floor())
		if layout.roads.has(cell) and not yard.has_point(cell):
			continue
		art.prop(parent, item[0], spot)

# Well, market stalls and planters give the square a civic centre.
func _square(parent: Node2D) -> void:
	art.prop(parent, "well", Vector2(0, 4))
	for corner: Vector2 in [Vector2(-64, -28), Vector2(72, -28), Vector2(-64, 100),
		Vector2(72, 100)]:
		art.prop(parent, "pot_red" if corner.y < 0 else "pot_white", corner)
	for side: float in [-1.0, 1.0]:
		art.cover(parent, "flowers", Vector2(side * 22, 2))
		art.cover(parent, "flower_purple", Vector2(side * 16, 14))
	# The market (TownLife place at (-48, 88)) keeps its centre free for shoppers.
	art.prop(parent, "sign_tavern", Vector2(-48, 64))
	art.prop(parent, "chest", Vector2(-66, 82))
	art.prop(parent, "crate", Vector2(-30, 82))
	art.prop(parent, "bale", Vector2(-66, 96))
	art.prop(parent, "sign_potion", Vector2(48, 64))
	art.prop(parent, "crate", Vector2(32, 82))
	art.prop(parent, "bucket", Vector2(64, 82))

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
				if _on_road(layout, cell) or stone.has(cell) or FIELD.grow(1).has_point(cell):
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
