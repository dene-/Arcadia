extends SceneTree

const FakeDecisionService = preload("res://tests/fixtures/npc_fake_decision_service.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var cognition: Node = root.get_node("NpcCognition")
	cognition.save_game.path = OS.get_temp_dir().path_join("arcadia-town-test-%d.json" % OS.get_process_id())
	cognition.save_game.legacy_world_path = cognition.save_game.path + ".legacy-world"
	cognition.save_game.legacy_memory_path = cognition.save_game.path + ".legacy-memory"
	cognition.save_game.from_data(NpcWorldSave.new().to_data())
	cognition.save_game.region_seed = 274415
	var backend := FakeDecisionService.new()
	# Residents want the social activity for a long while; the listener believes the rumor and
	# holds the player slightly less trustworthy.
	backend.set_default("select_goal", {"suitability:SOCIAL": 4.0, "duration:SOCIAL": "EXTENDED"})
	backend.set_default("listen", {"disposition:player:trust:direction": "NEGATIVE",
		"disposition:player:trust:magnitude": 1.0})
	backend.set_default("life/say", {"response": "Mirelle told me there was fighting nearby."})
	root.add_child(backend)
	cognition.backend = backend
	cognition.decisions.transport = backend
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
		if npc.life_context.known_townspeople.size() != cognition.save_game.population.people.size() - 1:
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
	# Give the rumor scenario a real rendezvous. Random daily plans need not bring the
	# only witness near another resident during this test's two-minute window.
	for participant: BaseNpc in [witness, residents[1]]:
		var id: String = String(participant.get_npc_profile().npc_id)
		var meeting: Dictionary = {"kind": "social", "place": "square"}
		cognition.save_game.life.select_activity(id, meeting, 90, {})
		life._request_routine(participant, id, meeting)
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
	var decisions: int = backend.call_count("select_goal")
	var transfers: int = backend.call_count("listen")
	var lines: int = backend.call_count("life/say")
	if informed < 2 or transfers == 0:
		failures.append("No rumor reached another resident")
	if lines == 0:
		failures.append("No audible social dialogue")
	if decisions < 9:
		failures.append("Not all residents consulted the decision model")
	print("Town life: moved=%d arrived=%d informed=%d decisions=%d lines=%d" %
		[moved, arrivals.size(), informed, decisions, lines])
	print("Town life failures: ", failures)
	world.queue_free()
	await process_frame
	var restored := NpcWorldSave.new()
	restored.path = cognition.save_game.path
	restored.legacy_world_path = cognition.save_game.legacy_world_path
	restored.legacy_memory_path = cognition.save_game.legacy_memory_path
	if restored.load_file() != OK:
		failures.append("Town save did not reload")
	DirAccess.remove_absolute(cognition.save_game.path)
	quit(0 if failures.is_empty() else 1)
