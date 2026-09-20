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
	if get_nodes_in_group("npc_observers").size() != 9:
		failures.append("Expected nine named NPCs")
	if get_nodes_in_group("enemies").size() != 27:
		failures.append("Expected 27 enemies")
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
