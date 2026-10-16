extends SceneTree

## Real-scene smoke and collision checks. Never touches the player's save or providers.
var started: bool = false

func _process(_delta: float) -> bool:
	if started: return false
	started = true
	_run()
	return false

func _run() -> void:
	var cognition: Node = root.get_node("NpcCognition")
	cognition.save_game.path = OS.get_temp_dir().path_join("arcadia-region-check-%s.json" % OS.get_process_id())
	cognition.save_game.region_seed = 274415
	cognition.save_game.dead_npcs.clear()
	cognition.store.from_save_data(NpcMemoryStore.new().to_save_data())
	var world: Node2D = load("res://game/world/scenes/world.tscn").instantiate()
	world.town_life_enabled = false
	root.add_child(world)
	current_scene = world
	for actor: Node in get_nodes_in_group("npc_observers") + get_nodes_in_group("enemies"):
		actor.process_mode = Node.PROCESS_MODE_DISABLED
	world.get_node("BasePlayer").process_mode = Node.PROCESS_MODE_DISABLED
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState2D = world.get_world_2d().direct_space_state
	var failures: Array[String] = []
	if _blocked(space, RegionLayout.PLAYER_SPAWN):
		failures.append("Player spawned inside an obstacle")
	for row: int in RegionLayout.BRIDGES:
		var left: int = RegionLayout.river_left_at(row)
		for x: int in range(left - 3, left + 13):
			if _blocked(space, Vector2(x * 8 + 4, row * 8 + 4)):
				failures.append("Bridge blocked at %s" % Vector2i(x, row))
		for y: int in [row * 8 - 10, row * 8 + 14, row * 8 + 20]:
			if not _blocked(space, Vector2((left + 4) * 8, y)):
				failures.append("Bridge side open at %s" % Vector2((left + 4) * 8, y))
	for home: Dictionary in RegionLayout.HOMES:
		if not _blocked(space, Vector2(home.cell * 8) + Vector2(0, -9)):
			failures.append("Missing house collision: %s" % home.job)
		# Household members spawn in up to two rows of three in front of the door.
		for member: int in range(6):
			var spawn := Vector2(home.cell * 8) + Vector2((member % 3 - 1) * 12, 24 + member / 3 * 12)
			if _blocked(space, spawn):
				failures.append("NPC spawned inside obstacle: %s at %s" % [home.job, spawn])
	if not _blocked(space, Vector2((RegionLayout.river_left_at(20) + 4) * 8, 164)):
		failures.append("Missing river collision")
	# A tree, the windmill base and the carpenter's sawhorse.
	for point: Vector2 in [Vector2(-336, -195), Vector2(409, -60), Vector2(148, -130)]:
		if not _blocked(space, point):
			failures.append("Prop footprint misses its visible base at %s" % point)
	var residents: int = TownPopulation.FOUNDERS.size() + TownPopulation.MEMBERS.size()
	if get_nodes_in_group("npc_observers").size() != residents:
		failures.append("Expected %s residents" % residents)
	if get_nodes_in_group("enemies").size() != 35:
		failures.append("Expected 35 enemies")
	var enemy: BaseNpc = world.get_node("Region/Enemy27")
	var player: BasePlayer = world.get_node("BasePlayer")
	var west_gate := Vector2(RegionTown.FENCE_LEFT * 8, 32)
	if enemy.global_position.distance_to(west_gate) > 300:
		failures.append("First encounter is too far from the west town gate")
	for cell: Vector2i in [Vector2i(RegionTown.FENCE_LEFT, 4), Vector2i(0, RegionTown.FENCE_TOP),
		Vector2i(0, RegionTown.FENCE_BOTTOM)]:
		if _blocked(space, Vector2(cell * 8) + Vector2(4, 4)):
			failures.append("Town gate blocked at %s" % cell)
	player.global_position = enemy.global_position + Vector2(32, 0)
	await physics_frame
	if enemy.update_enemy_ai(0.016) != &"run":
		failures.append("Approach enemy does not chase a visible nearby player")
	_check_detail_crops(failures)
	_check_town_placement(world, space, failures)
	print("Region physical checks: ", failures)
	world.queue_free()
	await process_frame
	DirAccess.remove_absolute(cognition.save_game.path)
	quit(0 if failures.is_empty() else 1)

