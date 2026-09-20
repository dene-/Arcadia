extends "res://tests/test_case.gd"

func test_saved_seed_reproduces_layout_and_generation_does_not_accumulate() -> void:
	var first := RegionLayout.new()
	var second := RegionLayout.new()
	first.generate(274415)
	second.generate(274415)
	assert_eq(first.trees, second.trees)
	assert_eq(first.details, second.details)
	assert_eq(first.enemies, second.enemies)
	first.generate(274415)
	assert_eq(first.trees, second.trees)
	second.generate(731)
	assert_ne(first.trees, second.trees)
	assert_eq(first.roads, second.roads, "Town, roads and landmarks must remain authored.")

func test_forest_placement_keeps_routes_town_water_and_encounters_clear() -> void:
	for world_seed: int in [1, 274415, 2147483646]:
		var layout := RegionLayout.new()
		layout.generate(world_seed)
		assert_true(layout.trees.size() > 2000)
		assert_eq(layout.enemies.size(), 27)
		for tree: Dictionary in layout.trees:
			assert_true(RegionLayout.BOUNDS.has_point(tree.cell))
			assert_false(layout.is_reserved(tree.cell, 3))
		for spawn: Dictionary in layout.enemies:
			assert_false(RegionLayout.TOWN.grow(20).has_point(spawn.cell))
			assert_false(layout.is_water(spawn.cell))
			assert_true(layout.roads.has(spawn.cell))

func test_roads_reach_every_home_camp_and_crossing_without_entering_water() -> void:
	var layout := RegionLayout.new()
	layout.generate(274415)
	var visited: Dictionary[Vector2i, bool] = {Vector2i(0, 4): true}
	var queue: Array[Vector2i] = [Vector2i(0, 4)]
	var index: int = 0
	while index < queue.size():
		var cell: Vector2i = queue[index]
		index += 1
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + direction
			if visited.has(next) or not layout.roads.has(next): continue
			if layout.is_water(next) and not layout.is_bridge(next): continue
			visited[next] = true
			queue.append(next)
	for camp: Vector2i in RegionLayout.CAMPS:
		assert_true(visited.has(camp), "Unreachable encounter: %s" % camp)
	for home: Dictionary in RegionLayout.HOMES:
		assert_true(visited.has(home.cell + Vector2i(0, 3)), "Unreachable home: %s" % home.job)
	for row: int in RegionLayout.BRIDGES:
		assert_true(visited.has(Vector2i(RegionLayout.river_left_at(row) + 4, row)))

func test_cottage_patterns_reference_real_tiles_and_visible_alternatives() -> void:
	var tiles: TileSet = load("res://game/resources/world/town_tileset.tres")
	for pattern: TileMapPattern in [RegionTown.COTTAGE_WALLS, RegionTown.COTTAGE_ROOF]:
		assert_false(pattern.is_empty())
		for cell: Vector2i in pattern.get_used_cells():
			var source: TileSetAtlasSource = tiles.get_source(pattern.get_cell_source_id(cell))
			var coords: Vector2i = pattern.get_cell_atlas_coords(cell)
			assert_true(source.has_tile(coords))
			assert_true(source.has_alternative_tile(coords, pattern.get_cell_alternative_tile(cell)))

func test_every_house_width_keeps_opaque_walls_beneath_the_roof_gable() -> void:
	var town := RegionTown.new()
	var atlas: TileSetAtlasSource = RegionTown.TILES.get_source(0)
	var image: Image = atlas.texture.get_image()
	for extra: int in [0, 2, 4]:
		var house := Node2D.new()
		town._house_layer(house, "Walls", RegionTown.COTTAGE_WALLS, extra)
		town._house_layer(house, "Roof", RegionTown.COTTAGE_ROOF, extra)
		var walls: TileMapLayer = house.get_node("Walls")
		var roof: TileMapLayer = house.get_node("Roof")
		assert_eq(walls.position, roof.position)
		# These pixels exposed grass when roof cells replaced walls in one layer.
		for y: int in range(24, 32):
			for x: int in range(16, 40 + extra * 8):
				var cell := Vector2i(x / 8, y / 8)
				var pixel := Vector2i(x % 8, y % 8)
				var wall_alpha: float = image.get_pixelv(walls.get_cell_atlas_coords(cell) * 8 + pixel).a
				var roof_alpha: float = image.get_pixelv(roof.get_cell_atlas_coords(cell) * 8 + pixel).a
				assert_eq(maxf(wall_alpha, roof_alpha), 1.0,
					"Transparent gable at %s, extra width %s" % [Vector2i(x, y), extra])
		house.free()
