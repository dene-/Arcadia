extends SceneTree

class SafetyBackend extends DialogBackendClient:
	signal release_routine
	signal release_observation
	var hold_routine: bool = false
	var hold_observation: bool = true
	func request_life(kind: String, _payload: Dictionary) -> Dictionary:
		if kind == "routine":
			if hold_routine:
				await release_routine
			return {"policy": {"activity": "PLAN", "duration_minutes": 30}}
		return {"policy": {"engage": false, "topic_index": -1,
			"tone": "RESERVED", "another_exchange": false}}
	func request_observation(_payload: Dictionary) -> Dictionary:
		if hold_observation:
			await release_observation
		return {} # Exercise retreat with the classifier unavailable.

var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _run() -> void:
	var cognition: Node = root.get_node("NpcCognition")
	cognition.save_game.path = OS.get_temp_dir().path_join("arcadia-safety-%d.json" % OS.get_process_id())
	cognition.save_game.from_data(NpcWorldSave.new().to_data())
	cognition.save_game.region_seed = 274415
	var backend := SafetyBackend.new()
	root.add_child(backend)
	cognition.backend = backend
	cognition.events.backend = backend
	var world: Node2D = load("res://game/world/scenes/world.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame: int in range(5):
		await physics_frame
	var life: TownLife = world.get_node("Region/TownLife")
	life.set_process(false)
	life.minutes_per_second = 0 # Advance time explicitly, independently of the movement test.
	for actor: Node in get_nodes_in_group("enemies") + get_nodes_in_group("town_residents"):
		actor.process_mode = Node.PROCESS_MODE_DISABLED
	var npc: BaseNpc = get_nodes_in_group("town_residents")[0]
	npc.process_mode = Node.PROCESS_MODE_INHERIT
	var id: String = String(npc.get_npc_profile().npc_id)
	var player: BasePlayer = world.get_node("BasePlayer")
	# Keep the physics body registered: dialogue entry/exit applies velocity immediately.
	player.set_physics_process(false)
	var home: NpcInterior = life.buildings.rooms[StringName("home:" + id)]
	life.buildings._transfer(npc, id, &"outdoors", life.navigation.nearest(home.outside + Vector2(0, 24)))
	life.buildings._transfer(player, "player:%d" % player.get_instance_id(), &"outdoors", npc.global_position + Vector2(10, 0))
	npc.set_health(npc.max_health)
	# Hold an earlier routine response: the urgent route must not wait for it.
	backend.hold_routine = true
	life._choose_activity(npc, id)
	var dialog: Node = root.get_node("DialogManager")
	_check(dialog._bind_dialog_ui(), "World dialogue UI could not be bound")
	dialog._start_dialog(npc)
	dialog.dialog_started.emit(npc, "Hello.")
	npc.take_damage(1, player.hit_box)
	_check(NpcSafetyState.sheltering(life.save_game.life.get_person(id).safety,
		life.save_game.life.minute), "Actual injury did not establish a provisional safety concern")
	for frame: int in range(60):
		await physics_frame
	life._process(1.01)
	_check(not dialog.is_dialog_open(), "The retreat did not interrupt the active conversation")
	_check(npc.daily_routine.activity == "shelter", "Retreat waited for the delayed provider")
	backend.hold_routine = false
	backend.release_routine.emit()
	backend.hold_observation = false
	backend.release_observation.emit()
	await cognition.events.flush(id)
	_check(life.save_game.life.get_person(id).activity == "shelter", "An obsolete routine replaced the retreat")
	await _arrive(npc, life, StringName("home:" + id))
	_check(not npc.is_sleeping(), "Taking shelter incorrectly put the NPC to sleep")
	var saved := NpcWorldSave.new()
	_check(saved.from_data(life.save_game.to_data()), "Safety state did not survive serialization")
	_check(saved.life.get_person(id).safety == life.save_game.life.get_person(id).safety,
		"The saved concern changed on reload")
	# A new attack inside the refuge must cause an exit, not another trip to the bed.
	life.buildings._transfer(player, "player:%d" % player.get_instance_id(),
		npc.world_space, npc.global_position + Vector2(10, 0))
	npc.set_health(npc.max_health)
	npc.take_damage(1, player.hit_box)
	for frame: int in range(60):
		await physics_frame
	life._process(1.01)
	_check(life.save_game.life.get_person(id).place == "market", "NPC stayed in the room where they were attacked")
	await _arrive(npc, life, &"outdoors")
	life.save_game.life.advance(NpcSafetyState.SHELTER_MINUTES + 1)
	life._process(1.01)
	_check(life.save_game.life.get_person(id).activity != "shelter", "NPC never resumed the daily plan")
	_check(npc.life_context.safety_response.is_empty(), "Expired danger remained in model context")
	print("NPC safety world failures: ", _failures)
	world.queue_free()
	await process_frame
	DirAccess.remove_absolute(cognition.save_game.path)
	quit(0 if _failures.is_empty() else 1)

func _arrive(npc: BaseNpc, life: TownLife, space: StringName) -> void:
	for frame: int in range(2400):
		await physics_frame
		life._process(1.0 / 60.0)
		if npc.world_space == space and npc.global_position.distance_to(npc.daily_routine.destination) <= 3:
			return
	_failures.append("NPC failed to reach refuge in " + String(space))
