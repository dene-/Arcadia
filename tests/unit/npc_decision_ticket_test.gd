extends "res://tests/test_case.gd"

## A decision ticket names the task it serves and the versions of the state it read. A result is
## stale once that task no longer owns the resident or any read version moved; diagnostics and
## state the request did not read leave it current.

const Routine = preload("res://tests/unit/npc_routine_task_test.gd")
const START: float = 600.0

func test_diagnostics_and_in_band_ticks_do_not_stale_a_goal_ticket() -> void:
	var rig := _rig()
	var ticket: NpcDecisionTicket = _goal_ticket(rig, START)
	var diagnostics: int = rig.brain.trace.version
	for index: int in 10:
		rig.brain.trace.record(START, NpcDecisionTrace.GOAL, {"goal": "REST", "index": index})
	rig.brain.debug_snapshot()
	assert_true(rig.brain.trace.version > diagnostics, "the diagnostics were recorded")
	rig.mind.advance_needs(1.0, false, 0.5, rig.tuning)
	assert_false(_stale(ticket, rig, START + 1.0), "trace entries and a need tick inside its band")
	rig.dispose()

func test_an_unrelated_relationship_does_not_stale_a_goal_ticket() -> void:
	var rig := _rig()
	var ticket: NpcDecisionTicket = _goal_ticket(rig, START)
	assert_true(rig.mind.relationships.apply_delta("oren", {"trust": 0.2}, "receipt:oren:1"))
	assert_false(_stale(ticket, rig, START))
	rig.dispose()

func test_a_newly_perceived_attacker_stales_it() -> void:
	var rig := _rig()
	var ticket: NpcDecisionTicket = _goal_ticket(rig, START)
	assert_true(rig.mind.feel("fear", 0.9, "stranger", "obs:attack:1", "incident:1", START))
	assert_true(_stale(ticket, rig, START))
	rig.dispose()

## The belief changes the appraisal's read set; the resulting grief concern changes the goal's.
func test_miras_reported_death_stales_it() -> void:
	var rig := _rig()
	var ticket: NpcDecisionTicket = _goal_ticket(rig, START)
	var appraisal: Dictionary = _appraisal_reads(rig.mind, START)
	assert_true(rig.mind.knowledge.record_report("mira", "status", "dead", "oren", "origin:mira",
		"obs:report:1", START, 0.8))
	assert_ne(_appraisal_reads(rig.mind, START), appraisal, "the report is a new belief")
	assert_true(rig.mind.add_bereavement("mira", "obs:report:1", START))
	assert_true(_stale(ticket, rig, START))
	rig.dispose()

## Needs grow every minute; only the minute a band boundary is crossed stales the ticket.
func test_only_a_band_boundary_stales_it() -> void:
	var rig := _rig()
	var ticket: NpcDecisionTicket = _goal_ticket(rig, START)
	var bands: Dictionary = _need_bands(rig.mind, START)
	var crossed: bool = false
	var minute: float = START
	while not crossed and minute < START + 600.0:
		minute += 1.0
		rig.mind.advance_needs(1.0, false, 0.5, rig.tuning)
		crossed = _need_bands(rig.mind, minute) != bands
		assert_eq(_stale(ticket, rig, minute), crossed, "minute %s" % minute)
	assert_true(crossed, "a need reached its next band within ten hours")
	rig.dispose()

func test_replacing_its_task_stales_it() -> void:
	var rig := _rig()
	var ticket: NpcDecisionTicket = _goal_ticket(rig, START)
	var replacement: NpcRoutineTask = NpcRoutineTask.create(
		Routine.routine_params("rest", "home", START + 120.0), rig.tuning)
	replacement.priority = rig.tuning.routine_priority + 0.01
	assert_true(rig.brain.request_task(replacement))
	assert_true(_stale(ticket, rig, START), "another task owns the resident")
	rig.dispose()

func test_a_saved_task_checkpoint_stales_it() -> void:
	var rig := _rig()
	var ticket: NpcDecisionTicket = _goal_ticket(rig, START)
	assert_true(rig.brain.save_checkpoint())
	assert_true(_stale(ticket, rig, START), "the task state it read was replaced")
	rig.dispose()

func test_an_ended_session_stales_its_ticket_and_releases_the_claim() -> void:
	var rig := _rig()
	var session: String = "player:1"
	assert_true(rig.brain.request_conversation(session))
	assert_true(rig.brain.request_task(NpcSocialTask.create(session, "player", "partner", rig.tuning)))
	var ticket: NpcDecisionTicket = _goal_ticket(rig, START)
	assert_eq(ticket.task_id, NpcSocialTask.owner_for(session))
	rig.brain.trace.record(START, NpcDecisionTrace.EFFECT, {"reason": "line_spoken"})
	assert_false(_stale(ticket, rig, START), "a diagnostic during the session")
	assert_true(rig.brain.end_task(NpcSocialTask.owner_for(session), &"session_ended"))
	rig.brain.finish_conversation(session)
	assert_true(_stale(ticket, rig, START))
	assert_eq(rig.brain.controller.claim_owner(NpcBrain.CONVERSATION_CLAIM), "")
	rig.dispose()

func _rig() -> Routine.Rig:
	var rig := Routine.Rig.new()
	assert_true(rig.start(NpcRoutineTask.create(
		Routine.routine_params("work", "bakery", START + 240.0), rig.tuning), START))
	return rig

## A goal ticket as TownLife builds it: the running task plus task, condition and commitment
## versions, and the knowledge it decides from.
func _goal_ticket(rig: Routine.Rig, minute: float) -> NpcDecisionTicket:
	var ticket := NpcDecisionTicket.create(rig.mind.npc_id, NpcDecisionTicket.SELECT_GOAL)
	var task: NpcTask = rig.brain.controller.current
	ticket.task_id = task.task_id
	ticket.task_generation = task.generation
	ticket.created_minute = int(minute)
	ticket.read_versions = _goal_reads(rig.mind, minute)
	return ticket

func _goal_reads(mind: NpcMindState, minute: float) -> Dictionary:
	return {"task": int(mind.versions().task), "knowledge": mind.knowledge.version,
		"condition": mind.condition_version(minute), "commitments": mind.commitments.version}

## The read set of an appraisal (NpcEventProcessor).
func _appraisal_reads(mind: NpcMindState, minute: float) -> Dictionary:
	return {"knowledge": mind.knowledge.version, "relationships": mind.relationships.version,
		"condition": mind.condition_version(minute)}

func _need_bands(mind: NpcMindState, minute: float) -> Dictionary:
	var band: Dictionary = mind.condition_band(minute)
	return {"hunger": band["hunger"], "fatigue": band["fatigue"], "social": band["social"]}

func _stale(ticket: NpcDecisionTicket, rig: Routine.Rig, minute: float) -> bool:
	var task: NpcTask = rig.brain.controller.current
	return task == null or task.task_id != ticket.task_id or task.generation != ticket.task_generation \
		or _goal_reads(rig.mind, minute) != ticket.read_versions
