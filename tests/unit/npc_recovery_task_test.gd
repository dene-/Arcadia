extends "res://tests/test_case.gd"

const Routine = preload("res://tests/unit/npc_routine_task_test.gd")

const BODY: String = "mira"
const SELF: String = "holt_partner"
const BODY_POINT := Vector2(100.0, 0.0)
const PLOT := Vector2(-280.0, 248.0)

# The town services TownFunerals hands to a participant's brain.
class Town extends RefCounted:
	var deaths := TownDeaths.new()
	var roster: Array[String] = []
	var visible: Array[Dictionary] = []
	var scene: StringName = &"clear"
	var events: Array[String] = []

	func provide(brain: NpcBrain) -> void:
		brain.provide_service(&"deaths", func() -> TownDeaths: return deaths)
		brain.provide_service(&"guard_roster", func() -> Array[String]: return roster)
		brain.provide_service(&"visible_guards", func() -> Array[Dictionary]: return visible)
		brain.provide_service(&"assess_scene",
			func(_space: StringName, _point: Vector2) -> StringName: return scene)
		brain.provide_service(&"cemetery_plot", func(_body: String) -> Vector2: return PLOT)
		brain.provide_service(&"recovery_event", func(event: StringName, _body: String, other: String) -> void:
			events.append("%s:%s" % [event, other]))

func _rig(town: Town) -> Routine.Rig:
	var rig := Routine.Rig.new()
	town.provide(rig.brain)
	return rig

func _task(rig: Routine.Rig, role: String) -> NpcRecoveryTask:
	return NpcRecoveryTask.create({"role": role, "body": BODY, "activity": "recover_body",
		"label": "a reported death"}, rig.tuning)

static func _fallen(town: Town) -> void:
	town.deaths.record(BODY, "town", BODY_POINT, 0.0)

# A body reported to SELF by another witness.
static func _reported_to_self(town: Town) -> void:
	_fallen(town)
	town.deaths.discover(BODY, "ana", 1.0)
	town.deaths.acknowledge_report(BODY, SELF, "ana", 2.0)

func _stage(town: Town) -> String:
	return town.deaths.snapshot(BODY)["stage"] as String

func _last_point(rig: Routine.Rig) -> Vector2:
	return rig.executor.begun[rig.executor.begun.size() - 1]["point"] as Vector2

func _arrive_at(rig: Routine.Rig, space: StringName, point: Vector2) -> void:
	rig.executor.arrive()
	rig.actor.world_space = space
	rig.actor.global_position = point

# --- Witness ---

func test_witness_searches_known_guard_locations_then_help_places_and_defers() -> void:
	var town := Town.new()
	_fallen(town)
	town.deaths.discover(BODY, SELF, 10.0)
	town.roster.assign(["vale_guard", "voss_guard", "dead_guard"])
	var rig := _rig(town)
	var knowledge: NpcKnowledge = rig.mind.knowledge
	knowledge.record_sighting("vale_guard", "outdoors", Vector2(10, 10), 5.0, "e1")
	knowledge.record_sighting("voss_guard", "barracks", Vector2(30, 30), 8.0, "e2")
	knowledge.record_sighting("dead_guard", "outdoors", Vector2(90, 90), 9.0, "e3")
	knowledge.record("dead_guard", "status", "dead", NpcKnowledge.Status.OBSERVED,
		NpcKnowledge.SELF_SOURCE, "e4", "death:dead_guard", 9.0, 1.0)
	knowledge.record("town", "help_place", {"place": "watch_post", "space": "outdoors",
		"x": 200.0, "y": 0.0, "kind": "guard_post"}, NpcKnowledge.Status.OBSERVED,
		NpcKnowledge.SELF_SOURCE, "e5", "place:watch_post", 1.0, 1.0)
	var task := _task(rig, NpcRecoveryTask.WITNESS)
	assert_true(rig.start(task, 10.0))
	assert_eq(rig.phase(), NpcRecoveryTask.PHASE_ABSORB)
	rig.tick(13.0)
	assert_eq(rig.phase(), NpcRecoveryTask.PHASE_ABSORB, "absorbing takes four minutes")
	rig.tick(14.0)
	assert_eq(rig.phase(), NpcRecoveryTask.PHASE_SEEK_HELP)
	var visited: Array[Vector2] = [_last_point(rig)]
	for minute: float in [15.0, 16.0, 17.0]:
		rig.executor.arrive()
		rig.tick(minute)
		if rig.executor.states.get(task.task_id) == &"traveling":
			visited.append(_last_point(rig))
	assert_eq(visited, [Vector2(30, 30), Vector2(10, 10), Vector2(200, 0)] as Array[Vector2],
		"most recent guard sighting first, never a guard known dead, then help places")
	assert_eq(rig.phase(), NpcRecoveryTask.PHASE_DEFERRED)
	assert_eq(rig.brain.task_state(task.task_id), "RUNNING")
	assert_eq(_stage(town), "discovered", "the body stays discovered for a later attempt")
	rig.dispose()

