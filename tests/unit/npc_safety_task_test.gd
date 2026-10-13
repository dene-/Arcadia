extends "res://tests/test_case.gd"

const Routine = preload("res://tests/unit/npc_routine_task_test.gd")

static func safety_params(response: String, until: float, refuge_space: String = "",
		refuge_point: Array = []) -> Dictionary:
	return {"response": response, "origin_id": "noise:1", "until_minute": until,
		"label": "Taking cover", "refuge_space": refuge_space, "refuge_point": refuge_point}

func _caution(rig: Routine.Rig, until: float) -> NpcSafetyTask:
	return NpcSafetyTask.create(safety_params("CAUTION", until), rig.tuning)

func _shelter(rig: Routine.Rig, until: float, refuge_space: String = "plaza",
		refuge_point: Array = [10.0, 20.0]) -> NpcSafetyTask:
	return NpcSafetyTask.create(safety_params("SHELTER", until, refuge_space, refuge_point),
		rig.tuning)

func test_caution_keeps_a_sleeper_asleep_and_stays_put() -> void:
	var rig := Routine.Rig.new()
	rig.actor.sleeping = true
	var task: NpcSafetyTask = _caution(rig, 500.0)
	assert_true(rig.start(task, 100.0))
	assert_eq(task.priority, rig.tuning.caution_priority)
	assert_eq(rig.phase(), "assess")
	assert_true(rig.actor.sleeping)
	assert_true(rig.actor.log.is_empty())
	assert_true(rig.executor.begun.is_empty())
	assert_eq(rig.brain.controller.claim_owner(&"locomotion"), task.task_id)
	rig.tick(105.0)
	assert_eq(rig.brain.task_state(task.task_id), "RUNNING")
	rig.tick(100.0 + rig.tuning.caution_minutes)
	assert_eq(rig.last_finished()["status"], "COMPLETED")
	assert_eq(rig.last_finished()["reason"], &"caution_elapsed")
	assert_true(rig.actor.sleeping)
	assert_eq(rig.brain.controller.claim_owner(&"locomotion"), "")
	rig.dispose()

func test_caution_ends_at_its_own_deadline_when_that_comes_first() -> void:
	var rig := Routine.Rig.new()
	assert_true(rig.start(_caution(rig, 104.0), 100.0))
	rig.tick(103.0)
	assert_eq(rig.brain.controller.current.phase, "assess")
	rig.tick(104.0)
	assert_eq(rig.last_finished()["reason"], &"until")
	rig.dispose()

func test_caution_halts_a_journey_and_the_routine_reroutes_afterwards() -> void:
	var rig := Routine.Rig.new()
	var routine := NpcRoutineTask.create(Routine.routine_params("work", "bakery", 900.0), rig.tuning)
	assert_true(rig.start(routine, 100.0))
	assert_true(rig.start(_caution(rig, 500.0), 101.0))
	assert_eq(rig.brain.task_state(routine.task_id), "SUSPENDED")
	assert_eq(rig.executor.cancelled, [routine.task_id] as Array[String])
	assert_eq(rig.executor.begun.size(), 1, "caution never starts a journey")
	rig.tick(101.0 + rig.tuning.caution_minutes)
	assert_eq(rig.last_finished()["reason"], &"caution_elapsed")
	assert_eq(rig.brain.task_state(routine.task_id), "RUNNING")
	assert_eq(rig.executor.owners(), [routine.task_id, routine.task_id] as Array[String])
	rig.dispose()

