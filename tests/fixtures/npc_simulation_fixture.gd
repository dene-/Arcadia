extends RefCounted

## Isolated, deterministic town simulation for cognition scenarios. Redirects the NpcCognition save to a
## temporary file, replaces every provider with a scripted fake and advances time only through advance().
## Usage: setup(tree) -> await load_world() -> await advance_minutes(n) -> reload_save() -> await teardown().
const FakeService = preload("res://tests/fixtures/npc_fake_decision_service.gd")
const WORLD_SCENE: String = "res://game/world/scenes/world.tscn"
const READY_FRAME_LIMIT: int = 120
const GUARD_ENDPOINT: String = "http://127.0.0.1:1"

static var _counter: int = 0

## Set before setup() to choose another map seed.
var region_seed: int = 274415
var tree: SceneTree
var backend: FakeService
var world: Node
var life: TownLife
var save_path: String = ""
## Fatal fixture problems (also push_error'd); scenarios assert this stays empty.
var problems: Array[String] = []
var _cognition: Node
var _original_backend: DialogBackendClient
var _trace: Array[Dictionary] = []
var _last_entry: Dictionary = {}

func setup(scene_tree: SceneTree) -> void:
	tree = scene_tree
	_cognition = tree.root.get_node("NpcCognition")
	_original_backend = _cognition.backend
	# Guard: anything that still reaches the original client cannot leave the machine.
	_original_backend.chat_endpoint = GUARD_ENDPOINT + "/chat"
	_original_backend.decision_endpoint = GUARD_ENDPOINT + "/decide"
	_original_backend.observation_endpoint = GUARD_ENDPOINT + "/observe"
	_original_backend.reaction_endpoint = GUARD_ENDPOINT + "/react"
	_original_backend.life_endpoint = GUARD_ENDPOINT + "/life"
	_counter += 1
	save_path = OS.get_temp_dir().path_join("arcadia-sim-%d-%d.json" % [OS.get_process_id(), _counter])
	var save: NpcWorldSave = _cognition.save_game
	save.path = save_path
	save.from_data(NpcWorldSave.new().to_data())
	# The temp path does not exist, so this only clears the read-only latch left by a real save.
	var legacy_path: String = save_path + ".legacy"
	var error: Error = save.load_file(legacy_path)
	if error != OK:
		_fail("Could not initialize the temporary save: %s" % error)
	save.region_seed = region_seed
	backend = FakeService.new()
	backend.chat_endpoint = GUARD_ENDPOINT + "/chat"
	backend.decision_endpoint = GUARD_ENDPOINT + "/decide"
	backend.observation_endpoint = GUARD_ENDPOINT + "/observe"
	backend.reaction_endpoint = GUARD_ENDPOINT + "/react"
	backend.life_endpoint = GUARD_ENDPOINT + "/life"
	tree.root.add_child(backend)
	_cognition.backend = backend
	_cognition.events.backend = backend

func save_game() -> NpcWorldSave:
	return _cognition.save_game

## Awaitable. Returns null (and records a problem) if the town never finished initializing.
func load_world() -> Node:
	world = (load(WORLD_SCENE) as PackedScene).instantiate()
	tree.root.add_child(world)
	tree.current_scene = world
	life = world.get_node("Region/TownLife")
	var frames: int = 0
	while not life._initialized:
		if frames >= READY_FRAME_LIMIT:
			_fail("TownLife was not ready after %d physics frames" % READY_FRAME_LIMIT)
			return null
		await tree.physics_frame
		frames += 1
	life.set_process(false)
	return world

## Awaitable. One life tick and one physics frame per step, so actors walk between ticks.
func advance(seconds: float, step: float = 1.0 / 60.0) -> void:
	var steps: int = ceili(seconds / step - 0.000001)
	for index: int in range(steps):
		life._process(step)
		await tree.physics_frame
		_record_trace()

func advance_minutes(minutes: float, step: float = 1.0 / 60.0) -> void:
	await advance(minutes / life.minutes_per_second, step)

func random(label: String) -> RandomNumberGenerator:
	return NpcRoutinePlan.random_for(region_seed, label)

func resident_ids() -> Array[String]:
	var ids: Array[String] = []
	for npc: BaseNpc in tree.get_nodes_in_group(&"town_residents"):
		if npc.health > 0 and not npc.is_queued_for_deletion():
			ids.append(String(npc.get_npc_profile().npc_id))
	ids.sort()
	return ids

