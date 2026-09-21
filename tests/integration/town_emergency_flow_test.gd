extends SceneTree

const WatchTest = preload("res://tests/integration/town_watch_test.gd")
var failures: Array[String] = []
var life: TownLife

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _frames(count: int) -> void:
	for frame: int in range(count):
		life._process(1.0 / 60.0)
		await physics_frame

func _run() -> void:
	var cognition: Node = root.get_node("NpcCognition")
	cognition.save_game.path = OS.get_temp_dir().path_join("arcadia-emergency-%d.json" % OS.get_process_id())
	cognition.save_game.from_data(NpcWorldSave.new().to_data())
	cognition.save_game.region_seed = 274415
	cognition.save_game.life.minute = 1380
	var backend := WatchTest.MockBackend.new()
	root.add_child(backend)
	cognition.backend = backend
	cognition.events.backend = backend
	var world: Node2D = load("res://game/world/scenes/world.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame: int in range(8):
		await physics_frame
	life = world.get_node("Region/TownLife")
	life.set_process(false)
	life.encounters.set_process(false)
	var player: BasePlayer = world.get_node("BasePlayer")
	player.set_physics_process(false)
	player.world_space = &"isolated"
	for actor: BaseActor in get_nodes_in_group(&"actors"):
		if actor is BaseNpc:
			actor.set_physics_process(false)
			actor.world_space = &"isolated"
	# Keep the small scene scenario independent of unrelated residents' daily routing.
	for id: String in life._actors.keys():
		if not id in ["vale_guard", "garrin_holt", "holt_partner", "holt_child_a"]:
			life.buildings.release(life._actors[id], id)
			life._actors.erase(id)
		else:
			life._actors[id].world_space = &"outdoors"
			life._actors[id].global_position = Vector2(1000, 900)
	var guard: BaseNpc = life._actors.vale_guard
	var guard_id: String = "vale_guard"
	guard.world_space = &"outdoors"
	guard.global_position = Vector2(-280, 32)
	guard.set_physics_process(true)
	life.buildings.release(guard, guard_id)
	life.navigation.register(guard_id, guard)
	guard.daily_routine.navigation = life.navigation
	# The late guard must physically leave a saved sleeping state and patrol at 23:00.
	guard.sleep_at(guard.global_position + Vector2(0, -20))
	var start: Vector2 = guard.global_position
	await _frames(180)
	_check(not guard.is_sleeping(), "Night watch stayed asleep")
	_check(guard.daily_routine.activity == "patrol", "Night watch did not receive patrol duty")
	_check(guard.global_position.distance_to(start) > 16, "Night patrol did not move")
	var victim: BaseNpc = life._actors.garrin_holt
	var first: BaseNpc = life._actors.holt_partner
	var second: BaseNpc = life._actors.holt_child_a
	var room: NpcInterior = life.buildings.rooms[&"home:garrin_holt"]
	for npc: BaseNpc in [victim, first, second]:
		var id: String = String(npc.get_npc_profile().npc_id)
		life.buildings.release(npc, id)
		life.buildings._transfer(npc, id, &"home:garrin_holt", room.bed_for(id))
		npc.daily_routine.navigation = room.navigation
		npc.sleep_at(room.bed_for(id, true))
		npc.set_physics_process(true)
	player.world_space = &"home:garrin_holt"
	player.global_position = room.bed_for("garrin_holt") + Vector2(12, 0)
	await physics_frame
	victim.take_damage(99, player.hit_box)
	_check(first.is_sleeping() and second.is_sleeping(), "The household woke instantly")
	_check(cognition.save_game.is_dead(&"garrin_holt"), "Lethal hit was not immediately saved")
	_check(cognition.save_game.deaths.records.garrin_holt.stage == "fallen", "Unseen death was already reported")
	_check(life.save_game.justice.known_to(guard_id).is_empty(), "Outside guard learned the attacker through a wall")
	await _frames(50)
	_check(first.is_sleeping() and second.is_sleeping(), "Noise skipped the stirring delay")
	player.world_space = &"isolated"
	player.global_position = Vector2(2000, 2000)
	await _frames(90)
	_check(life.funerals._bodies.has("garrin_holt"), "Death animation removed the body")
	var body_save: Dictionary = cognition.save_game.to_data()
	var restored := NpcWorldSave.new()
	_check(restored.from_data(body_save), "A body could not be reloaded")
	_check(restored.deaths.records.garrin_holt.space == "home:garrin_holt", "Body lost its interior on reload")
	life.funerals.queue_free()
	await process_frame
	life.funerals = TownFunerals.new()
	life.funerals.life = life
	life.add_child(life.funerals)
	_check(life.funerals._bodies.has("garrin_holt"), "Reload failed to recreate the body visual")
	var interrupted: bool = false
	var stages: Array[String] = []
	for step: int in range(1400):
		await _frames(6)
		var entry: Dictionary = cognition.save_game.deaths.records.garrin_holt
		if not entry.stage in stages:
			stages.append(entry.stage)
			print("Recovery stage: ", entry.stage, " at ", life.save_game.life.clock_text())
		if entry.stage == "carried" and not interrupted:
			# Interrupt recovery with a new assault, then surrender. The corpse must stay local.
			interrupted = true
			player.world_space = guard.world_space
			player.global_position = guard.global_position + Vector2(16, 0)
			guard.set_enforcement_target(player)
			life.funerals.advance(0.1)
			_check(entry.stage == "reported", "Combat did not interrupt carrying")
			guard.clear_enforcement_target()
			player.world_space = &"isolated"
			player.global_position = Vector2(2000, 2000)
			# Recreate the adapter during an interrupted recovery to check resumability.
			life.funerals.queue_free()
			await process_frame
			life.funerals = TownFunerals.new()
			life.funerals.life = life
			life.add_child(life.funerals)
		if entry.stage == "buried":
			break
	var entry: Dictionary = cognition.save_game.deaths.records.garrin_holt
	_check("reported" in stages, "Witness never reached a guard")
	_check("recovering" in stages, "Guard did not reach the body")
	_check("carried" in stages, "Body skipped physical recovery")
	_check(entry.stage == "buried", "Recovery never reached burial: " + str(entry))
	_check(not life.funerals._bodies.has("garrin_holt"), "Buried body remained in the house")
	_check(life.funerals.cemetery._graves.has("garrin_holt"), "Burial has no grave")
	_check(life.save_game.justice.known_to(guard_id).is_empty(), "Discovering a body invented a murderer")
	_check(restored.from_data(cognition.save_game.to_data()), "Burial state failed to reload")
	# Rebuild the visual adapter from the save: one grave, no corpse or resurrected actor.
	life.funerals.queue_free()
	await process_frame
	var funerals := TownFunerals.new()
	funerals.life = life
	life.add_child(funerals)
	life.funerals = funerals
	_check(funerals._bodies.is_empty(), "A buried body returned after reload")
	_check(funerals.cemetery._graves.size() == 1, "Reload duplicated the grave")
	print("Emergency flow failures: ", failures)
	world.queue_free()
	await process_frame
	DirAccess.remove_absolute(cognition.save_game.path)
	quit(0 if failures.is_empty() else 1)