func test_shelter_waits_for_orientation_then_wakes_and_flees_only_to_the_refuge() -> void:
	var rig := Routine.Rig.new()
	rig.actor.sleeping = true
	rig.actor.world_space = &"home"
	rig.actor.alert_response.alert_active = true
	var task: NpcSafetyTask = _shelter(rig, 300.0)
	assert_true(rig.start(task, 100.0))
	assert_eq(task.priority, rig.tuning.shelter_priority)
	assert_eq(rig.phase(), "orient")
	rig.tick(101.0)
	rig.tick(102.0)
	assert_eq(rig.phase(), "orient", "the real-second reflex is not re-timed")
	assert_true(rig.actor.sleeping)
	assert_true(rig.executor.begun.is_empty())
	rig.actor.alert_response.alert_active = false
	rig.tick(103.0)
	assert_eq(rig.actor.log, ["wake:danger"] as Array[String])
	assert_eq(rig.phase(), "flee")
	assert_eq(rig.executor.begun.size(), 1)
	assert_eq(rig.executor.begun[0]["space"], &"plaza", "never the room the danger was heard in")
	assert_eq(rig.executor.begun[0]["point"], Vector2(10.0, 20.0))
	assert_eq(rig.executor.begun[0]["owner"], task.task_id)
	rig.tick(110.0)
	assert_eq(rig.phase(), "flee")
	rig.executor.arrive()
	rig.tick(120.0)
	assert_eq(rig.phase(), "shelter")
	assert_eq(rig.executor.begun.size(), 1)
	rig.tick(299.0)
	assert_eq(rig.brain.task_state(task.task_id), "RUNNING")
	rig.tick(300.0)
	assert_eq(rig.last_finished()["status"], "COMPLETED")
	assert_eq(rig.last_finished()["reason"], &"until")
	rig.dispose()

func test_awake_shelter_acts_at_once_and_without_a_refuge_stays_put() -> void:
	var rig := Routine.Rig.new()
	var task := NpcSafetyTask.create(safety_params("SHELTER", 300.0), rig.tuning)
	assert_true(rig.start(task, 100.0))
	assert_eq(rig.phase(), "shelter")
	assert_true(rig.executor.begun.is_empty())
	rig.tick(150.0)
	assert_true(rig.executor.begun.is_empty())
	assert_eq(rig.brain.controller.claim_owner(&"locomotion"), task.task_id)
	rig.dispose()

func test_unreachable_refuge_leaves_the_resident_sheltering_in_place() -> void:
	var refused := Routine.Rig.new()
	assert_true(refused.start(NpcRoutineTask.create(Routine.routine_params("work", "bakery", 900.0),
		refused.tuning), 100.0))
	refused.executor.accept = false
	assert_true(refused.start(_shelter(refused, 300.0), 101.0))
	assert_eq(refused.phase(), "shelter")
	refused.dispose()
	var failed := Routine.Rig.new()
	assert_true(failed.start(_shelter(failed, 300.0), 100.0))
	assert_eq(failed.phase(), "flee")
	failed.executor.fail()
	failed.tick(105.0)
	assert_eq(failed.phase(), "shelter")
	failed.dispose()
	var slow := Routine.Rig.new()
	assert_true(slow.start(_shelter(slow, 900.0), 100.0))
	slow.tick(100.0 + slow.tuning.travel_timeout_minutes)
	assert_eq(slow.phase(), "flee")
	slow.tick(101.0 + slow.tuning.travel_timeout_minutes)
	assert_eq(slow.phase(), "shelter")
	assert_eq(slow.executor.cancelled.size(), 1)
	slow.dispose()

func test_shelter_replaces_caution_but_caution_cannot_replace_shelter() -> void:
	var rig := Routine.Rig.new()
	var caution := _caution(rig, 500.0)
	assert_true(rig.start(caution, 100.0))
	var shelter := _shelter(rig, 300.0)
	assert_true(rig.start(shelter, 101.0))
	assert_eq(rig.last_finished()["task_id"], caution.task_id)
	assert_eq(rig.last_finished()["status"], "CANCELLED")
	assert_eq(rig.last_finished()["reason"], &"replaced")
	assert_false(rig.start(_caution(rig, 500.0), 102.0))
	rig.dispose()