func _blocked(space: PhysicsDirectSpaceState2D, point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 1
	return not space.intersect_point(query).is_empty()

## Buildings stand clear of streets, cobbles and each other; no prop, tree or fence clips
## into a building; and no obstacle stands on a street outside the dooryards, where signs
## and pots sit against the walls.
func _check_town_placement(world: Node2D, space: PhysicsDirectSpaceState2D,
		failures: Array[String]) -> void:
	var layout: RegionLayout = world.layout
	var paved: Dictionary[Vector2i, bool] = layout.roads.duplicate()
	for cell: Vector2i in layout.stone:
		paved[cell] = true
	var buildings: Array[Dictionary] = []
	buildings.append_array(RegionLayout.HOMES)
	buildings.append_array(RegionLayout.PUBLIC_BUILDINGS)
	buildings.append_array(RegionLayout.OUTBUILDINGS)
	var walls: Array[Rect2] = []
	var dooryards: Dictionary[Vector2i, bool] = {}
	for building: Dictionary in buildings:
		var foot := Vector2(building.cell * 8)
		var half_width: float = 20 + int(building.extra) * 4
		var rect := Rect2(foot.x - half_width, foot.y - 48, half_width * 2, 48)
		for other: Rect2 in walls:
			if rect.grow(4).intersects(other):
				failures.append("Buildings touch at %s" % building.cell)
		walls.append(rect)
		for cell: Vector2i in paved:
			if rect.intersects(Rect2(cell * 8, Vector2(8, 8))):
				failures.append("Street under building at %s" % cell)
		if not RegionLayout.OUTBUILDINGS.has(building):
			for y: int in range(0, 4):
				for x: int in range(-3, 4):
					dooryards[building.cell + Vector2i(x, y)] = true
		var query := PhysicsShapeQueryParameters2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect.size - Vector2(2, 2)
		query.shape = shape
		query.transform = Transform2D(0, rect.get_center())
		query.collision_mask = 1
		for hit: Dictionary in space.intersect_shape(query, 8):
			var owner_node: Node = hit.collider.get_parent()
			if owner_node is Node2D and owner_node.global_position == foot:
				continue
			failures.append("%s clips into the building at %s" % [owner_node.name, building.cell])
	for cell: Vector2i in layout.roads:
		if RegionLayout.TOWN.has_point(cell) and not dooryards.has(cell) \
			and _blocked(space, Vector2(cell * 8) + Vector2(4, 4)):
			failures.append("Obstacle on a town street at %s" % cell)

func _check_detail_crops(failures: Array[String]) -> void:
	var region_script: GDScript = load("res://game/world/region/rekala_region.gd")
	for sheet: String in [RegionArt.PLAINS, RegionArt.SWAMP]:
		var texture: Texture2D = load(RegionArt.ROOT + sheet)
		var rectangles: Array[Rect2i] = region_script.WET_DETAILS if sheet == RegionArt.SWAMP else region_script.DRY_DETAILS
		_check_crops(texture.get_image(), rectangles, failures)
	# Every catalogued prop and plant must be one whole sprite inside its region.
	var catalog: Array[Array] = []
	catalog.append_array(RegionArt.PROPS.values())
	catalog.append_array(RegionArt.GROUND_COVER.values())
	for entry: Array in catalog:
		var crop: Array[Rect2i] = [entry[1]]
		_check_crops(load(RegionArt.ROOT + String(entry[0])).get_image(), crop, failures)
	# Interior furniture and rugs too.
	for entry: Array in TownInteriorLayout.PROPS.values():
		var crop: Array[Rect2i] = [entry[1]]
		_check_crops(load(RegionArt.ROOT + String(entry[0])).get_image(), crop, failures)
	_check_crops(load(RegionArt.ROOT + RegionArt.TOWN_II).get_image(),
		TownInteriorLayout.RUG_REGIONS, failures)

func _check_crops(image: Image, rectangles: Array[Rect2i], failures: Array[String]) -> void:
	for rect: Rect2i in rectangles:
		var cut: bool = false
		for y: int in range(rect.position.y, rect.end.y):
			cut = cut or _joined(image, Vector2i(rect.position.x, y), Vector2i.LEFT)
			cut = cut or _joined(image, Vector2i(rect.end.x - 1, y), Vector2i.RIGHT)
		for x: int in range(rect.position.x, rect.end.x):
			cut = cut or _joined(image, Vector2i(x, rect.position.y), Vector2i.UP)
			cut = cut or _joined(image, Vector2i(x, rect.end.y - 1), Vector2i.DOWN)
		if cut:
			failures.append("Detail atlas crop cuts a sprite: %s" % rect)

func _joined(image: Image, pixel: Vector2i, direction: Vector2i) -> bool:
	if not Rect2i(Vector2i.ZERO, image.get_size()).has_point(pixel + direction):
		return false
	return image.get_pixelv(pixel).a > 0.5 and image.get_pixelv(pixel + direction).a > 0.5
