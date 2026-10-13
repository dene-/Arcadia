extends SceneTree

const Simulation = preload("res://tests/fixtures/npc_simulation_fixture.gd")
const REAL_SAVES: Array[String] = ["user://npc_world.json", "user://npc_memory.json"]
const SYNTHETIC_TEXT: String = "I saw a stranger ring a copper bell at the old well."
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
	events.observe(witness.get_npc_profile(), {"world_minute": sim.save_game().life.minute}, event, witness)
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
