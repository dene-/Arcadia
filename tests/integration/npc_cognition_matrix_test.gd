extends SceneTree

## Acceptance-matrix rows of docs/plans/2026-09-21-npc-cognition-architecture.md section 8 that no
## other suite covers end to end: 7 (guard location unknown), 13 (promise plus farewell), 14 (family
## news unrelated to the player), 15 (same rumor circulates repeatedly), 19 (save at every task
## phase) and 20 (same seed and recorded judgments).

const Simulation = preload("res://tests/fixtures/npc_simulation_fixture.gd")
const RUMOR_ORIGIN: String = "test:m10rumor"
const RUMOR_TEXT: String = "I saw a stranger ring a copper bell at the old well."
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	await _row_7_guard_location_unknown()
	await _row_13_promise_and_farewell()
	await _row_14_family_news()
	await _row_15_same_rumor()
	await _row_19_save_at_every_phase()
	await _row_20_same_seed()
	for failure: String in failures:
		push_error(failure)
	print("NPC cognition matrix: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _start(minute: float = -1.0) -> Simulation:
	var sim := Simulation.new()
	sim.setup(self)
	if minute >= 0.0:
		sim.save_game().life.minute = minute
	await sim.load_world()
	_check(sim.problems.is_empty(), "Fixture problems: %s" % [sim.problems])
	return sim

# ---------------------------------------------------------------------------------------------
# Row 7: a witness that knows no guard's location visits only places its own knowledge holds.
# ---------------------------------------------------------------------------------------------
func _row_7_guard_location_unknown() -> void:
	var sim: Simulation = await _start(960.0)
	await sim.advance(2.0)
	var result: Dictionary = await _recovery_chain(sim, "(row 7)", false)
	if not result.is_empty():
		_check(result.trips > 0 or result.searched,
			"(row 7) The witness never searched: %s" % [result])
		_check(result.search_before_report,
			"(row 7) The report was made without a search phase: %s" % [result.phases])
		_check("seek_help" in result.phases and "report" in result.phases,
			"(row 7) Missing report phases: %s" % [result.phases])
	await sim.teardown()

# ---------------------------------------------------------------------------------------------
# Row 19: the body recovery survives a save and reload at every task phase.
# ---------------------------------------------------------------------------------------------
func _row_19_save_at_every_phase() -> void:
	var sim: Simulation = await _start(960.0)
	await sim.advance(2.0)
	var result: Dictionary = await _recovery_chain(sim, "(row 19)", true)
	if not result.is_empty():
		_check(result.reloads >= 3, "(row 19) Too few phases were reloaded: %s" % [result.reloaded_phases])
		print("Matrix row 19: reloaded at phases %s" % [result.reloaded_phases])
	await sim.teardown()

## One death with two witnesses who know no guard's location. Returns {} when the town offered no
## setup. `reload_phases` reloads the world the first time each recovery phase is seen.
func _recovery_chain(sim: Simulation, label: String, reload_phases: bool) -> Dictionary:
	var guards: Array[String] = _guard_ids(sim)
	var free: Array[BaseNpc] = _free_residents(sim, 8)
	_check(free.size() >= 3, "%s Fewer than three free residents are outdoors" % label)
	if free.size() < 3:
		return {}
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
		_knowledge_of(sim, id).from_data(NpcKnowledge.new().to_data())
		sim.life._bootstrap_knowledge([id] as Array[String])
		for guard_id: String in guards:
			_check(_knowledge_of(sim, id).known_locations(guard_id).is_empty(),
				"%s %s still knows where %s is" % [label, id, guard_id])
	# Whoever finds the body must also know no guard's location, not just the two placed witnesses.
	for id: String in sim.resident_ids():
		if id in guards or id == body or id in witnesses:
			continue
		_knowledge_of(sim, id).from_data(NpcKnowledge.new().to_data())
		sim.life._bootstrap_knowledge([id] as Array[String])
	victim.take_damage(999, null)
	var stages: Array[String] = []
	var phases: Array[String] = []
	var reloaded_phases: Array[String] = []
	var reporters: Array[String] = []
	var carriers: Array[String] = []
	var checked_stops: Dictionary = {}
	var trips: int = 0
	var searched: bool = false
	var search_before_report: bool = false
	var reported_seen: bool = false
	var second_guard_placed: bool = false
	var end: float = sim.save_game().life.minute + 300.0
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
		_check_one_recovery(sim, body, label)
		_check_witness_search(sim, body, checked_stops)
		_check(_remains_of(sim, body).size() <= 1, "%s %s has more than one body" % [label, body])
		var holders: Dictionary = _recovery_holders(sim, body)
		var new_phase: String = ""
		for id: String in holders:
			var task: NpcRecoveryTask = holders[id]
			if not task.phase in phases:
				phases.append(task.phase)
				if not task.phase in reloaded_phases:
					new_phase = task.phase
			if task.is_witness() and task.phase == NpcRecoveryTask.PHASE_SEEK_HELP:
				searched = searched or task.progress.has("stops")
				search_before_report = search_before_report or not reported_seen
				var journey: Dictionary = sim.life.buildings._journeys.get(id, {})
				if journey.get("state") == &"traveling" and journey.get("owner") == task.task_id:
					trips += 1
		if entry.stage == "reported":
			reported_seen = true
		if entry.stage == "reported" and not second_guard_placed:
			second_guard_placed = true
			for guard_id: String in guards:
				var other: BaseNpc = sim.resident(guard_id)
				if guard_id != entry.guard and other != null and String(entry.space) == "outdoors" \
						and other.world_space == &"outdoors":
					other.global_position = Vector2(entry.position[0], entry.position[1]) + Vector2(0.0, 36.0)
		if reload_phases and not new_phase.is_empty() and entry.stage != "buried":
			reloaded_phases.append(new_phase)
			await _reload_and_check(sim, body, holders.keys(), entry.stage, label + " [" + new_phase + "]")
		if entry.stage == "buried":
			break
	var entry: Dictionary = sim.save_game().deaths.snapshot(body)
	_check(entry.stage == "buried", "%s The body was never buried: %s %s" % [label, stages, entry])
	_check(stages == ["fallen", "discovered", "reported", "recovering", "carried", "buried"]
		or stages == ["discovered", "reported", "recovering", "carried", "buried"],
		"%s Unexpected recovery stages: %s" % [label, stages])
	_check(reporters.size() == 1 and not reporters[0] in guards and reporters[0] != body,
		"%s Reporters: %s" % [label, reporters])
	_check(carriers.size() == 1 and carriers[0] in guards, "%s Carriers: %s" % [label, carriers])
	await sim.advance_minutes(3.0)
	var effects: Dictionary = sim.effects()
	_check(effects.graves == 1 and sim.life.funerals.cemetery.graves().keys() == [body],
		"%s Graves after burial: %s" % [label, sim.life.funerals.cemetery.graves()])
	_check(_remains_of(sim, body).is_empty(), "%s Remains stayed after burial" % label)
	_check(_recovery_holders(sim, body).is_empty(), "%s A recovery task outlived the burial" % label)
	_check(sim.save_game().deaths.snapshot(body).stage == "buried", "%s The burial changed after completion" % label)
	_check_owned_states(sim, label)
	return {"phases": phases, "stages": stages, "trips": trips, "searched": searched,
		"search_before_report": search_before_report, "reloads": reloaded_phases.size(),
		"reloaded_phases": reloaded_phases}

## Reloads the world mid-phase: the body, its stage and its recovery job must survive unduplicated.
func _reload_and_check(sim: Simulation, body: String, holder_ids: Array, stage: String, label: String) -> void:
	await sim.reload_world()
	_check(sim.problems.is_empty(), "%s Reload problems: %s" % [label, sim.problems])
	_check(sim.save_game().deaths.snapshot(body).stage == stage, "%s The reload changed the stage" % label)
	_check(_remains_of(sim, body).size() <= 1, "%s Reload duplicated the body" % label)
	await sim.advance(1.0)
	var after: Dictionary = sim.save_game().deaths.snapshot(body)
	var holders: Dictionary = _recovery_holders(sim, body)
	if after.stage == stage:
		var kept: bool = false
		for id: String in holder_ids:
			kept = kept or holders.has(id)
		_check(kept or not holders.is_empty(),
			"%s No recovery task for %s after the reload (stage %s)" % [label, body, after.stage])
	_check_one_recovery(sim, body, label)
	_check_owned_states(sim, label)

# ---------------------------------------------------------------------------------------------
# Row 13: a promise is retained, the farewell closes after the reply is shown and only gameplay
# fulfillment completes it. No production code turns a spoken promise into a commitment, so the
# commitment is created by the fixture, as scenario (g) of npc_cognition_scenarios_test does.
# ---------------------------------------------------------------------------------------------
func _row_13_promise_and_farewell() -> void:
	var sim: Simulation = await _start(480.0)
	await sim.advance(2.0)
	var free: Array[BaseNpc] = _free_residents(sim, 1)
	_check(free.size() == 1, "(row 13) No free resident is outdoors")
	if free.is_empty():
		await sim.teardown()
		return
	var npc: BaseNpc = free[0]
	var id: String = _resident_id(npc)
	var dialog: Node = root.get_node("DialogManager")
	_check(dialog._bind_dialog_ui(), "(row 13) World dialogue UI could not be bound")
	dialog.request_npc_dialog(npc)
	for frame: int in 240:
		await sim.advance(1.0 / 60.0)
		if dialog.is_dialog_open() and not dialog._is_waiting_for_backend:
			break
	_check(dialog.is_dialog_open() and not dialog._is_waiting_for_backend, "(row 13) The greeting never arrived")
	# The player's session outlasts the approach timeout (one game minute) while the player reads.
	var opened: float = sim.save_game().life.minute
	for second: int in 3:
		await sim.advance(1.0)
	_check(sim.save_game().life.minute - opened > 2.0 and dialog.is_dialog_open() and not dialog._is_waiting_for_backend,
		"(row 13) The dialog did not survive %.1f game minutes of reading" % (sim.save_game().life.minute - opened))
	var gist: String = "Promised to report the copper bell."
	sim.backend.queue_response("dialogue/chat", {"should_remember": 1.0, "should_end_conversation": 1.0,
		"memory_importance": 3.0, "response": "I will tell the guard. Farewell.",
		"memory_writes": [{"type": "prospective", "gist": gist, "source": "player_claim",
			"topics": ["bell"], "people": ["player"], "completed": true}]})
	var chats: int = sim.backend.call_count("dialogue/chat")
	dialog._send_player_message("Please tell the guard about the bell.")
	for frame: int in 240:
		await sim.advance(1.0 / 60.0)
		if not dialog._is_waiting_for_backend:
			break
	_check(sim.backend.call_count("dialogue/chat") == chats + 1, "(row 13) The promise did not reach the backend once")
	_check(dialog._end_after_response and dialog.is_dialog_open(), "(row 13) The reply did not mark a farewell")
	# The reply is delivered in full before the farewell hold starts, and the hold keeps it visible.
	var revealed_frames: int = 0
	for frame: int in 600:
		await sim.advance(1.0 / 60.0)
		if dialog._farewell_remaining >= 0.0:
			break
	_check(dialog.is_dialog_open() and dialog._farewell_remaining >= 0.0 and not dialog._typewriter.is_revealing(),
		"(row 13) The farewell hold did not start after the reply was fully shown")
	chats = sim.backend.call_count("dialogue/chat")
	dialog._send_player_message("One more thing.")
	_check(sim.backend.call_count("dialogue/chat") == chats, "(row 13) A message after the farewell reached the backend")
	while dialog.is_dialog_open() and revealed_frames < 400:
		await sim.advance(1.0 / 60.0)
		revealed_frames += 1
	_check(not dialog.is_dialog_open(), "(row 13) The farewell never closed the dialog")
	_check(revealed_frames >= 60 and revealed_frames <= 180,
		"(row 13) The farewell closed after %d frames, not about %.1f s" % [revealed_frames, dialog.FAREWELL_HOLD_SECONDS])
	var memory_id: String = ""
	for record: Dictionary in sim.save_game().memory.snapshot(id).memories:
		if record.type == "prospective" and String(record.gist) == gist:
			memory_id = String(record.id)
			_check(record.get("completed") != true, "(row 13) The model's own 'completed' was accepted")
	_check(not memory_id.is_empty(), "(row 13) The valid promise was not retained")
	if memory_id.is_empty():
		await sim.teardown()
		return
	# The ended conversation invalidated the resident's routine; let it plan a new one before the errand.
	await sim.advance(2.0)
	var minute: float = sim.save_game().life.minute
	var commitments: NpcCommitments = sim.save_game().minds.get_mind(id).commitments
	var promise: String = commitments.create("report_discovery", [] as Array[String], ["memory:" + memory_id] as Array[String], minute)
	_check(not promise.is_empty(), "(row 13) The commitment was not created")
	var target: Vector2 = sim.life.navigation.nearest(npc.global_position + Vector2(220.0, 0.0))
	var errand := NpcRoutineTask.create({"activity": "report", "place": "outdoors", "label": "Reporting",
		"space": "outdoors", "point": [target.x, target.y], "until_minute": minute + 6.0}, sim.life.tuning)
	errand.commitment_ids = [promise] as Array[String]
	_check(sim.life.brain_for(id).request_task(errand), "(row 13) The errand was refused")
	await sim.advance(0.5)
	_check(not _completed(sim, id, memory_id), "(row 13) The promise completed before the errand did")
	for second: int in 90:
		await sim.advance(1.0)
		if commitments.get_commitment(promise).get("status") != "open":
			break
	_check(commitments.get_commitment(promise).get("status") == "completed",
		"(row 13) The errand ended as %s" % commitments.get_commitment(promise).get("status"))
	_check(_completed(sim, id, memory_id), "(row 13) Fulfilling the commitment did not complete the promise")
	await sim.teardown()

# ---------------------------------------------------------------------------------------------
# Row 14: news of a relative's death, unrelated to the player, becomes a concern that opens a check
# on another relative, steers the next goal and reaches the model's context.
# ---------------------------------------------------------------------------------------------
func _row_14_family_news() -> void:
	var sim: Simulation = await _start(1080.0)
	sim.backend.set_default("select_goal", {"suitability:CHECK_RELATIVE": 3.0, "suitability:PLAN": 0.0})
	await sim.advance(2.0)
	var free: Array[BaseNpc] = _free_residents(sim, 40)
	var mourner: BaseNpc = null
	var reporter: BaseNpc = null
	var kin: Array[String] = []
	for candidate: BaseNpc in free:
		var id: String = _resident_id(candidate)
		var mind: NpcMindState = sim.save_game().minds.get_mind(id)
		var found: Array[String] = []
		for subject: String in mind.relationships.subjects():
			if subject != id and _knowledge_of(sim, id).knows(subject, "family_role") and sim.resident(subject) != null:
				found.append(subject)
		found.sort()
		if found.size() >= 2:
			for other: BaseNpc in free:
				if other != candidate and not _resident_id(other) in found:
					reporter = other
					break
		if reporter != null:
			mourner = candidate
			kin = found
			break
	_check(mourner != null, "(row 14) No free resident has two known relatives and a reporter")
	if mourner == null:
		await sim.teardown()
		return
	var mourner_id: String = _resident_id(mourner)
	var deceased: String = kin[0]
	var relative: String = kin[1]
	var mind: NpcMindState = sim.save_game().minds.get_mind(mourner_id)
	var other: BaseNpc = sim.resident(relative)
	other.global_position = mourner.global_position + Vector2(mourner.npc_data.vision_radius * 4.0, 0.0)
	var chats: int = sim.backend.call_count("select_goal")
	sim.life.funerals._observe(mourner, deceased, "body_reported",
		"%s told me that %s was found dead." % [reporter.get_npc_profile().profile_name, deceased],
		"hearing", mourner.global_position, reporter)
	var commitment: Dictionary = {}
	for frame: int in 900:
		await sim.advance(1.0 / 60.0)
		commitment = mind.commitments.find("check_relative", relative)
		if not commitment.is_empty():
			break
	_check(not commitment.is_empty(), "(row 14) %s opened no check on %s after learning of %s's death" % [mourner_id, relative, deceased])
	if commitment.is_empty():
		await sim.teardown()
		return
	var grief: bool = false
	for concern: Variant in mind.condition.get("concerns", []):
		grief = grief or (concern is Dictionary and concern.get("kind") == "bereavement" and concern.get("subject") == deceased)
	_check(grief, "(row 14) The loss of %s left no bereavement concern" % deceased)
	_check(mind.commitments.get_commitment(commitment.id).get("status") == "open",
		"(row 14) The check ended without finding %s" % relative)
	await _m8_rechoose(sim, [mourner_id] as Array[String])
	_check(_latest_goal(sim, mourner_id).get("selected") == "CHECK_RELATIVE",
		"(row 14) %s did not go looking for %s: %s" % [mourner_id, relative, _latest_goal(sim, mourner_id)])
	sim.save_game().memory.ensure_npc(mourner.get_npc_profile())
	var context: Dictionary = NpcCognitiveContext.build(sim.save_game().memory.snapshot(mourner_id),
		mourner.get_cognitive_context())
	var kinds: Array[String] = []
	for concern: Dictionary in context.get("current_concerns", []):
		kinds.append(String(concern.get("kind", "")))
	_check("bereavement" in kinds and "commitment" in kinds,
		"(row 14) The concerns of %s do not carry the news: %s" % [mourner_id, kinds])
	var sent: bool = false
	for call: Dictionary in sim.backend.calls("select_goal").slice(chats):
		var text: String = JSON.stringify(call)
		sent = sent or (text.contains(mourner_id) and text.contains("bereavement"))
	_check(sent, "(row 14) No goal request to the model carried the bereavement")
	await sim.teardown()

# ---------------------------------------------------------------------------------------------
# Row 15: a rumor retold along O -> T -> L keeps its provenance; a repeated telling to L after its
# own account lapsed adds no memory, no corroboration and no second trust change.
# ---------------------------------------------------------------------------------------------
func _row_15_same_rumor() -> void:
	var sim: Simulation = await _start(600.0)
	await sim.advance(2.0)
	var trio: Array[BaseNpc] = _free_residents(sim, 3)
	_check(trio.size() == 3, "(row 15) Fewer than three free residents are outdoors")
	if trio.size() < 3:
		await sim.teardown()
		return
	var player: BasePlayer = sim.world.get_node("BasePlayer")
	player.set_physics_process(false)
	player.world_space = &"isolated"
	player.global_position = Vector2(4000.0, 4000.0)
	var life_state: TownLifeState = sim.save_game().life
	var o: BaseNpc = trio[0]
	var t: BaseNpc = trio[1]
	var l: BaseNpc = trio[2]
	var o_id: String = _resident_id(o)
	var t_id: String = _resident_id(t)
	var l_id: String = _resident_id(l)
	for npc: BaseNpc in trio:
		_eager_initiator(npc)
	life_state.rumors.observe(o_id, o.get_npc_profile().profile_name,
		{"origin_id": RUMOR_ORIGIN, "text": RUMOR_TEXT, "sense": "sight", "player_involved": false},
		{"remember": true, "importance": 1.0}, life_state.minute)
	# O -> T: believed and remembered.
	life_state.advance(120.0)
	sim.backend.set_default("listen", {"believe_account": 1.0, "remember": 1.0})
	_check(await _tell(sim, o, t), "(row 15) O did not tell T")
	var told: Array[Dictionary] = life_state.rumors.get_known(t_id, life_state.minute)
	_check(told.size() == 1 and told[0].chain == [o_id, t_id] and told[0].hops == 1 and told[0].originator == o_id,
		"(row 15) T's account lost its provenance: %s" % [told])
	# T -> L: believed, forgotten, and the messenger is distrusted once.
	life_state.advance(120.0)
	var l_mind: NpcMindState = sim.save_game().minds.get_mind(l_id)
	var trust_before: Dictionary = l_mind.relationships.to_data()
	sim.backend.set_default("listen", {"believe_account": 1.0, "remember": 0.0,
		"disposition:%s:trust:direction" % t_id: "NEGATIVE", "disposition:%s:trust:magnitude" % t_id: 3.0})
	_check(await _tell(sim, t, l), "(row 15) T did not tell L")
	var second: Array[Dictionary] = life_state.rumors.get_known(l_id, life_state.minute)
	_check(second.size() == 1 and second[0].chain == [o_id, t_id, l_id] and second[0].hops == 2
		and float(second[0].confidence) <= float(told[0].confidence),
		"(row 15) L's account lost provenance or gained certainty: %s" % [second])
	_check(life_state.rumors.candidates(o_id, l_id, life_state.minute).is_empty(),
		"(row 15) O may retell the rumor to someone who already knows it")
	_check(life_state.rumors.candidates(t_id, o_id, life_state.minute).is_empty(),
		"(row 15) The rumor may be told back to its originator")
	var penalized: Dictionary = l_mind.relationships.to_data()
	_check(penalized != trust_before, "(row 15) The first telling changed no relationship (trust penalty not applied)")
	var memories: int = sim.save_game().memory.snapshot(l_id).memories.size()
	# L's own account lapses; O's remains live, so the origin stays known to L's receipts.
	life_state.advance(181.0)
	_check(life_state.rumors.get_known(l_id, life_state.minute).is_empty(), "(row 15) L's forgotten account did not lapse")
	_check(not life_state.rumors.get_known(o_id, life_state.minute).is_empty(), "(row 15) O's account lapsed too early")
	sim.backend.set_default("listen", {"believe_account": 1.0, "remember": 1.0,
		"disposition:%s:trust:direction" % o_id: "NEGATIVE", "disposition:%s:trust:magnitude" % o_id: 3.0})
	_check(await _tell(sim, o, l), "(row 15) O's repeated telling to L was not heard")
	var third: Array[Dictionary] = life_state.rumors.get_known(l_id, life_state.minute)
	_check(third.size() == 1 and third[0].chain == [o_id, l_id] and float(third[0].confidence) <= float(told[0].confidence),
		"(row 15) The repeated account gained certainty or lost its source: %s" % [third])
	var trust_after: Dictionary = l_mind.relationships.to_data().subjects
	_check(trust_after[t_id].trust == penalized.subjects[t_id].trust and trust_after[o_id].trust == penalized.subjects[o_id].trust,
		"(row 15) The repeated telling changed L's trust again: %s %s" % [t_id, o_id])
	_check(sim.save_game().memory.snapshot(l_id).memories.size() == memories,
		"(row 15) The repeated telling created a second memory of the same origin")
	await sim.teardown()

## Starts conversations between `speaker` and `listener` (one attempt per game minute) until the
## listener knows the rumor; false when none transferred it.
func _tell(sim: Simulation, speaker: BaseNpc, listener: BaseNpc) -> bool:
	var life_state: TownLifeState = sim.save_game().life
	var speaker_id: String = _resident_id(speaker)
	var listener_id: String = _resident_id(listener)
	for attempt: int in 40:
		listener.global_position = speaker.global_position + Vector2(12.0, 0.0)
		sim.life.encounters.consider(speaker, listener)
		for frame: int in 20:
			await process_frame
			if not sim.life.encounters.is_busy(speaker_id) and not sim.life.encounters.is_busy(listener_id):
				break
		if life_state.rumors.knows(listener_id, RUMOR_ORIGIN, life_state.minute):
			return true
		life_state.advance(1.0)
	return false

# ---------------------------------------------------------------------------------------------
# Row 20: the same seed, start minute and recorded judgments reproduce every resident's goals, also
# when the provider's answers arrive late.
# ---------------------------------------------------------------------------------------------
func _row_20_same_seed() -> void:
	var first: Dictionary = await _goal_run(0.0)
	var again: Dictionary = await _goal_run(0.0)
	var late: Dictionary = await _goal_run(1.0)
	_check(first.size() > 0, "(row 20) No resident chose a goal")
	_check(first == again, "(row 20) A repeated run chose different goals: %s" % _first_difference(first, again))
	_check(_first_goals(first) == _first_goals(late),
		"(row 20) Late provider answers changed the first goals: %s" % _first_difference(_first_goals(first), _first_goals(late)))

## Resident id -> goals it selected during a 20 second run; the provider holds its answers for
## `hold_seconds` first.
func _goal_run(hold_seconds: float) -> Dictionary:
	var sim: Simulation = await _start(480.0)
	sim.backend.set_default("select_goal", {"suitability:PLAN": 3.0, "suitability:WORK": 3.0,
		"suitability:SOCIAL": 3.0, "suitability:REST": 1.0})
	if hold_seconds > 0.0:
		sim.backend.hold("select_goal")
		await sim.advance(hold_seconds)
		sim.backend.release("select_goal")
	await sim.advance(20.0 - hold_seconds)
	var goals: Dictionary = {}
	for id: String in sim.resident_ids():
		var chosen: Array[String] = []
		for entry: Dictionary in sim.life.brain_for(id).trace.entries():
			if entry.kind == NpcDecisionTrace.GOAL:
				chosen.append(String(entry.get("selected", "")))
		goals[id] = chosen
	await sim.teardown()
	return goals

static func _first_goals(goals: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id: String in goals:
		if not (goals[id] as Array).is_empty():
			result[id] = goals[id][0]
	return result

static func _first_difference(a: Dictionary, b: Dictionary) -> String:
	for id: String in a:
		if a[id] != b.get(id):
			return "%s: %s != %s" % [id, a[id], b.get(id)]
	for id: String in b:
		if not a.has(id):
			return "%s only in the second run" % id
	return ""

# ---------------------------------------------------------------------------------------------
# Helpers shared with npc_cognition_scenarios_test.gd.
# ---------------------------------------------------------------------------------------------
func _knowledge_of(sim: Simulation, id: String) -> NpcKnowledge:
	return sim.save_game().minds.get_mind(id).knowledge

func _guard_ids(sim: Simulation) -> Array[String]:
	var guards: Array[String] = []
	for id: String in sim.save_game().population.people:
		if sim.save_game().population.people[id].job == "guard":
			guards.append(id)
	guards.sort()
	return guards

func _task(sim: Simulation, id: String) -> NpcTask:
	var brain: NpcBrain = sim.life.brain_for(id)
	return brain.controller.current if brain != null else null

func _latest_goal(sim: Simulation, id: String) -> Dictionary:
	var brain: NpcBrain = sim.life.brain_for(id)
	return brain.trace.latest(NpcDecisionTrace.GOAL) if brain != null else {}

func _journey_owner(sim: Simulation, id: String) -> String:
	var journey: Dictionary = sim.life.buildings._journeys.get(id, {})
	return String(journey.owner) if journey.get("state") == &"traveling" else ""

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

func _eager_initiator(npc: BaseNpc) -> void:
	var traits: Dictionary = npc.get_npc_profile().social_traits.duplicate()
	traits.sociability = 1.0
	traits.curiosity = 1.0
	npc.get_npc_profile().social_traits = traits

func _resident_id(npc: BaseNpc) -> String:
	return String(npc.get_npc_profile().npc_id)

func _completed(sim: Simulation, id: String, memory_id: String) -> bool:
	for record: Dictionary in sim.save_game().memory.snapshot(id).memories:
		if record.id == memory_id:
			return record.get("completed") == true
	return false

## Interrupts `ids` and runs the simulation until each has chosen again (or 10 seconds pass).
func _m8_rechoose(sim: Simulation, ids: Array[String]) -> void:
	var life_state: TownLifeState = sim.save_game().life
	var from: float = life_state.minute
	for id: String in ids:
		life_state.interrupt(id)
	for _step: int in 20:
		await sim.advance(0.5)
		var pending: bool = false
		for id: String in ids:
			pending = pending or float(life_state.get_person(id).until) <= from
		if not pending:
			return

func _guard_distance(sim: Simulation, npc: BaseNpc) -> float:
	var nearest: float = INF
	for id: String in _guard_ids(sim):
		var guard: BaseNpc = sim.resident(id)
		if guard != null:
			nearest = minf(nearest, guard.global_position.distance_to(npc.global_position))
	return nearest

func _recovery_holders(sim: Simulation, body: String) -> Dictionary:
	var holders: Dictionary = {}
	for id: String in sim.resident_ids():
		var brain: NpcBrain = sim.life.brain_for(id)
		var task: NpcRecoveryTask = TownFunerals._recovery_task(brain) if brain != null else null
		if task != null and task.body_id() == body:
			holders[id] = task
	return holders

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
					"%s searches %s, which its knowledge does not hold" % [id, stop])
		var journey: Dictionary = sim.life.buildings._journeys.get(id, {})
		if journey.get("state") != &"traveling" or journey.get("owner") != task.task_id:
			continue
		var target: Vector2 = journey.point
		_check(stops.any(func(stop: Array) -> bool:
			return String(stop[0]) == String(journey.space) \
				and Vector2(float(stop[1]), float(stop[2])).distance_to(target) < NpcRecoveryTask.SAME_STOP_DISTANCE),
			"%s walks to %s %s, which is not a known stop" % [id, journey.space, target])

func _remains_of(sim: Simulation, id: String) -> Array[NpcRemains]:
	var result: Array[NpcRemains] = []
	var prefix: String = id.to_pascal_case() + "Remains"
	for node: Node in sim.life.get_parent().get_children():
		if node is NpcRemains and not node.is_queued_for_deletion() and String(node.name).begins_with(prefix):
			result.append(node)
	return result
