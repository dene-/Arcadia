@tool

class_name RegionTown
extends RefCounted

const TILES: TileSet = preload("res://game/resources/world/town_tileset.tres")
const COTTAGE: TileMapPattern = preload("res://game/resources/world/cottage_pattern.tres")
const NPC: PackedScene = preload("res://game/actors/npcs/base_npc.tscn")
var art := RegionArt.new()

func build(parent: Node2D, spawn_actors: bool) -> void:
	for index: int in range(RegionLayout.HOMES.size()):
		var home: Dictionary = RegionLayout.HOMES[index]
		var foot: Vector2 = Vector2(home.cell * 8)
		_house(parent, foot, index)
		_workplace(parent, home.job, foot)
		if spawn_actors:
			var npc: BaseNpc = NPC.instantiate()
			npc.name = String(home.job).capitalize()
			npc.npc_data = load("res://game/resources/actors/humans/%s_npc_data.tres" % home.job).duplicate()
			npc.npc_data.roam_radius = 12.0
			npc.position = foot + Vector2(0, 24)
			parent.add_child(npc)
	# Well, stalls, seating and lamps give the square a civic centre.
	art.sprite(parent, RegionArt.TOWN, Rect2i(8, 48, 24, 32), Vector2(0, 4), Vector2(12, 8))
	for x: int in [-48, 48]:
		art.sprite(parent, RegionArt.TOWN, Rect2i(8, 88, 24, 16), Vector2(x, 64), Vector2(16, 6))
		art.sprite(parent, RegionArt.TOWN_II, Rect2i(168, 8, 8, 16), Vector2(x, -28))
		art.sprite(parent, RegionArt.PLAINS, Rect2i(72, 64, 24, 16), Vector2(x, 0))
	_farm(parent)
	for foot: Vector2 in [Vector2(-80, -160), Vector2(32, -174), Vector2(-90, 160),
		Vector2(184, -165), Vector2(-210, -70), Vector2(190, 100)]:
		art.sprite(parent, RegionArt.PLAINS, Rect2i(152, 0, 24, 32), foot, Vector2(5, 5))
	# Broken perimeter fencing leaves generous road entrances.
	for y: int in [-24, 25]:
		for x: int in range(-30, 31, 3):
			if absi(x) < 5: continue
			art.sprite(parent, RegionArt.TOWN_II, Rect2i(8, 8, 24, 8),
				Vector2(x * 8, y * 8), Vector2(22, 3))
	for x: int in [-30, 30]:
		for y: int in range(-20, 23, 3):
			if absi(y - 4) < 5: continue
			art.sprite(parent, RegionArt.TOWN_II, Rect2i(40, 8, 8, 24),
				Vector2(x * 8, y * 8), Vector2(3, 22))

func _house(parent: Node2D, foot: Vector2, index: int) -> void:
	var house := Node2D.new()
	house.name = "House%s" % index
	house.position = foot
	parent.add_child(house)
	var walls := TileMapLayer.new()
	walls.tile_set = TILES
	var extra: int = 4 if index == 4 else (2 if index in [0, 3, 5] else 0)
	var pattern := TileMapPattern.new()
	for cell: Vector2i in COTTAGE.get_used_cells():
		var target: Vector2i = cell + Vector2i(extra if cell.x > 3 else 0, 0)
		var repetitions: int = extra + 1 if cell.x == 3 else 1
		for offset: int in range(repetitions):
			var atlas_cell: Vector2i = COTTAGE.get_cell_atlas_coords(cell)
			if cell.x == 3 and cell.y >= 4 and offset != extra / 2:
				atlas_cell = COTTAGE.get_cell_atlas_coords(Vector2i(2, cell.y))
			pattern.set_cell(target + Vector2i(offset, 0), 0, atlas_cell, 0)
	walls.position = Vector2(-pattern.get_size().x * 4, -48)
	walls.set_pattern(Vector2i.ZERO, pattern)
	var colors: Array[Color] = [Color.WHITE, Color(0.72, 0.87, 1), Color(1, 0.88, 0.72)]
	walls.modulate = colors[index % colors.size()]
	house.add_child(walls)
	RegionArt.barrier(house, Vector2(0, -9), Vector2(40 + extra * 8, 18))
	art.sprite(parent, RegionArt.PLAINS, Rect2i(72, 64, 24, 16), foot + Vector2(-35, -4))

func _workplace(parent: Node2D, job: String, foot: Vector2) -> void:
	var sheet: String = RegionArt.TOWN
	var region := Rect2i(32, 88, 24, 16)
	match job:
		"blacksmith":
			sheet = "Minifantasy_CraftingAndProfessionsBlacksmithProps.png"
			region = Rect2i(40, 8, 24, 32)
		"carpenter":
			sheet = "Minifantasy_CraftingAndProfessionsWoodworkProps.png"
			region = Rect2i(8, 8, 32, 24)
		"tailor", "dyer":
			sheet = "Minifantasy_CraftingAndProfessionsTailorProps.png"
			region = Rect2i(8, 8, 24, 24)
		"furrier", "butcher":
			sheet = RegionArt.FARM
			region = Rect2i(8, 8, 40, 32)
	art.sprite(parent, sheet, region, foot + Vector2(36, 12), Vector2(12, 6))
	art.sprite(parent, RegionArt.TOWN_II, Rect2i(80, 8, 8, 8), foot + Vector2(-27, 11))

func _farm(parent: Node2D) -> void:
	var mill := AnimatedSprite2D.new()
	mill.position = Vector2(424, -48)
	mill.sprite_frames = SpriteFrames.new()
	var texture: Texture2D = load(RegionArt.ROOT + "Minifantasy_TownsIIWindmillFrames.png")
	var frame_size := Vector2(texture.get_width() / 8.0, texture.get_height())
	var used: Rect2i = texture.get_image().get_region(Rect2i(Vector2i.ZERO, frame_size)).get_used_rect()
	mill.offset = Vector2(0, frame_size.y * 0.5 - used.end.y)
	for index: int in range(2):
		var frame := AtlasTexture.new()
		frame.atlas = texture
		frame.region = Rect2(Vector2(index * frame_size.x, 0), frame_size)
		mill.sprite_frames.add_frame(&"default", frame)
	mill.sprite_frames.set_animation_speed(&"default", 2.0)
	parent.add_child(mill)
	mill.play()
	RegionArt.barrier(mill, Vector2(0, -8), Vector2(20, 16))
	for y: int in range(10, 20, 3):
		for x: int in range(38, 55, 2):
			art.sprite(parent, "Minifantasy_FarmTileset.png", Rect2i(8, 8, 8, 24),
				Vector2(x * 8, y * 8))
	for x: int in range(36, 57, 3):
		art.sprite(parent, RegionArt.TOWN_II, Rect2i(8, 8, 24, 8),
			Vector2(x * 8, 22 * 8), Vector2(22, 3))
	art.sprite(parent, RegionArt.FARM, Rect2i(56, 8, 16, 32), Vector2(364, 140))
	art.sprite(parent, RegionArt.FARM, Rect2i(80, 8, 24, 32), Vector2(280, 152), Vector2(16, 8))