func test_only_death_and_replacement_end_a_safety_task() -> void:
	var rig := Routine.Rig.new()
	var task := _shelter(rig, 300.0)
	assert_true(rig.start(task, 100.0))
	for kind: NpcTask.Interrupt in [NpcTask.Interrupt.HURT, NpcTask.Interrupt.DANGER,
			NpcTask.Interrupt.CONVERSATION, NpcTask.Interrupt.SCHEDULE]:
		rig.brain.interrupt(kind)
		assert_eq(rig.brain.task_state(task.task_id), "RUNNING", NpcTask.interrupt_name(kind))
	rig.brain.interrupt(NpcTask.Interrupt.DEATH)
	assert_eq(rig.last_finished()["reason"], &"death")
	assert_eq(rig.executor.cancelled, [task.task_id] as Array[String])
	rig.dispose()

func test_restore_reroutes_a_live_flight_and_ends_an_expired_one_explicitly() -> void:
	var rig := Routine.Rig.new()
	var task := _shelter(rig, 300.0)
	assert_true(rig.start(task, 100.0))
	rig.tick(110.0)
	assert_true(rig.brain.save_checkpoint())
	var live := Routine.Rig.new()
	live.mind.set_task_checkpoint(rig.mind.task_checkpoint())
	assert_true(live.brain.restore_checkpoint(120.0))
	assert_eq(live.brain.controller.current.priority, live.tuning.shelter_priority)
	assert_eq(live.phase(), "flee")
	assert_eq(live.executor.owners(), [task.task_id] as Array[String])
	assert_eq(live.brain.controller.claim_owner(&"locomotion"), task.task_id)
	var expired := Routine.Rig.new()
	expired.mind.set_task_checkpoint(rig.mind.task_checkpoint())
	assert_false(expired.brain.restore_checkpoint(301.0))
	assert_null(expired.brain.controller.current)
	assert_eq(expired.last_finished()["task_id"], task.task_id)
	assert_eq(expired.last_finished()["status"], "CANCELLED")
	assert_eq(expired.last_finished()["reason"], &"restore_invalid")
	assert_true(expired.executor.begun.is_empty())
	assert_eq(expired.brain.controller.claim_owner(&"locomotion"), "")
	rig.dispose()
	live.dispose()
	expired.dispose()

func test_restored_orientation_continues_without_the_unsaved_reflex() -> void:
	var rig := Routine.Rig.new()
	rig.actor.sleeping = true
	rig.actor.alert_response.alert_active = true
	assert_true(rig.start(_shelter(rig, 300.0), 100.0))
	assert_eq(rig.phase(), "orient")
	assert_true(rig.brain.save_checkpoint())
	var loaded := Routine.Rig.new()
	loaded.actor.sleeping = true
	loaded.mind.set_task_checkpoint(rig.mind.task_checkpoint())
	assert_true(loaded.brain.restore_checkpoint(101.0))
	assert_eq(loaded.phase(), "flee")
	assert_false(loaded.actor.sleeping)
	rig.dispose()
	loaded.dispose()

func test_invalid_params_are_rejected() -> void:
	var rig := Routine.Rig.new()
	var broken: Array[Dictionary] = [
		safety_params("PANIC", 300.0),
		safety_params("SHELTER", 300.0, "plaza"),
		safety_params("SHELTER", 300.0, "", [1.0, 2.0]),
		safety_params("SHELTER", 300.0, "plaza", [1.0]),
		safety_params("SHELTER", 300.0, "plaza", ["a", "b"]),
	]
	var no_time := safety_params("SHELTER", 300.0)
	no_time.erase("until_minute")
	broken.append(no_time)
	var no_origin := safety_params("CAUTION", 300.0)
	no_origin.erase("origin_id")
	broken.append(no_origin)
	for params: Dictionary in broken:
		assert_false(rig.start(NpcSafetyTask.create(params, rig.tuning), 100.0), str(params))
	assert_null(rig.brain.controller.current)
	rig.dispose()
