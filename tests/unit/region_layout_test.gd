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

func test_cottage_pattern_references_real_tiles_and_visible_alternatives() -> void:
	var pattern: TileMapPattern = load("res://game/resources/world/cottage_pattern.tres")
	var tiles: TileSet = load("res://game/resources/world/town_tileset.tres")
	assert_true(pattern.get_used_cells().size() >= 30)
	for cell: Vector2i in pattern.get_used_cells():
		var source: TileSetAtlasSource = tiles.get_source(pattern.get_cell_source_id(cell))
		var coords: Vector2i = pattern.get_cell_atlas_coords(cell)
		assert_true(source.has_tile(coords))
		assert_true(source.has_alternative_tile(coords, pattern.get_cell_alternative_tile(cell)))
