extends SceneTree

class MockLifeBackend extends DialogBackendClient:
	var decisions: int = 0
	var transfers: int = 0
	var lines: int = 0
	var http_mode: bool = false
	func request_life(kind: String, payload: Dictionary) -> Dictionary:
		if http_mode:
			if kind == "routine": decisions += 1
			if kind == "listen": transfers += 1
			if kind == "say": lines += 1
			return await super.request_life(kind, payload)
		match kind:
			"routine":
				decisions += 1
				return {"policy": {"activity": "SOCIAL", "duration_minutes": 90}}
			"social":
				print("Encounter: ", payload.npc.id, " -> ", payload.listener.id, " topics=", payload.topics.size())
				return {"policy": {"engage": true, "topic_index": 0 if not payload.topics.is_empty() else -1,
					"tone": "FRIENDLY", "another_exchange": false}}
			"listen":
				transfers += 1
				return {"policy": {"belief": 0.75, "remember": true, "importance": 0.8,
					"affinity": 0.01, "trust_player": -0.03}}
			"say":
				lines += 1
				return {"response": "Mirelle told me there was fighting nearby." if payload.mode == "share" else "Good to see you."}
		return {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var cognition: Node = root.get_node("NpcCognition")
	cognition.save_game.path = OS.get_temp_dir().path_join("arcadia-town-test-%d.json" % OS.get_process_id())
	cognition.save_game.life.from_data(TownLifeState.new().to_data())
	cognition.save_game.dead_npcs.clear()
	cognition.save_game.region_seed = 274415
	cognition.store.from_save_data(NpcMemoryStore.new().to_save_data())
	var backend := MockLifeBackend.new()
	var endpoint: String = OS.get_environment("ARCADIA_TOWN_SERVER_URL")
	if not endpoint.is_empty():
		backend.life_endpoint = endpoint + "/life"
		backend.http_mode = true
	root.add_child(backend)
	cognition.backend = backend
	cognition.events.backend.observation_endpoint = "http://127.0.0.1:1/observe"
	cognition.events.backend.reaction_endpoint = "http://127.0.0.1:1/react"
	var world: Node2D = load("res://game/world/scenes/world.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for enemy: Node in get_nodes_in_group("enemies"):
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
	world.get_node("BasePlayer").process_mode = Node.PROCESS_MODE_DISABLED
	for frame: int in range(5):
		await physics_frame
	var life: TownLife = world.get_node("Region/TownLife")
	var failures: Array[String] = []
	var residents: Array[Node] = get_nodes_in_group("town_residents")
	var starts: Dictionary = {}
	for npc: BaseNpc in residents:
		starts[npc.get_instance_id()] = npc.global_position
		if npc.life_context.known_townspeople.size() != 8:
			failures.append("Missing local knowledge: " + npc.name)
		if npc.get_npc_profile().social_traits.size() != 5:
			failures.append("Missing temperament: " + npc.name)
		for place: Dictionary in life._places.values():
			var space := StringName(place.get("space", "outdoors"))
			var destination: Vector2 = place.position
			if space != &"outdoors":
				var room: NpcInterior = life.buildings.rooms[space]
				if room.navigation.route(room.entrance, destination).is_empty():
					failures.append("No interior route to " + place.label)
				destination = room.outside
			if life.navigation.route(npc.global_position, destination).is_empty():
				failures.append("No route from %s to %s" % [npc.name, place.label])
	var witness: BaseNpc = residents[0]
	var witness_id: String = String(witness.get_npc_profile().npc_id)
	cognition.save_game.life.rumors.observe(witness_id, witness.get_npc_profile().profile_name,
		{"origin_id": "world:test", "text": "I saw Den hurt a person.", "sense": "sight", "player_involved": true},
		{"remember": true, "importance": 0.8}, cognition.save_game.life.minute)
	var capture: String = OS.get_environment("ARCADIA_TOWN_CAPTURE")
	var arrivals: Dictionary = {}
	for frame: int in range(7200):
		await physics_frame
		for npc: BaseNpc in residents:
			if npc.global_position.distance_to(starts[npc.get_instance_id()]) > 20 \
				and npc.global_position.distance_to(npc.daily_routine.destination) <= 3:
				arrivals[npc.get_instance_id()] = true
		if not capture.is_empty():
			for npc: BaseNpc in residents:
				if npc.get_node("ReactionBubble").visible:
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(capture)
					capture = ""
					break
	var moved: int = 0
	var informed: int = 0
	for npc: BaseNpc in residents:
		if npc.global_position.distance_to(starts[npc.get_instance_id()]) > 20:
			moved += 1
		if not cognition.save_game.life.rumors.get_known(String(npc.get_npc_profile().npc_id), cognition.save_game.life.minute).is_empty():
			informed += 1
	if moved < 8:
		failures.append("Only %d residents moved" % moved)
	if arrivals.size() < 8:
		failures.append("Only %d residents reached a destination" % arrivals.size())
	if informed < 2 or backend.transfers == 0:
		failures.append("No rumor reached another resident")
	if backend.lines == 0:
		failures.append("No audible social dialogue")
	if backend.decisions < 9:
		failures.append("Not all residents consulted the decision model")
	print("Town life: moved=%d arrived=%d informed=%d decisions=%d lines=%d" %
		[moved, arrivals.size(), informed, backend.decisions, backend.lines])
	print("Town life failures: ", failures)
	world.queue_free()
	await process_frame
	var restored := NpcWorldSave.new()
	restored.path = cognition.save_game.path
	if restored.load_file() != OK:
		failures.append("Town save did not reload")
	DirAccess.remove_absolute(cognition.save_game.path)
	quit(0 if failures.is_empty() else 1)
