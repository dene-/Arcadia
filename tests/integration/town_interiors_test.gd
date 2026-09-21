extends SceneTree

class MockBackend extends DialogBackendClient:
	var always_rest: bool = false
	func request_life(kind: String, _payload: Dictionary) -> Dictionary:
		return {"policy": {"activity": "REST" if always_rest else "PLAN", "duration_minutes": 75}} if kind == "routine" else {}

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
	print("Region navigation: ", life.navigation.metrics())
	var residents: Array[Node] = get_nodes_in_group("town_residents")
	var failures: Array[String] = []
	_check_prop_crops(failures)
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
		else:
			var bed_room: NpcInterior = buildings.rooms[npc.world_space]
			var sprite: AnimatedSprite2D = npc.animated_sprite
			var texture: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, 0)
			var used: Rect2i = texture.get_image().get_used_rect()
			var center: Vector2 = Vector2(used.position) + Vector2(used.size) * 0.5 - texture.get_size() * 0.5
			if sprite.flip_h:
				center.x = -center.x
			if sprite.to_global(center).distance_to(bed_room.bed_center) > 1:
				failures.append("Sleeping sprite misses mattress: " + id)
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
		for interior: NpcInterior in buildings.rooms.values():
			buildings.move_player(player, &"outdoors")
			buildings.move_player(player, StringName("home:" + interior.resident_id))
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(capture.get_basename() + "-" + interior.job + ".png")
		buildings.move_player(player, &"outdoors")
		buildings.move_player(player, StringName("home:" + room.resident_id))
		await physics_frame
		await physics_frame
	life._save()
	var sleeping_save: Dictionary = cognition.save_game.to_data()
	var restored := NpcWorldSave.new()
	restored.path = cognition.save_game.path
	if restored.load_file() != OK or restored.life.get_person(room.resident_id).space != String(resident.world_space):
		failures.append("Room membership did not survive saving")
	player.global_position = room.bed_spot
	await physics_frame
	await physics_frame
	if not resident.get_interaction_area().overlaps_body(player):
		failures.append("The sleeping resident cannot be reached from the bedside")
	resident.enter_dialog()
	if resident._sleeping or resident.animated_sprite.rotation != 0:
		failures.append("Interacting did not wake a sleeping resident")
	await physics_frame
	await physics_frame
	if resident.body_collision_shape.disabled:
		failures.append("Waking did not restore resident collision")
	player.global_position = room.player_entrance
	await physics_frame
	await physics_frame
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
	# A portal must update lighting synchronously, before another clock tick/render.
	var original_position: Vector2 = player.global_position
	var blocked_entry: StaticBody2D = RegionArt.barrier(world, room.player_entrance, Vector2(32, 32))
	await physics_frame
	buildings.move_player(player, StringName("home:" + room.resident_id))
	if player.world_space != &"outdoors" or player.global_position != original_position:
		failures.append("Blocked doorway moved the player")
	if Rect2i(camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom) != old_limits:
		failures.append("Blocked doorway changed the camera")
	blocked_entry.queue_free()
	await physics_frame
	await process_frame
	cognition.save_game.life.minute = 22 * 60
	buildings.move_player(player, StringName("home:" + room.resident_id))
	if life._light.color != Color(1, 0.96, 0.88):
		failures.append("Interior lighting was not applied during entry")
	buildings.move_player(player, &"outdoors")
	if life._light.color != Color(0.48, 0.53, 0.7):
		failures.append("Night lighting was not restored during exit")
	cognition.save_game.life.minute = 480
	# Exercise the actual E input with movement and collision enabled at every house.
	for interior: NpcInterior in buildings.rooms.values():
		var front: BuildingDoor = buildings.get_node(interior.job.capitalize() + "Door")
		player.global_position = front.global_position + Vector2(0, 20)
		await physics_frame
		await physics_frame
		if front.can_interact(player):
			failures.append("Door accepts a distant player: " + interior.job)
		player.global_position = interior.outside
		player.set_physics_process(true)
		await physics_frame
		await physics_frame
		Input.action_press(&"player_up")
		Input.action_press(&"player_interact")
		await physics_frame
		await physics_frame
		Input.action_release(&"player_interact")
		Input.action_release(&"player_up")
		await physics_frame
		if player.world_space != StringName("home:" + interior.resident_id) \
			or player.global_position.distance_to(interior.player_entrance) > 6:
			failures.append("E did not arrive at the interior threshold: " + interior.job)
		Input.action_press(&"player_down")
		Input.action_press(&"player_interact")
		await physics_frame
		await physics_frame
		Input.action_release(&"player_interact")
		Input.action_release(&"player_down")
		await physics_frame
		if player.world_space != &"outdoors" or player.global_position.distance_to(interior.outside) > 6:
			failures.append("E did not arrive at the exterior threshold: " + interior.job)
		player.set_physics_process(false)
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
	life = world.get_node("Region/TownLife")
	life.minutes_per_second = 0
	backend.always_rest = true
	cognition.save_game.life.minute = 650
	for frame: int in range(90):
		await physics_frame
	for npc: BaseNpc in get_nodes_in_group("town_residents"):
		if npc.is_sleeping() or npc.daily_routine.activity == "rest":
			failures.append("Resident ignored the scheduled wakeup: " + npc.name)
	print("Town interior failures: ", failures)
	world.queue_free()
	await process_frame
	DirAccess.remove_absolute(cognition.save_game.path)
	quit(0 if failures.is_empty() else 1)

func _check_prop_crops(failures: Array[String]) -> void:
	for kind: String in TownInteriorLayout.PROPS:
		var prop: Array = TownInteriorLayout.PROPS[kind]
		var texture: Texture2D = load(RegionArt.ROOT + String(prop[0]))
		var image: Image = texture.get_image()
		var rect: Rect2i = prop[1]
		for point: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			for index: int in range(rect.size.y if point.x != 0 else rect.size.x):
				var pixel: Vector2i = rect.position + (Vector2i(0 if point.x < 0 else rect.size.x - 1, index) \
					if point.x != 0 else Vector2i(index, 0 if point.y < 0 else rect.size.y - 1))
				if Rect2i(Vector2i.ZERO, image.get_size()).has_point(pixel + point) \
					and image.get_pixelv(pixel).a > 0.5 and image.get_pixelv(pixel + point).a > 0.5:
					failures.append("Furniture crop cuts pixels: " + kind)
					break
