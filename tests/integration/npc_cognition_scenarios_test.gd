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
	await _scenario_sleeper_shelters()
	await _scenario_safety_ends_session()
	await _scenario_reload_mid_travel()
	await _scenario_crossing_invitations()
	await _scenario_player_takes_over_session()
	await _scenario_urgent_resident_refuses_player()
	await _scenario_commitment_survives_reload()
	await _scenario_death_recovery()
	for failure: String in failures:
		push_error(failure)
	print("NPC cognition scenarios: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

## `minute` (when not negative) sets the town clock before the world loads.
func _start(minute: float = -1.0) -> Simulation:
	var sim := Simulation.new()
	sim.setup(self)
	if minute >= 0.0:
		sim.save_game().life.minute = minute
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

func _task(sim: Simulation, id: String) -> NpcTask:
	var brain: NpcBrain = sim.life.brain_for(id)
	return brain.controller.current if brain != null else null

func _claims(sim: Simulation, id: String) -> Dictionary:
	return sim.life.brain_for(id).debug_snapshot().claims

func _journey_owner(sim: Simulation, id: String) -> String:
	var journey: Dictionary = sim.life.buildings._journeys.get(id, {})
	return String(journey.owner) if journey.get("state") == &"traveling" else ""

## Every trace entry of `id` from `minute` on shows the running task as the only locomotion owner.
func _check_single_owner(sim: Simulation, id: String, minute: float, label: String) -> void:
	for entry: Dictionary in sim.trace():
		if entry.id == id and float(entry.minute) >= minute:
			_check(entry.locomotion == entry.task_id,
				"%s: locomotion owned by '%s' while '%s' runs at %.1f" % [label, entry.locomotion, entry.task_id, entry.minute])

## No resident sleeps or travels without a task owning that state.
func _check_owned_states(sim: Simulation, label: String) -> void:
	for id: String in sim.resident_ids():
		var npc: BaseNpc = sim.resident(id)
		var task: NpcTask = _task(sim, id)
		if npc.is_sleeping():
			_check(task != null and task.kind == &"routine" and task.phase == NpcRoutineTask.PHASE_SLEEP,
				"%s: %s sleeps without a rest task" % [label, id])
		var owner: String = _journey_owner(sim, id)
		if not owner.is_empty():
			_check(task != null and task.task_id == owner, "%s: %s travels for '%s', not its running task" % [label, id, owner])

## (a) A sleeper stirs on a noise without waking, then a SHELTER concern orients, wakes and moves it
## to a refuge; once the concern expires a routine takes over.
func _scenario_sleeper_shelters() -> void:
	var sim: Simulation = await _start(60.0)
	var id: String = ""
	for attempt: int in 60:
		for candidate: String in sim.resident_ids():
			var resident: BaseNpc = sim.resident(candidate)
			var current: NpcTask = _task(sim, candidate)
			if not resident.is_in_group(&"town_guards") and resident.is_sleeping() and current != null \
					and current.kind == &"routine" and current.phase == NpcRoutineTask.PHASE_SLEEP:
				id = candidate
				break
		if not id.is_empty():
			break
		await sim.advance(1.0)
	_check(not id.is_empty(), "(a) Nobody went to sleep in a rest task")
	if id.is_empty():
		await sim.teardown()
		return
	var npc: BaseNpc = sim.resident(id)
	var brain: NpcBrain = sim.life.brain_for(id)
	var rest_id: String = _task(sim, id).task_id
	var start_minute: float = sim.save_game().life.minute
	var start_space: StringName = npc.world_space
	var start_position: Vector2 = npc.global_position
	# The cognition pipeline's reflex and provisional concern, then a SHELTER classification.
	var event: Dictionary = {"origin_id": "noise:m3a", "text": "Something heavy crashed against the door.",
		"sense": "hearing", "danger_possible": true, "directly_affected": false}
	npc.alert_response.notice(npc, event)
	sim.save_game().life.notice_perception(id, event, String(npc.world_space))
	sim.save_game().life.assess_perception(id, event, {"safety_response": "SHELTER"})
	_check(npc.alert_response.phase == "stirring", "(a) A sleeper did not stir on the noise")
	var safety_id: String = ""
	var oriented_asleep: bool = false
	var fled: bool = false
	for frame: int in 600:
		await sim.advance(1.0 / 60.0)
		if npc.alert_response.phase == "stirring":
			_check(npc.is_sleeping(), "(a) The sleeper woke inside the stirring window")
		var current: NpcTask = _task(sim, id)
		if current == null or current.kind != &"safety":
			continue
		if safety_id.is_empty():
			safety_id = current.task_id
			_check(_claims(sim, id) == {"locomotion": safety_id, "conversation": safety_id},
				"(a) The shelter task does not own both claims: %s" % [_claims(sim, id)])
			_check(brain.controller.suspended != null and brain.controller.suspended.task_id == rest_id,
				"(a) The rest task was not suspended under the shelter task")
		if current.phase == NpcSafetyTask.PHASE_ORIENT and npc.is_sleeping():
			oriented_asleep = true
		if current.phase == NpcSafetyTask.PHASE_FLEE and not npc.is_sleeping() \
				and _journey_owner(sim, id) == safety_id:
			fled = true
			break
	_check(not safety_id.is_empty(), "(a) The SHELTER concern produced no safety task")
	_check(oriented_asleep, "(a) The shelter task did not orient while the sleeper stirred")
	_check(fled, "(a) The resident never woke and set off for the refuge")
	await sim.advance(10.0)
	_check(npc.world_space != start_space or npc.global_position.distance_to(start_position) > 16.0,
		"(a) The resident did not travel towards the refuge")
	# Let the concern expire; the shelter task completes and a routine takes over.
	var until: float = float(sim.save_game().life.get_person(id).safety.get("until", start_minute))
	sim.save_game().life.advance(maxf(0.0, until - sim.save_game().life.minute) + 0.5)
	var resumed: bool = false
	for second: int in 5:
		await sim.advance(1.0)
		var current: NpcTask = _task(sim, id)
		if current != null and current.kind == &"routine":
			resumed = true
			break
	_check(resumed, "(a) No routine resumed after the concern expired")
	_check(brain.task_state(safety_id) != "running", "(a) The expired shelter task kept running")
	_check_single_owner(sim, id, start_minute, "(a)")
	await sim.teardown()

## (b) A safety task on one participant ends the session for both; the session's late
## release cannot take the safety task's claims and its late assessment delivers no rumor.
func _scenario_safety_ends_session() -> void:
	var sim: Simulation = await _start(600.0)
	await sim.advance(2.0)
	var pair: Array[BaseNpc] = _free_residents(sim, 2)
	_check(pair.size() == 2, "(b) Fewer than two free residents are outdoors")
	if pair.size() < 2:
		await sim.teardown()
		return
	var first: BaseNpc = pair[0]
	var second: BaseNpc = pair[1]
	var first_id: String = String(first.get_npc_profile().npc_id)
	var second_id: String = String(second.get_npc_profile().npc_id)
	second.global_position = first.global_position + Vector2(12.0, 0.0)
	var life_state: TownLifeState = sim.save_game().life
	life_state.rumors.observe(first_id, first.get_npc_profile().profile_name,
		{"origin_id": "test:m4b", "text": SYNTHETIC_TEXT, "sense": "sight", "player_involved": false},
		{"remember": true, "importance": 1.0}, life_state.minute)
	sim.backend.queue_response("life/social", {"policy": {"engage": true, "another_exchange": false,
		"topic_index": 0, "tone": "FRIENDLY"}})
	sim.backend.queue_response("life/listen", {"policy": {"belief": 0.9, "importance": 0.8,
		"remember": true, "affinity": 0.01, "trust_player": 0.0}})
	sim.backend.hold("life/listen")
	sim.life.encounters.consider(first, second)
	_check(sim.life.encounters.session_phase(first_id) == TownEncounters.PHASE_CONVERSE
		and sim.life.encounters.session_phase(second_id) == TownEncounters.PHASE_CONVERSE,
		"(b) The session did not reach conversation: %s / %s" % [sim.life.encounters.diagnostics(first_id),
			sim.life.brain_for(second_id).debug_snapshot()])
	if not sim.life.encounters.is_busy(first_id):
		sim.backend.release("life/listen")
		await sim.teardown()
		return
	var session_owner: String = String(_claims(sim, first_id).conversation)
	for id: String in [first_id, second_id]:
		var social: NpcTask = _task(sim, id)
		_check(social != null and social.kind == &"social", "(b) %s is not held by a social task" % id)
		_check(social != null and _claims(sim, id) == {"locomotion": social.task_id, "conversation": session_owner},
			"(b) %s claims do not belong to the session: %s" % [id, _claims(sim, id)])
	_check(session_owner.begins_with("session:"), "(b) The conversation claim has no session owner")
	var event: Dictionary = {"origin_id": "attack:m3b", "text": "Someone struck me.",
		"sense": "touch", "danger_possible": true, "directly_affected": true}
	sim.save_game().life.notice_perception(second_id, event, String(second.world_space))
	var safety: NpcTask = null
	for frame: int in 90:
		await sim.advance(1.0 / 60.0)
		var current: NpcTask = _task(sim, second_id)
		if current != null and current.kind == &"safety":
			safety = current
			break
	_check(safety != null, "(b) The SHELTER concern produced no safety task")
	if safety == null:
		sim.backend.release("life/listen")
		await sim.teardown()
		return
	_check(not sim.life.encounters.is_busy(first_id) and not sim.life.encounters.is_busy(second_id),
		"(b) The session outlived a participant's safety task")
	_check(_claims(sim, first_id).conversation != session_owner, "(b) The partner kept the session's conversation claim")
	var partner: NpcTask = _task(sim, first_id)
	_check(partner == null or partner.kind != &"social", "(b) The partner is still held by the session")
	sim.backend.release("life/listen")
	await sim.advance(0.5)
	_check(_task(sim, second_id) == safety and safety.status == NpcTask.Status.RUNNING,
		"(b) The session's late release ended the safety task")
	_check(_claims(sim, second_id) == {"locomotion": safety.task_id, "conversation": safety.task_id},
		"(b) The session's late release took the safety task's claims: %s" % [_claims(sim, second_id)])
	_check(not _mentions_rumor(life_state, second_id),
		"(b) The ended session's late assessment delivered the rumor")
	await sim.teardown()

## Awake residents outdoors that are free to start a social session or be spoken to.
func _free_residents(sim: Simulation, count: int) -> Array[BaseNpc]:
	var found: Array[BaseNpc] = []
	for id: String in sim.resident_ids():
		var npc: BaseNpc = sim.resident(id)
		if npc.is_in_group(&"town_guards") or npc.world_space != &"outdoors" or npc.is_sleeping() \
				or npc.daily_routine.activity == "rest" or not npc.can_speak_reaction() \
				or sim.life.encounters.is_busy(id) or sim.life.funerals.is_assigned(id) \
				or float(sim.save_game().life.get_person(id).social_after) > sim.save_game().life.minute \
				or _task(sim, id) == null:
			continue
		found.append(npc)
		if found.size() == count:
			break
	return found

func _resident_id(npc: BaseNpc) -> String:
	return String(npc.get_npc_profile().npc_id)

## Puts the player within earshot of `npc`; the check fails when no landing spot was found.
func _place_player_near(sim: Simulation, npc: BaseNpc) -> BasePlayer:
	var player: BasePlayer = sim.world.get_node("BasePlayer")
	player.set_physics_process(false)
	var placed: bool = false
	for offset: Vector2 in [Vector2(10, 0), Vector2(-10, 0), Vector2(0, 30), Vector2(0, -30), Vector2(60, 0)]:
		if sim.life.buildings._transfer(player, "player:%d" % player.get_instance_id(), &"outdoors",
				npc.global_position + offset):
			placed = true
			break
	_check(placed and player.world_space == npc.world_space
		and player.global_position.distance_to(npc.global_position) <= 150.0,
		"The player could not be placed near %s (placed %s, %s at %s, npc %s at %s)" % [_resident_id(npc), placed,
			player.world_space, player.global_position, npc.world_space, npc.global_position])
	return player

func _bubble_shows(npc: BaseNpc, text: String) -> bool:
	var bubble: Node2D = npc.get_node("ReactionBubble")
	return bubble.visible and (bubble.get_node("Panel/Text") as Label).text == text

## (d) Crossing invitations: the second invitation is dropped, one session holds both residents and
## nothing is left claimed when it ends.
func _scenario_crossing_invitations() -> void:
	var sim: Simulation = await _start(600.0)
	await sim.advance(2.0)
	var pair: Array[BaseNpc] = _free_residents(sim, 2)
	_check(pair.size() == 2, "(d) Fewer than two free residents are outdoors")
	if pair.size() < 2:
		await sim.teardown()
		return
	var first_id: String = _resident_id(pair[0])
	var second_id: String = _resident_id(pair[1])
	pair[1].global_position = pair[0].global_position + Vector2(12.0, 0.0)
	var encounters: TownEncounters = sim.life.encounters
	var before: Dictionary = {first_id: _claims(sim, first_id), second_id: _claims(sim, second_id)}
	var tasks: Dictionary = {first_id: _task(sim, first_id), second_id: _task(sim, second_id)}
	var judgments: int = sim.backend.call_count("life/social")
	sim.backend.hold("life/social")
	encounters.consider(pair[0], pair[1])
	encounters.consider(pair[1], pair[0])
	for id: String in [first_id, second_id]:
		_check(encounters.session_phase(id) == TownEncounters.PHASE_INVITE,
			"(d) %s is not waiting on one invitation: '%s'" % [id, encounters.session_phase(id)])
		_check(_claims(sim, id) == before[id], "(d) An invitation took claims for %s: %s" % [id, _claims(sim, id)])
		_check(_task(sim, id) == tasks[id], "(d) An invitation replaced the task of %s" % id)
	_check(sim.backend.call_count("life/social") == judgments + 1,
		"(d) The crossing invitation made %d social judgments" % (sim.backend.call_count("life/social") - judgments))
	sim.backend.queue_response("life/social", {"policy": {"engage": true, "another_exchange": false,
		"topic_index": -1, "tone": "FRIENDLY"}})
	sim.backend.queue_response("life/social", {"policy": {"engage": false, "another_exchange": false,
		"topic_index": -1, "tone": "RESERVED"}})
	sim.backend.release("life/social")
	_check(not encounters.is_busy(first_id) and not encounters.is_busy(second_id),
		"(d) The session never ended: %s" % [encounters.diagnostics(first_id)])
	_check(encounters.diagnostics(first_id).get("outcome") in ["offscreen_exchange", "declined", "bubble_displayed"],
		"(d) The session did not complete: %s" % [encounters.diagnostics(first_id)])
	for id: String in [first_id, second_id]:
		_check(_claims(sim, id) == before[id], "(d) %s kept session claims after it ended: %s" % [id, _claims(sim, id)])
		_check(_task(sim, id) == tasks[id], "(d) %s did not return to its own task" % id)
		var history: Array = sim.save_game().life.get_person(id).recent_social
		var sessions: Dictionary = {}
		for entry: Dictionary in history:
			sessions[entry.session_id] = true
		_check(sessions.size() == 1, "(d) %s took part in %d sessions" % [id, sessions.size()])
	await sim.advance(2.0)
	_check(not encounters.is_busy(first_id) and not encounters.is_busy(second_id), "(d) A session restarted at once")
	await sim.teardown()

## (e) The player takes over a resident in a session: both residents are released, and a late
## reply of the ended session neither speaks nor delivers the rumor, nor ends the player's session.
func _scenario_player_takes_over_session() -> void:
	var sim: Simulation = await _start(600.0)
	await sim.advance(2.0)
	var pair: Array[BaseNpc] = _free_residents(sim, 2)
	_check(pair.size() == 2, "(e) Fewer than two free residents are outdoors")
	if pair.size() < 2:
		await sim.teardown()
		return
	var first: BaseNpc = pair[0]
	var second: BaseNpc = pair[1]
	var first_id: String = _resident_id(first)
	var second_id: String = _resident_id(second)
	second.global_position = first.global_position + Vector2(12.0, 0.0)
	_place_player_near(sim, first)
	var life_state: TownLifeState = sim.save_game().life
	life_state.rumors.observe(first_id, first.get_npc_profile().profile_name,
		{"origin_id": "test:m4e", "text": SYNTHETIC_TEXT, "sense": "sight", "player_involved": false},
		{"remember": true, "importance": 1.0}, life_state.minute)
	var late_line: String = "The copper bell rang at the old well."
	sim.backend.queue_response("life/social", {"policy": {"engage": true, "another_exchange": false,
		"topic_index": 0, "tone": "FRIENDLY"}})
	sim.backend.queue_response("life/listen", {"policy": {"belief": 0.9, "importance": 0.8,
		"remember": true, "affinity": 0.01, "trust_player": 0.0}})
	sim.backend.queue_response("life/say", {"response": late_line})
	sim.backend.hold("life/say")
	sim.life.encounters.consider(first, second)
	var session_owner: String = String(_claims(sim, second_id).conversation)
	_check(sim.life.encounters.session_phase(first_id) == TownEncounters.PHASE_CONVERSE
		and sim.life.encounters.session_phase(second_id) == TownEncounters.PHASE_CONVERSE
		and sim.backend.call_count("life/say") == 1,
		"(e) The session did not reach its spoken line: %s" % [sim.life.encounters.diagnostics(first_id)])
	_check(session_owner.begins_with("session:social:"), "(e) The conversation claim has no session owner")
	var dialog: Node = root.get_node("DialogManager")
	_check(dialog._bind_dialog_ui(), "(e) World dialogue UI could not be bound")
	_check(dialog._start_dialog(second), "(e) The player was refused by a resident in a plain conversation")
	var player_owner: String = String(_claims(sim, second_id).conversation)
	_check(player_owner.begins_with("session:player:"), "(e) The player did not take the conversation claim: %s" % [_claims(sim, second_id)])
	_check(_claims(sim, second_id).locomotion == player_owner and _task(sim, second_id).kind == &"social",
		"(e) The player's hold is not a social task owning both claims: %s" % [_claims(sim, second_id)])
	_check(not sim.life.encounters.is_busy(first_id) and not sim.life.encounters.is_busy(second_id),
		"(e) The encounter outlived the player's takeover")
	_check(String(_claims(sim, first_id).conversation) != session_owner and not String(_claims(sim, first_id).locomotion).begins_with("session:social:"),
		"(e) The partner kept the session's claims: %s" % [_claims(sim, first_id)])
	var partner: NpcTask = _task(sim, first_id)
	_check(partner == null or partner.kind != &"social", "(e) The partner is still held by the session")
	var calls_before: int = sim.backend.call_count("life/say")
	sim.backend.release("life/say")
	_check(sim.backend.call_count("life/say") == calls_before, "(e) The ended session asked for another line")
	await sim.advance(0.5)
	for npc: BaseNpc in [first, second]:
		_check(not _bubble_shows(npc, late_line), "(e) The ended session's late reply was spoken by %s" % _resident_id(npc))
	_check(not _mentions_rumor(life_state, second_id), "(e) The ended session's late reply delivered the rumor")
	_check(dialog.is_dialog_open() and String(_claims(sim, second_id).conversation) == player_owner,
		"(e) The ended session's late reply disturbed the player's session: %s" % [_claims(sim, second_id)])
	dialog.close_dialog()
	_check(String(_claims(sim, second_id).conversation).is_empty()
		and not _claims(sim, second_id).locomotion.begins_with("session:"),
		"(e) Closing the dialog left the player's claims: %s" % [_claims(sim, second_id)])
	await sim.teardown()

## (f) A resident on an urgent safety task refuses the player with a short line and keeps its task.
func _scenario_urgent_resident_refuses_player() -> void:
	var sim: Simulation = await _start(600.0)
	await sim.advance(2.0)
	var free: Array[BaseNpc] = _free_residents(sim, 1)
	_check(free.size() == 1, "(f) No free resident is outdoors")
	if free.is_empty():
		await sim.teardown()
		return
	var npc: BaseNpc = free[0]
	var id: String = _resident_id(npc)
	var event: Dictionary = {"origin_id": "attack:m4f", "text": "Someone struck me.",
		"sense": "touch", "danger_possible": true, "directly_affected": true}
	sim.save_game().life.notice_perception(id, event, String(npc.world_space))
	var safety: NpcTask = null
	for frame: int in 90:
		await sim.advance(1.0 / 60.0)
		var current: NpcTask = _task(sim, id)
		if current != null and current.kind == &"safety":
			safety = current
			break
	_check(safety != null, "(f) The danger produced no safety task")
	if safety == null:
		await sim.teardown()
		return
	var claims: Dictionary = _claims(sim, id)
	var dialog: Node = root.get_node("DialogManager")
	_check(dialog._bind_dialog_ui(), "(f) World dialogue UI could not be bound")
	_check(not dialog._start_dialog(npc), "(f) A resident on an urgent task accepted the player")
	_check(not dialog.is_dialog_open(), "(f) A dialog opened with a refusing resident")
	var bubble: Node2D = npc.get_node("ReactionBubble")
	var shown: String = (bubble.get_node("Panel/Text") as Label).text
	_check(bubble.visible and shown in dialog.REFUSAL_LINES, "(f) The refusal line was not shown: '%s'" % shown)
	_check(_task(sim, id) == safety and safety.status == NpcTask.Status.RUNNING, "(f) The refusal changed the safety task")
	_check(_claims(sim, id) == claims, "(f) The refusal changed the claims: %s" % [_claims(sim, id)])
	await sim.advance(1.0)
	_check(_task(sim, id) == safety and _claims(sim, id) == claims and not dialog.is_dialog_open(),
		"(f) The refused session left a trace: %s" % [_claims(sim, id)])
	await sim.teardown()

## (g) A commitment backed by a prospective memory completes once when its task ends, across reloads.
func _scenario_commitment_survives_reload() -> void:
	var sim: Simulation = await _start(480.0)
	await sim.advance(2.0)
	var free: Array[BaseNpc] = _free_residents(sim, 1)
	_check(free.size() == 1, "(g) No free resident is outdoors")
	if free.is_empty():
		await sim.teardown()
		return
	var id: String = _resident_id(free[0])
	var memory: NpcMemoryStore = sim.save_game().memory
	memory.ensure_npc(free[0].get_npc_profile())
	var result: Dictionary = {"response": "I will tell the guard.", "replies": ["Thanks.", "Good.", "Bye."],
		"memory_writes": [{"type": "prospective", "gist": "Promised to report the copper bell.",
			"source": "player_claim", "topics": ["bell"], "people": ["player"]}], "recalled_memory_ids": []}
	_check(memory.commit_exchange(id, "Tell the guard.", result, Simulation.FakeService.valid_policy(), [], [], "player:m4g"),
		"(g) The prospective memory was not committed")
	var memory_id: String = ""
	for record: Dictionary in memory.snapshot(id).memories:
		if record.type == "prospective":
			memory_id = String(record.id)
	_check(not memory_id.is_empty(), "(g) No prospective memory was stored")
	var minute: float = sim.save_game().life.minute
	var commitments: NpcCommitments = sim.save_game().minds.get_mind(id).commitments
	var evidence: Array[String] = ["memory:" + memory_id]
	var promise: String = commitments.create("report_discovery", [] as Array[String], evidence, minute)
	_check(not promise.is_empty(), "(g) The commitment was not created")
	var target: Vector2 = sim.life.navigation.nearest(free[0].global_position + Vector2(220.0, 0.0))
	var errand := NpcRoutineTask.create({"activity": "report", "place": "outdoors", "label": "Reporting",
		"space": "outdoors", "point": [target.x, target.y], "until_minute": minute + 6.0}, sim.life.tuning)
	errand.commitment_ids = [promise] as Array[String]
	_check(sim.life.brain_for(id).request_task(errand), "(g) The errand was refused")
	await sim.advance(0.5)
	_check(_task(sim, id) == errand and errand.status == NpcTask.Status.RUNNING, "(g) The errand is not running")
	await sim.reload_world()
	_check(sim.problems.is_empty(), "(g) Reload problems: %s" % [sim.problems])
	var mind: NpcMindState = sim.save_game().minds.get_mind(id)
	_check(mind.commitments.get_commitment(promise).get("status") == "open", "(g) The commitment was resolved by the reload")
	var restored: NpcTask = _task(sim, id)
	_check(restored != null and restored.task_id == errand.task_id and restored.commitment_ids == errand.commitment_ids,
		"(g) The errand was not restored with its commitment: %s" % [restored.checkpoint() if restored != null else {}])
	_check(not _completed(sim, id, memory_id), "(g) The intention completed before the errand did")
	var arrived: bool = false
	for second: int in 60:
		await sim.advance(1.0)
		if mind.commitments.get_commitment(promise).get("status") != "open":
			arrived = true
			break
	mind = sim.save_game().minds.get_mind(id)
	_check(arrived or mind.commitments.get_commitment(promise).get("status") != "open", "(g) The restored errand never finished")
	var record: Dictionary = mind.commitments.get_commitment(promise)
	_check(record.get("status") == "completed", "(g) The commitment ended as %s" % record.get("status"))
	_check(_completed(sim, id, memory_id), "(g) The completed commitment did not complete its intention")
	var resolved_minute: float = float(record.get("resolved_minute", -1.0))
	await sim.reload_world()
	await sim.advance_minutes(5.0)
	mind = sim.save_game().minds.get_mind(id)
	record = mind.commitments.get_commitment(promise)
	_check(record.get("status") == "completed" and absf(float(record.get("resolved_minute", -1.0)) - resolved_minute) < 0.001,
		"(g) The commitment resolved again after reload (was %s): %s" % [resolved_minute, record])
	_check(_completed(sim, id, memory_id), "(g) The intention lost its completion across reload")
	_check(mind.commitments.open_commitments().is_empty(), "(g) A commitment stayed open: %s" % [mind.commitments.open_commitments()])
	await sim.teardown()

func _completed(sim: Simulation, id: String, memory_id: String) -> bool:
	for record: Dictionary in sim.save_game().memory.snapshot(id).memories:
		if record.id == memory_id:
			return record.get("completed") == true
	return false

func _mentions_rumor(life_state: TownLifeState, id: String) -> bool:
	for rumor: Dictionary in life_state.rumors.get_known(id, life_state.minute):
		if SYNTHETIC_TEXT in str(rumor):
			return true
	return false

## (c) Reloading mid-travel restores the task, which re-routes from the saved position; no state is
## left without an owning task and nobody stays inactive for long.
func _scenario_reload_mid_travel() -> void:
	var sim: Simulation = await _start(480.0)
	var id: String = ""
	for attempt: int in 30:
		await sim.advance(0.5)
		for candidate: String in sim.resident_ids():
			var current: NpcTask = _task(sim, candidate)
			if current != null and current.kind == &"routine" and current.phase == NpcRoutineTask.PHASE_TRAVEL \
					and _journey_owner(sim, candidate) == current.task_id \
					and sim.resident(candidate).world_space == &"outdoors":
				id = candidate
				break
		if not id.is_empty():
			break
	_check(not id.is_empty(), "(c) Nobody was travelling for a routine")
	if id.is_empty():
		await sim.teardown()
		return
	var task_id: String = _task(sim, id).task_id
	await sim.reload_world()
	_check(sim.problems.is_empty(), "(c) Reload problems: %s" % [sim.problems])
	var saved: Array = sim.save_game().life.get_person(id).position
	var saved_position := Vector2(float(saved[0]), float(saved[1]))
	var npc: BaseNpc = sim.resident(id)
	var restored: NpcTask = _task(sim, id)
	_check(restored != null and restored.task_id == task_id and restored.phase == NpcRoutineTask.PHASE_TRAVEL,
		"(c) The travelling routine was not restored: %s" % [restored.checkpoint() if restored != null else {}])
	_check(npc.global_position.distance_to(saved_position) <= 4.0,
		"(c) %s restored at %s, saved at %s" % [id, npc.global_position, saved_position])
	_check(_journey_owner(sim, id) == task_id, "(c) The restored task did not re-route")
	_check_owned_states(sim, "(c) after reload")
	var reload_minute: float = sim.save_game().life.minute
	await sim.advance(2.0)
	_check(npc.global_position.distance_to(saved_position) > 4.0 or _task(sim, id) == null
		or _task(sim, id).task_id != task_id or _task(sim, id).phase != NpcRoutineTask.PHASE_TRAVEL,
		"(c) The restored traveller did not move")
	await sim.advance_minutes(10.0)
	_check_owned_states(sim, "(c) 10 minutes later")
	for resident: String in sim.resident_ids():
		var current: NpcTask = _task(sim, resident)
		var active: bool = current != null and current.status == NpcTask.Status.RUNNING
		var replanning: bool = current == null and (sim.life._pending.has(resident) or sim.life._routine_due(resident))
		_check(active or replanning, "(c) %s is inactive with nothing pending" % resident)
	_check_idle_bounded(sim, reload_minute, 4.5, "(c)")
	await sim.teardown()

## No resident runs without a task for longer than `limit` game minutes after `from`.
func _check_idle_bounded(sim: Simulation, from: float, limit: float, label: String) -> void:
	var idle_since: Dictionary = {}
	var end: float = sim.save_game().life.minute
	for entry: Dictionary in sim.trace():
		if float(entry.minute) < from:
			continue
		if String(entry.task_id).is_empty():
			if not idle_since.has(entry.id):
				idle_since[entry.id] = float(entry.minute)
		elif idle_since.has(entry.id):
			_check(float(entry.minute) - float(idle_since[entry.id]) <= limit,
				"%s %s idled %.1f minutes" % [label, entry.id, float(entry.minute) - float(idle_since[entry.id])])
			idle_since.erase(entry.id)
	for id: String in idle_since:
		_check(end - float(idle_since[id]) <= limit, "%s %s still idle after %.1f minutes" % [label, id, end - float(idle_since[id])])

# --- M5: watch and death recovery ---

## One town: (h) a patrol resumes after an intervention; (i) a full report, recovery and burial
## across a mid-carry reload; (j) a killed carrier leaves the body where it fell; (k) with no guard
## left a witness defers. Later steps reuse the world the earlier ones changed.
func _scenario_death_recovery() -> void:
	var sim: Simulation = await _start(960.0)
	await sim.advance(2.0)
	await _patrol_after_intervention(sim)
	if await _recovery_with_reload(sim) and await _carrier_killed(sim):
		await _no_guard_left(sim)
	await sim.teardown()

## (h) A patrolling guard intervenes in an assault, stands down when the attacker surrenders and
## then resumes the same patrol.
func _patrol_after_intervention(sim: Simulation) -> void:
	var guard_id: String = ""
	for id: String in _guard_ids(sim):
		var npc: BaseNpc = sim.resident(id)
		var task: NpcTask = _task(sim, id)
		if npc != null and npc.world_space == &"outdoors" and task is NpcGuardTask \
				and task.phase == NpcGuardTask.PHASE_PATROL:
			guard_id = id
			break
	_check(not guard_id.is_empty(), "(h) No guard is patrolling outdoors")
	var free: Array[BaseNpc] = _free_residents(sim, 1)
	_check(free.size() == 1, "(h) No free resident is outdoors")
	if guard_id.is_empty() or free.is_empty():
		return
	var guard: BaseNpc = sim.resident(guard_id)
	var patrol: NpcTask = _task(sim, guard_id)
	var victim: BaseNpc = free[0]
	victim.global_position = guard.global_position + Vector2(24.0, 0.0)
	var player: BasePlayer = _place_player_near(sim, victim)
	await sim.advance(0.1)
	victim.take_damage(1, player.hit_box)
	victim.take_damage(1, player.hit_box)
	var intervened: bool = false
	for frame: int in 60:
		await sim.advance(1.0 / 60.0)
		if patrol.phase in [NpcGuardTask.PHASE_INTERVENE, NpcGuardTask.PHASE_PURSUE]:
			intervened = true
			break
	_check(intervened, "(h) The guard did not intervene (phase %s)" % patrol.phase)
	player.surrender()
	var health: int = player.health
	var phases: Array[String] = []
	for second: int in 16:
		await sim.advance(0.5)
		if not patrol.phase in phases:
			phases.append(patrol.phase)
		if second > 0 and patrol.phase == NpcGuardTask.PHASE_PATROL:
			break
	_check(NpcGuardTask.PHASE_SURRENDERED in phases, "(h) The guard never stood down: %s" % [phases])
	_check(player.health == health, "(h) The guard attacked after the surrender")
	player.world_space = &"isolated"
	player.global_position = Vector2(4000.0, 4000.0)
	await sim.advance_minutes(NpcGuardTask.STAND_DOWN_MINUTES + 1.0)
	_check(_task(sim, guard_id) == patrol and patrol.phase == NpcGuardTask.PHASE_PATROL
		and patrol.status == NpcTask.Status.RUNNING,
		"(h) The patrol was not restored: %s" % [_task(sim, guard_id).checkpoint() if _task(sim, guard_id) != null else {}])
	_check(not guard.has_enemy_target(), "(h) The guard kept its enemy target")

## (i) Two witnesses find a body; one reports it to one guard while a second guard knows of it.
## The witness only searches places its own knowledge holds. A reload mid-carry still ends in
## exactly one burial, one grave and no remains.
func _recovery_with_reload(sim: Simulation) -> bool:
	var guards: Array[String] = _guard_ids(sim)
	var free: Array[BaseNpc] = _free_residents(sim, 8)
	_check(free.size() >= 3, "(i) Fewer than three free residents are outdoors")
	if free.size() < 3:
		return false
	# The victim farthest from every guard, so a resident (not a guard) finds the body.
	free.sort_custom(func(a: BaseNpc, b: BaseNpc) -> bool:
		return _guard_distance(sim, a) > _guard_distance(sim, b))
	var victim: BaseNpc = free[0]
	var body: String = _resident_id(victim)
	var point: Vector2 = victim.global_position
	var witnesses: Array[String] = []
	for index: int in 2:
		var witness: BaseNpc = free[index + 1]
		witness.global_position = point + Vector2(-14.0 + 28.0 * index, 12.0)
		var id: String = _resident_id(witness)
		witnesses.append(id)
		# Forget every sighting: the witness knows no guard's location, only public help places.
		_knowledge_of(sim, id).from_data(NpcKnowledge.new().to_data())
		sim.life._bootstrap_knowledge([id] as Array[String])
		for guard_id: String in guards:
			_check(_knowledge_of(sim, id).known_locations(guard_id).is_empty(), "(i) %s still knows where %s is" % [id, guard_id])
	victim.take_damage(999, null)
	var stages: Array[String] = []
	var reporters: Array[String] = []
	var carriers: Array[String] = []
	var checked_stops: Dictionary = {}
	var reloaded: bool = false
	var second_guard_placed: bool = false
	var end: float = sim.save_game().life.minute + 240.0
	while sim.save_game().life.minute < end:
		await sim.advance(0.25)
		var entry: Dictionary = sim.save_game().deaths.snapshot(body)
		if entry.is_empty():
			continue
		if stages.is_empty() or stages.back() != entry.stage:
			stages.append(entry.stage)
		if not entry.reporter.is_empty() and not entry.reporter in reporters:
			reporters.append(entry.reporter)
		if entry.stage in ["recovering", "carried"] and not entry.guard in carriers:
			carriers.append(entry.guard)
		_check_one_recovery(sim, body, "(i)")
		_check_witness_search(sim, body, checked_stops)
		_check(_remains_of(sim, body).size() <= 1, "(i) %s has more than one body" % body)
		if entry.stage == "reported" and not second_guard_placed:
			# A second guard learns of the reported body; the first guard keeps the only recovery job.
			second_guard_placed = true
			for guard_id: String in guards:
				var other: BaseNpc = sim.resident(guard_id)
				if guard_id != entry.guard and other != null and String(entry.space) == "outdoors" \
						and other.world_space == &"outdoors":
					other.global_position = Vector2(entry.position[0], entry.position[1]) + Vector2(0.0, 36.0)
		if entry.stage == "carried" and not reloaded:
			reloaded = true
			await sim.advance(1.0)
			await sim.reload_world()
			_check(sim.problems.is_empty(), "(i) Reload problems: %s" % [sim.problems])
			_check(sim.save_game().deaths.snapshot(body).stage == "carried", "(i) The reload lost the carry")
		if entry.stage == "buried":
			break
	var entry: Dictionary = sim.save_game().deaths.snapshot(body)
	_check(reloaded, "(i) The body was never carried: %s" % [stages])
	_check(entry.stage == "buried", "(i) The body was never buried: %s %s" % [stages, entry])
	_check(stages == ["fallen", "discovered", "reported", "recovering", "carried", "buried"]
		or stages == ["discovered", "reported", "recovering", "carried", "buried"],
		"(i) Unexpected recovery stages: %s" % [stages])
	_check(reporters.size() == 1 and reporters[0] in witnesses, "(i) Reporters: %s (witnesses %s)" % [reporters, witnesses])
	_check(carriers.size() == 1 and carriers[0] in guards, "(i) Carriers: %s" % [carriers])
	_check(not checked_stops.is_empty() or "reported" in stages, "(i) The witness never searched")
	await sim.advance_minutes(3.0)
	var effects: Dictionary = sim.effects()
	_check(effects.graves == 1 and sim.life.funerals.cemetery.graves().keys() == [body],
		"(i) Graves after burial: %s" % [sim.life.funerals.cemetery.graves()])
	_check(_remains_of(sim, body).is_empty(), "(i) Remains stayed after burial")
	_check(_recovery_holders(sim, body).is_empty(), "(i) A recovery task outlived the burial: %s" % [_recovery_holders(sim, body)])
	_check(sim.save_game().deaths.snapshot(body).stage == "buried", "(i) The burial changed after completion")
	return entry.stage == "buried"

## (j) A carrier killed mid-carry leaves exactly one body where it fell; another guard who finds it
## recovers it.
func _carrier_killed(sim: Simulation) -> bool:
	var carrier_id: String = ""
	for id: String in _guard_ids(sim):
		var npc: BaseNpc = sim.resident(id)
		if npc != null and npc.world_space == &"outdoors" and not npc.is_sleeping() \
				and not sim.life.funerals.is_assigned(id):
			carrier_id = id
			break
	var free: Array[BaseNpc] = _free_residents(sim, 1)
	_check(not carrier_id.is_empty() and free.size() == 1, "(j) No free guard and resident outdoors")
	if carrier_id.is_empty() or free.is_empty():
		return false
	var victim: BaseNpc = free[0]
	var body: String = _resident_id(victim)
	victim.global_position = sim.resident(carrier_id).global_position + Vector2(20.0, 0.0)
	victim.take_damage(999, null)
	var pickup: Vector2 = Vector2.INF
	var carrier: BaseNpc = null
	var end: float = sim.save_game().life.minute + 120.0
	while sim.save_game().life.minute < end:
		await sim.advance(0.25)
		_check_one_recovery(sim, body, "(j)")
		var entry: Dictionary = sim.save_game().deaths.snapshot(body)
		if entry.stage != "carried":
			continue
		carrier = sim.resident(entry.guard)
		if carrier == null:
			break
		if pickup == Vector2.INF:
			pickup = carrier.global_position
		elif carrier.global_position.distance_to(pickup) > 48.0:
			break
	var entry: Dictionary = sim.save_game().deaths.snapshot(body)
	_check(entry.stage == "carried" and carrier != null, "(j) The body was never carried: %s" % [entry])
	if carrier == null:
		return false
	carrier_id = _resident_id(carrier)
	var fell_at: Vector2 = carrier.global_position
	var space: String = String(carrier.world_space)
	carrier.take_damage(999, null)
	await sim.advance(0.5)
	entry = sim.save_game().deaths.snapshot(body)
	var drop := Vector2(entry.position[0], entry.position[1])
	_check(entry.stage == "reported" and entry.guard.is_empty(), "(j) The dead carrier still holds the body: %s" % [entry])
	_check(entry.space == space and drop.distance_to(fell_at) <= 24.0,
		"(j) The body is at %s %s, the carrier fell at %s %s" % [entry.space, drop, space, fell_at])
	var remains: Array[NpcRemains] = _remains_of(sim, body)
	_check(remains.size() == 1 and remains[0].global_position.distance_to(drop) <= 24.0,
		"(j) Remains after the carrier died: %s" % [remains.map(func(node: NpcRemains) -> Vector2: return node.global_position)])
	await sim.advance(2.0)
	entry = sim.save_game().deaths.snapshot(body)
	_check(entry.stage == "reported" and Vector2(entry.position[0], entry.position[1]) == drop,
		"(j) The dropped body moved without a carrier: %s" % [entry])
	# Another guard comes upon the body and takes the recovery up.
	var finder_id: String = ""
	for id: String in _guard_ids(sim):
		var npc: BaseNpc = sim.resident(id)
		if npc != null and npc.world_space == StringName(space) and not npc.is_sleeping():
			finder_id = id
			npc.global_position = drop + Vector2(0.0, 30.0)
			break
	_check(not finder_id.is_empty(), "(j) No guard is left to find the dropped body")
	if finder_id.is_empty():
		return false
	var recovered: bool = false
	end = sim.save_game().life.minute + 150.0
	while sim.save_game().life.minute < end:
		await sim.advance(0.25)
		_check_one_recovery(sim, body, "(j)")
		entry = sim.save_game().deaths.snapshot(body)
		if entry.stage in ["carried", "buried"] and entry.guard in [finder_id, ""]:
			recovered = true
			break
	_check(recovered, "(j) The dropped body was never recovered: %s" % [entry])
	return recovered

## (k) With no guard alive a witness searches every place it knows, defers the report and goes back
## to ordinary life; the body stays where it is and a knower takes the report up again later.
func _no_guard_left(sim: Simulation) -> void:
	for id: String in _guard_ids(sim):
		var guard: BaseNpc = sim.resident(id)
		if guard != null:
			guard.take_damage(999, null)
	await sim.advance(2.0)
	var free: Array[BaseNpc] = _free_residents(sim, 3)
	_check(free.size() == 3, "(k) Fewer than three free residents are outdoors")
	if free.size() < 3:
		return
	var victim: BaseNpc = free[0]
	var body: String = _resident_id(victim)
	free[1].global_position = victim.global_position + Vector2(14.0, 10.0)
	var witness: String = ""
	victim.take_damage(999, null)
	var deferred_at: float = -1.0
	var end: float = sim.save_game().life.minute + 360.0
	while sim.save_game().life.minute < end:
		await sim.advance(0.5)
		var entry: Dictionary = sim.save_game().deaths.snapshot(body)
		if not entry.reporter.is_empty():
			witness = entry.reporter
		elif entry.stage == "discovered" and sim.life.funerals._retry_at.has(witness):
			deferred_at = sim.save_game().life.minute
			break
	var entry: Dictionary = sim.save_game().deaths.snapshot(body)
	_check(deferred_at >= 0.0, "(k) The witness never deferred: %s, reporter task %s" % [entry,
		_task(sim, witness).checkpoint() if _task(sim, witness) != null else {}])
	if deferred_at < 0.0:
		return
	await sim.advance_minutes(3.0)
	var task: NpcTask = _task(sim, witness)
	_check(task != null and task.kind != &"recovery" and task.status == NpcTask.Status.RUNNING,
		"(k) Ordinary life did not resume: %s" % [task.checkpoint() if task != null else {}])
	entry = sim.save_game().deaths.snapshot(body)
	_check(entry.stage == "discovered" and _remains_of(sim, body).size() == 1, "(k) The deferred body changed: %s" % [entry])
	_check(String(entry.space) == "outdoors", "(k) The body is no longer outdoors: %s" % [entry])
	var reclaimed: bool = false
	var retry_end: float = deferred_at + TownFunerals.RETRY_MINUTES + 60.0
	while not reclaimed and sim.save_game().life.minute < retry_end:
		await sim.advance_minutes(5.0)
		entry = sim.save_game().deaths.snapshot(body)
		reclaimed = entry.stage == "discovered" and not entry.reporter.is_empty()
	_check(reclaimed and _remains_of(sim, body).size() == 1,
		"(k) Nobody took the deferred report up again: %s" % [entry])

func _guard_distance(sim: Simulation, npc: BaseNpc) -> float:
	var nearest: float = INF
	for id: String in _guard_ids(sim):
		var guard: BaseNpc = sim.resident(id)
		if guard != null:
			nearest = minf(nearest, guard.global_position.distance_to(npc.global_position))
	return nearest

## Resident id -> live recovery task (running or suspended) for `body`.
func _recovery_holders(sim: Simulation, body: String) -> Dictionary:
	var holders: Dictionary = {}
	for id: String in sim.resident_ids():
		var brain: NpcBrain = sim.life.brain_for(id)
		var task: NpcRecoveryTask = TownFunerals._recovery_task(brain) if brain != null else null
		if task != null and task.body_id() == body:
			holders[id] = task
	return holders

## At most one witness and one guard hold a recovery task for `body` at any time.
func _check_one_recovery(sim: Simulation, body: String, label: String) -> void:
	var witnesses: int = 0
	var guards: int = 0
	var holders: Dictionary = _recovery_holders(sim, body)
	for id: String in holders:
		if (holders[id] as NpcRecoveryTask).is_witness():
			witnesses += 1
		else:
			guards += 1
	_check(witnesses <= 1 and guards <= 1, "%s Several recovery jobs for %s: %s" % [label, body, holders.keys()])

## A searching witness only walks to stops taken from its own knowledge, never to a live position.
func _check_witness_search(sim: Simulation, body: String, checked: Dictionary) -> void:
	var holders: Dictionary = _recovery_holders(sim, body)
	for id: String in holders:
		var task: NpcRecoveryTask = holders[id]
		if not task.is_witness() or task.phase != NpcRecoveryTask.PHASE_SEEK_HELP or not task.progress.has("stops"):
			continue
		var stops: Array = task.progress["stops"]
		if not checked.has(task.task_id):
			checked[task.task_id] = true
			var known: Array = []
			var knowledge: NpcKnowledge = _knowledge_of(sim, id)
			for fact: Dictionary in knowledge.known_help_places():
				known.append(fact.value)
			for guard_id: String in _guard_ids(sim):
				for fact: Dictionary in knowledge.current(guard_id, "location"):
					known.append(fact.value)
			for stop: Array in stops:
				_check(known.any(func(value: Dictionary) -> bool:
					return String(value.get("space", "")) == String(stop[0]) \
						and Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0))).distance_to(
							Vector2(float(stop[1]), float(stop[2]))) < NpcRecoveryTask.SAME_STOP_DISTANCE),
					"(i) %s searches %s, which its knowledge does not hold" % [id, stop])
		var journey: Dictionary = sim.life.buildings._journeys.get(id, {})
		if journey.get("state") != &"traveling" or journey.get("owner") != task.task_id:
			continue
		var target: Vector2 = journey.point
		_check(stops.any(func(stop: Array) -> bool:
			return String(stop[0]) == String(journey.space) \
				and Vector2(float(stop[1]), float(stop[2])).distance_to(target) < NpcRecoveryTask.SAME_STOP_DISTANCE),
			"(i) %s walks to %s %s, which is not a known stop" % [id, journey.space, target])

## Physical remains of `id` in the world.
func _remains_of(sim: Simulation, id: String) -> Array[NpcRemains]:
	var result: Array[NpcRemains] = []
	var prefix: String = id.to_pascal_case() + "Remains"
	for node: Node in sim.life.get_parent().get_children():
		if node is NpcRemains and not node.is_queued_for_deletion() and String(node.name).begins_with(prefix):
			result.append(node)
	return result
