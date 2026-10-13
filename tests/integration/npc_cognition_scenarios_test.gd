extends SceneTree

const Simulation = preload("res://tests/fixtures/npc_simulation_fixture.gd")
const REAL_SAVES: Array[String] = ["user://npc_world_v2.json", "user://npc_world.json", "user://npc_memory.json"]
const SYNTHETIC_TEXT: String = "I saw a stranger ring a copper bell at the old well."
## Measured at 164 KB minds / 221 KB file on load and 237 KB / 303 KB after 2 game hours.
const MAX_MIND_BYTES: int = 500000
const MAX_FILE_BYTES: int = 600000
const MAX_GROWTH_BYTES: int = 150000
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	await _scenario_isolation()
	await _scenario_reload_stability()
	await _scenario_no_information_without_evidence()
	await _scenario_personal_knowledge()
	for failure: String in failures:
		push_error(failure)
	print("NPC cognition scenarios: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _start() -> Simulation:
	var sim := Simulation.new()
	sim.setup(self)
	await sim.load_world()
	_check(sim.problems.is_empty(), "Fixture problems: %s" % [sim.problems])
	return sim

func _scenario_isolation() -> void:
	var before: Dictionary = {}
	for path: String in REAL_SAVES:
		before[path] = FileAccess.get_modified_time(path)
	var original_backend: Node = root.get_node("NpcCognition").backend
	var sim: Simulation = await _start()
	_check(sim.save_game().path != NpcWorldSave.SAVE_PATH, "Fixture kept the real save path")
	_check(sim.resident_ids().size() == sim.save_game().population.people.size(), "Residents missing")
	_check(sim.resident("garrin_holt") != null, "Founder resident not found")
	await sim.advance(5.0)
	_check(sim.backend.total_calls() > 0, "Nothing reached the fake backend")
	_check(sim.backend.call_count("life/routine") > 0, "Routine decisions did not reach the fake backend")
	_check(sim.backend.call_count("life/routine") <= sim.resident_ids().size() * 2,
		"Unexpected request volume for 5 seconds: %d" % sim.backend.call_count("life/routine"))
	_check(not sim.trace().is_empty(), "No trace recorded")
	_check(FileAccess.file_exists(sim.save_path), "Fixture save was not written to the temp path")
	await sim.teardown()
	_check(not FileAccess.file_exists(sim.save_path), "Temp save survived teardown")
	for path: String in REAL_SAVES:
		_check(FileAccess.get_modified_time(path) == before[path], "Real save touched: " + path)
	_check(root.get_node("NpcCognition").backend == original_backend, "Cognition backend was not restored")

func _scenario_reload_stability() -> void:
	var sim: Simulation = await _start()
	var start_minute: float = sim.save_game().life.minute
	await sim.advance_minutes(120.0)
	var elapsed: float = sim.save_game().life.minute - start_minute
	_check(absf(elapsed - 120.0) < 0.5, "Clock advanced %s minutes, expected 120" % elapsed)
	var reload: Dictionary = sim.reload_save()
	_check(reload.error == OK, "Reload failed: %s" % reload.error)
	_check(reload.before == reload.after, "Save changed across reload: " + _first_difference(reload.before, reload.after))
	_check(reload.effects_before == reload.effects_after, "Effects changed across reload")
	var live: Dictionary = sim.effects()
	_check(live.dead.is_empty() and live.remains == 0 and live.graves == 0, "Quiet town produced death effects")
	await sim.teardown()

func _scenario_no_information_without_evidence() -> void:
	var sim: Simulation = await _start()
	await sim.advance(2.0)
	var ids: Array[String] = sim.resident_ids()
	var witness_id: String = ""
	var bystander_id: String = ""
	for first: String in ids:
		for second: String in ids:
			if sim.resident(first).world_space != sim.resident(second).world_space:
				witness_id = first
				bystander_id = second
				break
		if not witness_id.is_empty():
			break
	_check(not witness_id.is_empty(), "No two residents were in different spaces")
	if witness_id.is_empty():
		await sim.teardown()
		return
	var witness: BaseNpc = sim.resident(witness_id)
	var event: Dictionary = {"kind": "synthetic", "text": SYNTHETIC_TEXT, "sense": "sight",
		"player_involved": false, "danger_possible": false, "directly_affected": false,
		"topics": ["town"]}
	var events: NpcEventProcessor = root.get_node("NpcCognition").events
	var minute: float = sim.save_game().life.minute
	var observation: NpcObservation = NpcObservation.from_perception(witness_id, "synthetic:1", minute,
		witness.world_space, event, witness.global_position)
	_check(observation != null, "Synthetic observation was not valid")
	events.observe(witness.get_npc_profile(), {"world_minute": minute}, observation, witness)
	await events.flush(witness_id)
	await sim.advance(3.0)
	var memory: NpcMemoryStore = sim.save_game().memory
	_check(_mentions(memory.snapshot(witness_id), SYNTHETIC_TEXT), "Witness did not record its own observation")
	_check(not _mentions(memory.snapshot(bystander_id), SYNTHETIC_TEXT),
		"%s learned about an event only %s perceived" % [bystander_id, witness_id])
	for id: String in sim.resident_ids():
		if id != witness_id:
			_check(not _mentions(memory.snapshot(id), SYNTHETIC_TEXT), "%s learned the unperceived event" % id)
	await sim.teardown()

func _mentions(state: Dictionary, text: String) -> bool:
	for memory: Dictionary in state.get("memories", []):
		if text in str(memory.gist):
			return true
	for observation: Dictionary in state.get("observations", []):
		if text in str(observation.text):
			return true
	for event: String in state.get("recent_events", []):
		if text in event:
			return true
	return false

func _first_difference(before: Variant, after: Variant, path: String = "") -> String:
	if before is Dictionary and after is Dictionary:
		for key: Variant in before:
			if not after.has(key):
				return "%s/%s missing after" % [path, key]
			var inner: String = _first_difference(before[key], after[key], "%s/%s" % [path, key])
			if not inner.is_empty():
				return inner
		for key: Variant in after:
			if not before.has(key):
				return "%s/%s missing before" % [path, key]
		return ""
	return "" if before == after else "%s: %s != %s" % [path, str(before).left(80), str(after).left(80)]

func _knowledge_of(sim: Simulation, id: String) -> NpcKnowledge:
	return sim.save_game().minds.get_mind(id).knowledge

func _guard_ids(sim: Simulation) -> Array[String]:
	var guards: Array[String] = []
	for id: String in sim.save_game().population.people:
		if sim.save_game().population.people[id].job == "guard":
			guards.append(id)
	guards.sort()
	return guards

## Residents hold public knowledge from the start and learn everything else by being near it.
func _scenario_personal_knowledge() -> void:
	var sim: Simulation = await _start()
	var guards: Array[String] = _guard_ids(sim)
	_check(guards.size() >= 2, "Fixture town has fewer than two guards")
	var ids: Array[String] = sim.resident_ids()
	for id: String in ids:
		var places: Array[String] = []
		for fact: Dictionary in _knowledge_of(sim, id).known_help_places():
			places.append(String(fact.value.place))
		for guard_id: String in guards:
			_check("home:" + guard_id in places, "%s does not know the home of guard %s" % [id, guard_id])
		for index: int in 4:
			_check("patrol:%d" % index in places, "%s does not know patrol point %d" % [id, index])
		for other: String in ids:
			_check(_knowledge_of(sim, id).known_locations(other).is_empty(),
				"%s knows where %s is before seeing it" % [id, other])
	var before: Dictionary = _size_report(sim)
	var spaces: Dictionary = {}
	var positions: Dictionary = {}
	for id: String in ids:
		spaces[id] = sim.resident(id).world_space
		positions[id] = sim.resident(id).global_position
	# One life tick: nobody can have seen a guard that stayed in another space or far away.
	await sim.advance(1.1)
	var checked: int = 0
	for id: String in ids:
		for guard_id: String in guards:
			var observer: BaseNpc = sim.resident(id)
			var guard: BaseNpc = sim.resident(guard_id)
			if id == guard_id or observer == null or guard == null or NpcPerception.can_see(observer, guard):
				continue
			if observer.world_space != spaces[id] or guard.world_space != spaces[guard_id]:
				continue
			var separate: bool = spaces[id] != spaces[guard_id]
			var far: bool = spaces[id] == spaces[guard_id] and (positions[id] as Vector2).distance_to(
				positions[guard_id]) > observer.npc_data.vision_radius + 300.0 and observer.global_position.distance_to(
				guard.global_position) > observer.npc_data.vision_radius + 300.0
			if not separate and not far:
				continue
			checked += 1
			_check(_knowledge_of(sim, id).known_locations(guard_id).is_empty(),
				"%s knows the location of guard %s it never saw" % [id, guard_id])
	_check(checked > 0, "No resident/guard pair out of sight was found")
	await sim.advance_minutes(30.0)
	await _scenario_adjacent_sighting(sim)
	await sim.advance_minutes(90.0)
	var after: Dictionary = _size_report(sim)
	print("NPC knowledge sizes (bytes) at start: ", before, " after 2 game hours: ", after)
	_check(int(after.minds) < MAX_MIND_BYTES, "Mind section grew to %d bytes" % int(after.minds))
	_check(int(after.minds) - int(before.minds) < MAX_GROWTH_BYTES,
		"Minds grew by %d bytes in 2 game hours" % (int(after.minds) - int(before.minds)))
	_check(int(after.file) < MAX_FILE_BYTES, "Save file grew to %d bytes" % int(after.file))
	_check(int(after.max_facts) < NpcKnowledge.MAX_FACTS, "A resident reached the knowledge capacity")
	var reload: Dictionary = sim.reload_save()
	_check(reload.error == OK, "Reload failed: %s" % reload.error)
	var with_facts: int = 0
	for id: String in ids:
		var saved: Dictionary = reload.before.minds.minds[id].knowledge
		_check(reload.after.minds.minds[id].knowledge == saved, "%s lost knowledge across reload" % id)
		if not (saved.facts as Array).is_empty():
			with_facts += 1
	# Public facts are re-derived on load; only personal evidence (sightings, reports) is saved.
	_check(with_facts > 0, "No resident saved any personal knowledge after 2 game hours")
	await sim.teardown()

func _scenario_adjacent_sighting(sim: Simulation) -> void:
	var outdoors: Array[BaseNpc] = []
	for id: String in sim.resident_ids():
		var npc: BaseNpc = sim.resident(id)
		if npc.world_space == &"outdoors" and not npc.is_sleeping():
			outdoors.append(npc)
	_check(outdoors.size() >= 2, "Fewer than two awake residents are outdoors")
	if outdoors.size() < 2:
		return
	var observer: BaseNpc = outdoors[0]
	var target: BaseNpc = outdoors[1]
	var observer_id: String = String(observer.get_npc_profile().npc_id)
	var target_id: String = String(target.get_npc_profile().npc_id)
	target.global_position = observer.global_position + Vector2(12.0, 0.0)
	await sim.advance(1.1)
	var sightings: Array[Dictionary] = _knowledge_of(sim, observer_id).known_locations(target_id)
	_check(not sightings.is_empty(), "%s standing next to %s has no sighting" % [observer_id, target_id])
	if not sightings.is_empty():
		_check(sightings[0].status == "OBSERVED" and sightings[0].source_id == NpcKnowledge.SELF_SOURCE,
			"A sighting must be first-hand")
		_check(sightings[0].value.space == "outdoors", "Sighting space was not recorded")
		_check(absf(float(sightings[0].observed_minute) - sim.save_game().life.minute) < 2.0,
			"Sighting is not recent")

func _size_report(sim: Simulation) -> Dictionary:
	var save: NpcWorldSave = sim.save_game()
	var minds: int = JSON.stringify(save.minds.to_data()).length()
	var max_facts: int = 0
	for id: String in sim.resident_ids():
		max_facts = maxi(max_facts, (_knowledge_of(sim, id).to_data().facts as Array).size())
	_check(save.save_file() == OK, "Save failed")
	return {"minds": minds, "file": FileAccess.get_file_as_bytes(sim.save_path).size(), "max_facts": max_facts}