func test_witness_approaches_a_visible_guard_where_seen_and_reports() -> void:
	var town := Town.new()
	_fallen(town)
	town.deaths.discover(BODY, SELF, 10.0)
	var rig := _rig(town)
	var commitment: String = rig.mind.commitments.create("report_discovery", [BODY], ["obs:1"],
		10.0, -1.0, 0.6)
	var task := _task(rig, NpcRecoveryTask.WITNESS)
	task.commitment_ids.assign([commitment])
	assert_true(rig.start(task, 10.0))
	town.visible.assign([{"id": "vale_guard", "space": "town", "position": Vector2(60, 0)}])
	rig.tick(14.0)
	assert_eq(rig.phase(), NpcRecoveryTask.PHASE_REPORT)
	assert_eq(_last_point(rig), Vector2(60, 0) + NpcRecoveryTask.STAND_OFFSET)
	var issued: int = rig.executor.begun.size()
	town.visible[0]["position"] = Vector2(64, 0)
	rig.tick(15.0)
	assert_eq(rig.executor.begun.size(), issued, "small moves keep the journey")
	town.visible[0]["position"] = Vector2(120, 40)
	rig.tick(16.0)
	assert_eq(_last_point(rig), Vector2(120, 40) + NpcRecoveryTask.STAND_OFFSET,
		"re-acquires the guard where it is seen now")
	rig.actor.global_position = Vector2(120, 52)
	rig.tick(17.0)
	var entry: Dictionary = town.deaths.snapshot(BODY)
	assert_eq(entry["stage"], "reported")
	assert_eq(entry["guard"], "vale_guard")
	assert_eq(town.events, ["reported:vale_guard"] as Array[String])
	assert_eq(rig.last_finished()["status"], "COMPLETED")
	assert_eq(rig.mind.commitments.get_commitment(commitment)["status"], "completed")
	rig.dispose()

func test_losing_sight_of_the_guard_resumes_the_search() -> void:
	var town := Town.new()
	_fallen(town)
	town.deaths.discover(BODY, SELF, 10.0)
	var rig := _rig(town)
	assert_true(rig.start(_task(rig, NpcRecoveryTask.WITNESS), 10.0))
	town.visible.assign([{"id": "vale_guard", "space": "town", "position": Vector2(60, 0)}])
	rig.tick(14.0)
	town.visible.clear()
	rig.tick(15.0)
	assert_eq(rig.phase(), NpcRecoveryTask.PHASE_SEEK_HELP)
	rig.dispose()

func test_witness_stops_when_the_report_was_already_made() -> void:
	var town := Town.new()
	_fallen(town)
	town.deaths.discover(BODY, SELF, 10.0)
	var rig := _rig(town)
	assert_true(rig.start(_task(rig, NpcRecoveryTask.WITNESS), 10.0))
	town.deaths.acknowledge_report(BODY, "vale_guard", SELF, 11.0)
	rig.tick(12.0)
	assert_eq(rig.last_finished()["reason"], &"already_reported")
	rig.dispose()

# --- Guard ---