func resident(id: String) -> BaseNpc:
	for npc: BaseNpc in tree.get_nodes_in_group(&"town_residents"):
		if String(npc.get_npc_profile().npc_id) == id and npc.health > 0 and not npc.is_queued_for_deletion():
			return npc
	return null

## Ordered change log: an entry is appended only when a resident's state differs from its previous entry.
func trace() -> Array[Dictionary]:
	return _trace.duplicate(true)

func _record_trace() -> void:
	var minute: float = save_game().life.minute
	for id: String in resident_ids():
		var npc: BaseNpc = resident(id)
		var person: Dictionary = save_game().life.get_person(id)
		var routine: NpcDailyRoutine = npc.daily_routine
		if person.is_empty() or routine == null:
			continue
		var entry: Dictionary = {"id": id, "activity": person.activity, "place": person.place,
			"destination": routine.destination.snappedf(0.1),
			# M3 replaces this private read with the actor's task claim.
			"held": routine._held, "sleeping": npc.is_sleeping(),
			"alert_phase": npc.alert_response.phase, "space": String(npc.world_space)}
		if _last_entry.get(id) == entry:
			continue
		_last_entry[id] = entry
		var logged: Dictionary = entry.duplicate()
		logged.minute = minute
		_trace.append(logged)

## Facts that would survive a save/load, taken from the save and the scene's physical remains.
func effects() -> Dictionary:
	var result: Dictionary = save_effects(save_game())
	result.remains = 0
	result.graves = 0
	if life != null and is_instance_valid(life):
		for node: Node in life.get_parent().get_children():
			if node is NpcRemains:
				result.remains += 1
		for node: Node in life.funerals.cemetery.get_children():
			if node.name.ends_with("Grave"):
				result.graves += 1
	return result

## The save-derived part of effects(), usable on a reloaded NpcWorldSave.
func save_effects(save: NpcWorldSave) -> Dictionary:
	var dead: Array[String] = save.dead_npcs.duplicate()
	dead.sort()
	var stages: Dictionary = {}
	for id: String in save.deaths.records:
		stages[id] = save.deaths.records[id].stage
	var coins: int = save.economy.treasury
	for household: String in save.economy.accounts:
		coins += int(save.economy.accounts[household])
	var relationships: Dictionary = {}
	var memory_counts: Dictionary = {}
	var ids: Array = save.population.people.keys()
	ids.sort()
	for id: String in ids:
		var state: Dictionary = save.memory.snapshot(id)
		if state.is_empty():
			continue
		relationships[id] = state.relationship
		memory_counts[id] = {"memories": state.memories.size(), "observations": state.observations.size()}
	return {"dead": dead, "death_records": save.deaths.records.size(), "death_stages": stages,
		"coins": coins, "relationships": relationships, "memory_counts": memory_counts}

## Writes the live save, loads the same file into a fresh NpcWorldSave and compares the two.
## Returns {"error", "before", "after", "effects_before", "effects_after"}; before/after are JSON-normalized.
func reload_save() -> Dictionary:
	var save: NpcWorldSave = save_game()
	var error: Error = save.save_file()
	var before: Dictionary = _normalize(save.to_data())
	var effects_before: Dictionary = _normalize(save_effects(save))
	var reloaded := NpcWorldSave.new()
	reloaded.path = save.path
	if error == OK:
		error = reloaded.load_file(save.path + ".legacy")
	return {"error": error, "before": before, "after": _normalize(reloaded.to_data()),
		"effects_before": effects_before, "effects_after": _normalize(save_effects(reloaded))}

func teardown() -> void:
	if backend != null and is_instance_valid(backend):
		backend.release_all()
	if world != null and is_instance_valid(world):
		world.queue_free()
	await tree.process_frame
	await tree.process_frame
	_cognition.backend = _original_backend
	_cognition.events.backend = _original_backend
	if backend != null and is_instance_valid(backend):
		backend.queue_free()
	await tree.process_frame
	var directory: String = save_path.get_base_dir()
	var base: String = save_path.get_file()
	for name: String in DirAccess.get_files_at(directory):
		if name == base or name.begins_with(base + "."):
			DirAccess.remove_absolute(directory.path_join(name))

func _normalize(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))

func _fail(message: String) -> void:
	problems.append(message)
	push_error(message)
