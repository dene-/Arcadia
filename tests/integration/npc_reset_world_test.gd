extends SceneTree

const WatchTest = preload("res://tests/integration/town_watch_test.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var cognition: Node = root.get_node("NpcCognition")
	var save: NpcWorldSave = cognition.save_game
	var filename: String = "arcadia-reset-world-%d.json" % OS.get_process_id()
	save.path = OS.get_temp_dir().path_join(filename)
	save.from_data(NpcWorldSave.new().to_data())
	save.region_seed = 274415
	save.population.ensure_population(save.region_seed)
	for id: String in save.population.people:
		save.mark_dead(StringName(id))
		save.deaths.record(id, "outdoors", Vector2.ZERO, 480)
	_check(save.save_file() == OK, "Could not write fixture")
	_check(save.reset(true, true) == OK, "Could not reset fixture")
	_check(save.load_file() == OK, "Could not reload reset save")
	var backend := WatchTest.MockBackend.new()
	root.add_child(backend)
	cognition.backend = backend
	cognition.events.backend = backend
	var world: Node = load("res://game/world/scenes/world.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame: int in range(8):
		await physics_frame
	var life: TownLife = world.get_node("Region/TownLife")
	life.set_process(false)
	life.encounters.set_process(false)
	_check(save.region_seed == 274415, "Map seed changed")
	_check(get_nodes_in_group("town_residents").size() == save.population.people.size(),
		"Reset did not respawn every resident")
	_check(save.deaths.records.is_empty(), "Bodies survived reset")
	for npc: BaseNpc in get_nodes_in_group("town_residents"):
		var profile: NpcProfile = npc.get_npc_profile()
		var expected: Dictionary = NpcTemperament.generate(save.get_npc_seed(), String(profile.npc_id))
		_check(npc.health > 0, "Resident is still dead: " + String(profile.npc_id))
		_check(profile.personality == expected.personality and profile.voice == expected.voice,
			"Resident did not use the new NPC seed: " + String(profile.npc_id))
	_check(life.encounters.seed_value == save.get_npc_seed(), "Social encounters used the map seed")
	world.queue_free()
	await process_frame
	DirAccess.remove_absolute(save.path)
	for name: String in DirAccess.get_files_at(OS.get_temp_dir()):
		if name.begins_with(filename + ".reset-"):
			DirAccess.remove_absolute(OS.get_temp_dir().path_join(name))
	for failure: String in failures:
		push_error(failure)
	print("NPC reset world integration: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