func test_guard_recovers_carries_and_buries_once() -> void:
	var town := Town.new()
	_reported_to_self(town)
	var rig := _rig(town)
	rig.actor.sleeping = true
	var task := _task(rig, NpcRecoveryTask.GUARD)
	assert_true(rig.start(task, 20.0))
	assert_false(rig.actor.sleeping, "a sleeping guard is roused")
	assert_eq(_stage(town), "recovering")
	assert_eq(rig.phase(), NpcRecoveryTask.PHASE_REACH_BODY)
	assert_eq(_last_point(rig), BODY_POINT + NpcRecoveryTask.STAND_OFFSET)
	_arrive_at(rig, &"town", BODY_POINT + NpcRecoveryTask.STAND_OFFSET)
	rig.tick(30.0)
	assert_eq(rig.phase(), NpcRecoveryTask.PHASE_PREPARE)
	rig.tick(35.0)
	assert_eq(_stage(town), "recovering", "preparation takes six minutes")
	rig.tick(36.0)
	assert_eq(_stage(town), "carried")
	rig.tick(37.0)
	assert_eq(rig.phase(), NpcRecoveryTask.PHASE_REACH_CEMETERY)
	rig.tick(38.0)
	assert_eq(_last_point(rig), PLOT + NpcRecoveryTask.STAND_OFFSET)
	rig.actor.world_space = &"outdoors"
	rig.actor.global_position = Vector2(0, 100)
	rig.tick(39.0)
	var carried: Dictionary = town.deaths.snapshot(BODY)
	assert_eq([carried["space"], carried["position"]], ["outdoors", [0.0, 100.0]],
		"the body moves with its carrier")
	_arrive_at(rig, &"outdoors", PLOT + NpcRecoveryTask.STAND_OFFSET)
	rig.tick(40.0)
	assert_eq(rig.phase(), NpcRecoveryTask.PHASE_BURY)
	rig.tick(51.0)
	assert_eq(_stage(town), "carried", "burial takes twelve minutes")
	rig.tick(52.0)
	assert_eq(_stage(town), "buried")
	assert_eq(rig.last_finished()["reason"], &"buried")
	assert_eq(town.events, ["recovering:%s" % SELF, "preparing:%s" % SELF, "picked_up:%s" % SELF,
		"buried:%s" % SELF] as Array[String])
	rig.dispose()

func test_danger_at_the_scene_releases_the_claim_until_it_is_clear() -> void:
	var town := Town.new()
	_reported_to_self(town)
	var rig := _rig(town)
	assert_true(rig.start(_task(rig, NpcRecoveryTask.GUARD), 20.0))
	_arrive_at(rig, &"town", BODY_POINT + NpcRecoveryTask.STAND_OFFSET)
	town.scene = &"danger"
	rig.tick(21.0)
	var entry: Dictionary = town.deaths.snapshot(BODY)
	assert_eq([entry["stage"], entry["guard"]], ["reported", ""])
	rig.tick(21.5)
	assert_eq(_stage(town), "reported", "no new claim while the danger lasts")
	town.scene = &"clear"
	rig.tick(22.0)
	assert_eq(_stage(town), "recovering")
	assert_eq(rig.phase(), NpcRecoveryTask.PHASE_PREPARE)
	rig.dispose()

func test_hurt_carrier_drops_the_body_where_it_stands_and_takes_it_up_again() -> void:
	var town := Town.new()
	_reported_to_self(town)
	var rig := _rig(town)
	var task := _task(rig, NpcRecoveryTask.GUARD)
	assert_true(rig.start(task, 20.0))
	_arrive_at(rig, &"town", BODY_POINT + NpcRecoveryTask.STAND_OFFSET)
	rig.tick(21.0)
	rig.tick(27.0)
	assert_eq(_stage(town), "carried")
	rig.actor.global_position = Vector2(150, 30)
	rig.tick(28.0)
	rig.brain.interrupt(NpcTask.Interrupt.HURT)
	var dropped: Dictionary = town.deaths.snapshot(BODY)
	assert_eq([dropped["stage"], dropped["guard"], dropped["position"]], ["reported", "", [150.0, 30.0]])
	assert_eq(rig.brain.task_state(task.task_id), "SUSPENDED")
	rig.tick(29.0)
	assert_eq(rig.brain.task_state(task.task_id), "RUNNING")
	assert_eq(_stage(town), "recovering", "the resumed guard claims the body again")
	assert_true(town.events.has("dropped:%s" % SELF))
	rig.dispose()

