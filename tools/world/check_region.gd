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
	cognition.backend.observation_endpoint = "http://127.0.0.1:1/observe"
	cognition.backend.reaction_endpoint = "http://127.0.0.1:1/react"
	var world: Node2D = load("res://game/world/scenes/world.tscn").instantiate()
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
	for home: Dictionary in RegionLayout.HOMES:
		if not _blocked(space, Vector2(home.cell * 8) + Vector2(0, -9)):
			failures.append("Missing house collision: %s" % home.job)
		if _blocked(space, Vector2(home.cell * 8) + Vector2(0, 24)):
			failures.append("NPC spawned inside obstacle: %s" % home.job)
	if not _blocked(space, Vector2((RegionLayout.river_left_at(20) + 4) * 8, 164)):
		failures.append("Missing river collision")
	for point: Vector2 in [Vector2(-76, -164), Vector2(409, -60), Vector2(-132, 154)]:
		if not _blocked(space, point):
			failures.append("Prop footprint misses its visible base at %s" % point)
	if get_nodes_in_group("npc_observers").size() != 9:
		failures.append("Expected nine named NPCs")
	if get_nodes_in_group("enemies").size() != 35:
		failures.append("Expected 35 enemies")
	var enemy: BaseNpc = world.get_node("Region/Enemy27")
	var player: BasePlayer = world.get_node("BasePlayer")
	if enemy.global_position.distance_to(player.global_position) > 300:
		failures.append("First encounter is too far from the town approach")
	player.global_position = enemy.global_position + Vector2(32, 0)
	await physics_frame
	if enemy.update_enemy_ai(0.016) != &"run":
		failures.append("Approach enemy does not chase a visible nearby player")
	_check_detail_crops(failures)
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

func _check_detail_crops(failures: Array[String]) -> void:
	var region_script: GDScript = load("res://game/world/region/rekala_region.gd")
	for sheet: String in [RegionArt.PLAINS, RegionArt.SWAMP]:
		var texture: Texture2D = load(RegionArt.ROOT + sheet)
		var rectangles: Array[Rect2i] = region_script.WET_DETAILS if sheet == RegionArt.SWAMP else region_script.DRY_DETAILS
		_check_crops(texture.get_image(), rectangles, failures)

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
