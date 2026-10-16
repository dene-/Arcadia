@tool

class_name RegionTerrain
extends RefCounted

## Terrain transitions and reusable patterns are separate from placement rules.
const PLAINS: TileSet = preload("res://game/resources/world/plains_tileset.tres")
const TILE_TEXTURE: Texture2D = preload("res://assets/art/tilesets/forgotten_plains/Minifantasy_ForgottenPlainsTiles.png")

func build(parent: Node2D, layout: RegionLayout) -> void:
	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = PLAINS
	ground.z_index = -10
	parent.add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = layout.region_seed
	for y: int in range(RegionLayout.BOUNDS.position.y, RegionLayout.BOUNDS.end.y):
		for x: int in range(RegionLayout.BOUNDS.position.x, RegionLayout.BOUNDS.end.x):
			ground.set_cell(Vector2i(x, y), 1, Vector2i(rng.randi_range(1, 4), 1))
	var roads: Array[Vector2i] = []
	roads.assign(layout.roads.keys())
	var field: Rect2i = RegionTown.FIELD
	for y: int in range(field.position.y, field.end.y):
		for x: int in range(field.position.x, field.end.x):
			roads.append(Vector2i(x, y))
	ground.set_cells_terrain_connect(roads, 0, 0)
	ground.set_cells_terrain_connect(layout.stone, 0, 2)
	_build_swamp(parent, layout)
	_build_river(parent, layout)
	_build_boundary(parent)

func _build_swamp(parent: Node2D, layout: RegionLayout) -> void:
	var swamp := TileMapLayer.new()
	swamp.name = "WetGrass"
	swamp.z_index = -9
	swamp.tile_set = TileSet.new()
	swamp.tile_set.tile_size = Vector2i(8, 8)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = load(RegionArt.ROOT + "Minifantasy_MurkySwampGrassToGrass.png")
	atlas.texture_region_size = Vector2i(8, 8)
	for y: int in range(3):
		for x: int in range(3):
			atlas.create_tile(Vector2i(x, y))
	swamp.tile_set.add_source(atlas, 0)
	parent.add_child(swamp)
	# A broad continuous biome with rounded, staggered borders; paths remain exposed.
	var cells: Dictionary[Vector2i, bool] = {}
	for y: int in range(26, RegionLayout.BOUNDS.end.y):
		for x: int in range(68, RegionLayout.BOUNDS.end.x):
			var cell := Vector2i(x, y)
			if RegionLayout.is_swamp(cell) and not layout.roads.has(cell):
				cells[cell] = true
	for cell: Vector2i in cells:
		var tx: int = 1
		var ty: int = 1
		if not cells.has(cell + Vector2i.LEFT): tx = 0
		elif not cells.has(cell + Vector2i.RIGHT): tx = 2
		if not cells.has(cell + Vector2i.UP): ty = 0
		elif not cells.has(cell + Vector2i.DOWN): ty = 2
		swamp.set_cell(cell, 0, Vector2i(tx, ty))