func test_dead_carrier_leaves_the_body_at_the_last_carried_position() -> void:
	var town := Town.new()
	_reported_to_self(town)
	var rig := _rig(town)
	assert_true(rig.start(_task(rig, NpcRecoveryTask.GUARD), 20.0))
	_arrive_at(rig, &"town", BODY_POINT + NpcRecoveryTask.STAND_OFFSET)
	rig.tick(21.0)
	rig.tick(27.0)
	rig.actor.global_position = Vector2(150, 30)
	rig.tick(28.0)
	rig.actor.global_position = Vector2(400, 400)
	rig.brain.interrupt(NpcTask.Interrupt.DEATH)
	var entry: Dictionary = town.deaths.snapshot(BODY)
	assert_eq([entry["stage"], entry["guard"], entry["position"]], ["reported", "", [150.0, 30.0]])
	rig.dispose()

func test_a_body_another_guard_holds_is_left_to_them() -> void:
	var town := Town.new()
	_fallen(town)
	town.deaths.discover(BODY, "ana", 1.0)
	town.deaths.acknowledge_report(BODY, "vale_guard", "ana", 2.0)
	var rig := _rig(town)
	assert_true(rig.start(_task(rig, NpcRecoveryTask.GUARD), 20.0))
	assert_eq(rig.last_finished()["reason"], &"claimed_by_other")
	assert_eq(town.deaths.snapshot(BODY)["guard"], "vale_guard")
	rig.dispose()

func test_saved_recovery_restores_only_while_the_record_agrees() -> void:
	var town := Town.new()
	_reported_to_self(town)
	var rig := _rig(town)
	var task := _task(rig, NpcRecoveryTask.GUARD)
	assert_true(rig.start(task, 20.0))
	_arrive_at(rig, &"town", BODY_POINT + NpcRecoveryTask.STAND_OFFSET)
	rig.tick(21.0)
	rig.tick(27.0)
	rig.tick(28.0)
	assert_eq(rig.phase(), NpcRecoveryTask.PHASE_REACH_CEMETERY)
	assert_true(rig.brain.save_checkpoint())
	var saved: Dictionary = rig.mind.task_checkpoint()
	rig.dispose()
	var loaded := _rig(town)
	assert_true(loaded.mind.set_task_checkpoint(saved))
	assert_true(loaded.brain.restore_checkpoint(30.0))
	assert_eq(loaded.brain.task_state(task.task_id), "RUNNING")
	assert_eq(loaded.phase(), NpcRecoveryTask.PHASE_REACH_CEMETERY)
	loaded.dispose()
	var other := Town.new()
	_fallen(other)
	other.deaths.discover(BODY, "ana", 1.0)
	other.deaths.acknowledge_report(BODY, "vale_guard", "ana", 2.0)
	var stale := _rig(other)
	assert_true(stale.mind.set_task_checkpoint(saved))
	stale.brain.restore_checkpoint(30.0)
	assert_eq(stale.brain.task_state(task.task_id), "")
	assert_eq(stale.last_finished()["reason"], &"restore_invalid")
	stale.dispose()

func test_invalid_params_are_rejected() -> void:
	var rig := Routine.Rig.new()
	var valid: Dictionary = {"role": "guard", "body": BODY, "activity": "recover_body", "label": "x"}
	var broken: Array[Dictionary] = []
	for key: String in valid:
		var missing: Dictionary = valid.duplicate()
		missing.erase(key)
		broken.append(missing)
	var role: Dictionary = valid.duplicate()
	role["role"] = "priest"
	broken.append(role)
	for params: Dictionary in broken:
		var task := NpcRecoveryTask.new()
		var saved: Dictionary = NpcRecoveryTask.create(valid, rig.tuning, "recovery:x:1").checkpoint()
		saved["params"] = params
		assert_false(task.restore_from(saved), str(params))
	rig.dispose()
