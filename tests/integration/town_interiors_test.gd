extends SceneTree

class MockBackend extends DialogBackendClient:
	func request_life(kind: String, _payload: Dictionary) -> Dictionary:
		return {"policy": {"activity": "PLAN", "duration_minutes": 75}} if kind == "routine" else {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var cognition: Node = root.get_node("NpcCognition")
	cognition.save_game.path = OS.get_temp_dir().path_join("arcadia-interiors-%d.json" % OS.get_process_id())
	cognition.save_game.life.from_data(TownLifeState.new().to_data())
	cognition.save_game.dead_npcs.clear()
	cognition.save_game.region_seed = 274415
	cognition.store.from_save_data(NpcMemoryStore.new().to_save_data())
	var backend := MockBackend.new()
	root.add_child(backend)
	cognition.backend = backend
	cognition.events.backend.observation_endpoint = "http://127.0.0.1:1/observe"
	cognition.events.backend.reaction_endpoint = "http://127.0.0.1:1/react"
	var world: Node2D = load("res://game/world/scenes/world.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for enemy: Node in get_nodes_in_group("enemies"):
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
	var player: BasePlayer = world.get_node("BasePlayer")
	player.set_physics_process(false)
	for frame: int in range(5):
		await physics_frame
	var life: TownLife = world.get_node("Region/TownLife")
	var buildings: TownBuildings = life.buildings
	life.minutes_per_second = 0
	var residents: Array[Node] = get_nodes_in_group("town_residents")
	var failures: Array[String] = []
	for npc: BaseNpc in residents:
		var id: String = String(npc.get_npc_profile().npc_id)
		var home: Dictionary = {"kind": "rest", "place": "home:" + id}
		life.save_game.life.select_activity(id, home, 120, {})
		life._travel(npc, id, home)
	for frame: int in range(1800):
		await physics_frame
	for npc: BaseNpc in residents:
		var id: String = String(npc.get_npc_profile().npc_id)
		if npc.world_space != StringName("home:" + id) or not npc.state_machine.is_in_state(&"sleep"):
			failures.append("Did not reach bed: %s at %s, state=%s, goal=%s" %
				[id, npc.position, npc.state_machine.get_current_state_name(), npc.daily_routine.destination])
	var resident: BaseNpc = residents[0]
	var room: NpcInterior = buildings.rooms[StringName("home:" + String(resident.get_npc_profile().npc_id))]
	var old_limits := Rect2i(player.get_node("Camera2D").limit_left, player.get_node("Camera2D").limit_top,
		player.get_node("Camera2D").limit_right, player.get_node("Camera2D").limit_bottom)
	var exterior: BuildingDoor = buildings.get_node(String(room.job).capitalize() + "Door")
	player.global_position = room.outside
	await physics_frame
	await physics_frame
	if world.get_node("InteractionPrompt")._find_closest_interactable() != exterior:
		failures.append("The outdoor door is not reachable by player interaction")
	exterior.interact(player)
	await physics_frame
	if player.world_space != resident.world_space or not room.navigation.is_clear(player.global_position):
		failures.append("Door did not enter the intended room at a walkable position")
	if NpcPerception.can_see(residents[1], resident):
		failures.append("Vision leaked between separate interiors")
	if not NpcPerception.observe(residents[1], resident, player, false).is_empty():
		failures.append("Combat leaked between separate interiors")
	var capture: String = OS.get_environment("ARCADIA_INTERIOR_CAPTURE")
	if not capture.is_empty():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	life._save()
	var sleeping_save: Dictionary = cognition.save_game.to_data()
	var restored := NpcWorldSave.new()
	restored.path = cognition.save_game.path
	if restored.load_file() != OK or restored.life.get_person(room.resident_id).space != String(resident.world_space):
		failures.append("Room membership did not survive saving")
	resident.enter_dialog()
	if resident._sleeping or resident.animated_sprite.rotation != 0:
		failures.append("Interacting did not wake a sleeping resident")
	await physics_frame
	if resident.body_collision_shape.disabled:
		failures.append("Waking did not restore resident collision")
	if not capture.is_empty():
		var manager: Node = root.get_node("DialogManager")
		manager._bind_dialog_ui()
		manager._start_dialog(resident)
		manager._apply_dialog_result({"response": "What is it? I was asleep.", "replies": ["Sorry.", "I need help.", "Bye."]})
		manager.advance_dialog()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture.get_basename() + "-dialog.png")
		manager.close_dialog()
	resident.exit_dialog()
	if not room.door.get_interaction_area().overlaps_body(player):
		failures.append("The exit door is not reachable from the room entrance")
	room.door.interact(player)
	await physics_frame
	if player.world_space != &"outdoors" or player.position.distance_to(room.outside) > 12:
		failures.append("Exit did not return to the matching outdoor door")
	var camera: Camera2D = player.get_node("Camera2D")
	if Rect2i(camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom) != old_limits:
		failures.append("Camera limits were not restored")
	# Residents must also leave through their own door to reach the outdoor square.
	for npc: BaseNpc in residents:
		var id: String = String(npc.get_npc_profile().npc_id)
		var outing: Dictionary = {"kind": "walk", "place": "square"}
		life.save_game.life.select_activity(id, outing, 120, {})
		life._travel(npc, id, outing)
	for frame: int in range(1800):
		await physics_frame
	for npc: BaseNpc in residents:
		if npc.world_space != &"outdoors":
			failures.append("Resident could not leave home: " + npc.name)
	world.queue_free()
	await process_frame
	# Reconstruct the actual scene using saved room membership, rather than just checking JSON.
	cognition.save_game.from_data(sleeping_save)
	world = load("res://game/world/scenes/world.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for enemy: Node in get_nodes_in_group("enemies"):
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
	world.get_node("BasePlayer").set_physics_process(false)
	for frame: int in range(30):
		await physics_frame
	for npc: BaseNpc in get_nodes_in_group("town_residents"):
		if npc.world_space != StringName("home:" + String(npc.get_npc_profile().npc_id)) \
			or not npc.is_sleeping():
			failures.append("Restart did not restore sleeping resident: " + npc.name)
	print("Town interior failures: ", failures)
	world.queue_free()
	await process_frame
	DirAccess.remove_absolute(cognition.save_game.path)
	quit(0 if failures.is_empty() else 1)