func _build_river(parent: Node2D, layout: RegionLayout) -> void:
	var water := TileMapLayer.new()
	water.name = "River"
	water.z_index = -8
	water.tile_set = TileSet.new()
	water.tile_set.tile_size = Vector2i(8, 8)
	water.tile_set.add_terrain_set()
	water.tile_set.add_terrain(0)
	water.tile_set.set_terrain_name(0, 0, "Water")
	water.tile_set.add_terrain(0)
	water.tile_set.set_terrain_name(0, 1, "Grass")
	var atlas := TileSetAtlasSource.new()
	atlas.texture = TILE_TEXTURE
	atlas.texture_region_size = Vector2i(8, 8)
	water.tile_set.add_source(atlas, 0)
	var original: TileSetAtlasSource = PLAINS.get_source(1)
	atlas.create_tile(Vector2i(1, 1))
	_copy_terrain(original.get_tile_data(Vector2i(1, 1), 0), atlas.get_tile_data(Vector2i(1, 1), 0))
	# The pack's water and dirt shores share the same corner/side layout.
	for y: int in range(3, 8):
		for x: int in range(25, 28):
			var cell := Vector2i(x, y)
			atlas.create_tile(cell)
			_copy_terrain(original.get_tile_data(Vector2i(x - 18, y), 0), atlas.get_tile_data(cell, 0))
			atlas.set_tile_animation_columns(cell, 2)
			atlas.set_tile_animation_separation(cell, Vector2i(3, 0))
			atlas.set_tile_animation_frames_count(cell, 2)
			atlas.set_tile_animation_speed(cell, 2.0)
	parent.add_child(water)
	var cells: Array[Vector2i] = []
	for y: int in range(RegionLayout.BOUNDS.position.y, RegionLayout.BOUNDS.end.y):
		var left: int = RegionLayout.river_left_at(y)
		for x: int in range(left - 2, left + 11):
			water.set_cell(Vector2i(x, y), 0, Vector2i(1, 1))
			if layout.is_water(Vector2i(x, y)):
				cells.append(Vector2i(x, y))
		if not layout.is_bridge(Vector2i(left, y)):
			RegionArt.barrier(parent, Vector2((left + 4.5) * 8, y * 8 + 4), Vector2(56, 8))
	water.set_cells_terrain_connect(cells, 0, 0)
	for bridge: int in RegionLayout.BRIDGES:
		_build_bridge(parent, bridge)

func _copy_terrain(source: TileData, target: TileData) -> void:
	target.terrain_set = 0
	target.terrain = source.terrain
	for bit: int in [0, 3, 4, 7, 8, 11, 12, 15]:
		target.set_terrain_peering_bit(bit, source.get_terrain_peering_bit(bit))

## The pack's arched stone bridge spans the 13-cell river corridor exactly. The deck is
## the three rows around `row`; the front parapet is drawn in front of walkers.
func _build_bridge(parent: Node2D, row: int) -> void:
	var left: int = RegionLayout.river_left_at(row)
	var art := RegionArt.new()
	var origin := Vector2((left - 2) * 8, (row - 2) * 8)
	var bridge := Sprite2D.new()
	bridge.name = "Bridge%s" % row
	bridge.centered = false
	bridge.texture = art.texture(RegionArt.BRIDGE)
	bridge.region_enabled = true
	bridge.region_rect = Rect2(104, 8, 104, 48)
	bridge.position = origin
	bridge.z_index = -7
	parent.add_child(bridge)
	var parapet := Sprite2D.new()
	parapet.name = "Parapet%s" % row
	parapet.centered = false
	parapet.texture = bridge.texture
	parapet.region_enabled = true
	parapet.region_rect = Rect2(104, 32, 104, 8)
	parapet.position = origin + Vector2(0, 32)
	parapet.offset = Vector2(0, -8)
	parent.add_child(parapet)
	# The river barrier closes the rows beyond the deck; this closes the parapet itself.
	RegionArt.barrier(parent, Vector2((left + 4.5) * 8, row * 8 + 14), Vector2(72, 4))
	RegionArt.barrier(parent, Vector2((left + 4.5) * 8, row * 8 - 10), Vector2(72, 4))

func _build_boundary(parent: Node2D) -> void:
	var bounds := Rect2(RegionLayout.BOUNDS.position * 8, RegionLayout.BOUNDS.size * 8)
	RegionArt.barrier(parent, Vector2(bounds.position.x - 4, 0), Vector2(8, bounds.size.y))
	RegionArt.barrier(parent, Vector2(bounds.end.x + 4, 0), Vector2(8, bounds.size.y))
	RegionArt.barrier(parent, Vector2(0, bounds.position.y - 4), Vector2(bounds.size.x, 8))
	RegionArt.barrier(parent, Vector2(0, bounds.end.y + 4), Vector2(bounds.size.x, 8))
