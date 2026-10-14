extends "res://tests/test_case.gd"

const Routine = preload("res://tests/unit/npc_routine_task_test.gd")
const Safety = preload("res://tests/unit/npc_safety_task_test.gd")

func _social(rig: Routine.Rig, session_id: String = "social:1",
		partner_id: String = "garrin_holt", role: String = "initiator") -> NpcSocialTask:
	return NpcSocialTask.create(session_id, partner_id, role, rig.tuning)

func _join(rig: Routine.Rig, task: NpcSocialTask, minute: float) -> bool:
	rig.brain.advance(minute, 0.0)
	return rig.brain.request_conversation(task.params["session_id"] as String) \
		and rig.brain.request_task(task)

func test_session_task_owns_both_claims_under_the_session_owner() -> void:
	var rig := Routine.Rig.new()
	var task := _social(rig)
	assert_eq(task.task_id, NpcSocialTask.owner_for("social:1"))
	assert_eq(task.priority, rig.tuning.hold_priority)
	assert_true(_join(rig, task, 100.0))
	var activity: Dictionary = rig.brain.current_activity()
	assert_eq(activity["kind"], "social")
	assert_eq(activity["activity"], "conversation")
	assert_eq(activity["phase"], NpcSocialTask.PHASE_APPROACH)
	assert_eq(rig.brain.controller.claim_owner(&"locomotion"), task.task_id)
	assert_eq(rig.brain.controller.claim_owner(&"conversation"), task.task_id)
	assert_false(rig.brain.request_conversation("social:2"), "one session at a time")
	task.converse()
	assert_eq(rig.phase(), NpcSocialTask.PHASE_CONVERSE)
	task.leave()
	assert_eq(rig.phase(), NpcSocialTask.PHASE_LEAVE)
	assert_true(rig.brain.end_task(task.task_id))
	rig.brain.finish_conversation("social:1")
	assert_eq(rig.brain.controller.claim_owner(&"locomotion"), "")
	assert_eq(rig.brain.controller.claim_owner(&"conversation"), "")
	assert_false(rig.brain.end_task(task.task_id), "ending twice changes nothing")
	rig.dispose()

func test_approach_is_bounded_but_conversation_is_not() -> void:
	var rig := Routine.Rig.new()
	var stuck := _social(rig)
	assert_true(_join(rig, stuck, 100.0))
	rig.tick(100.0 + NpcSocialTask.APPROACH_MINUTES)
	assert_eq(rig.brain.task_state(stuck.task_id), "RUNNING", "the bound is exclusive")
	rig.tick(101.5)
	assert_eq(rig.last_finished()["status"], "FAILED")
	assert_eq(rig.last_finished()["reason"], &"approach_timeout")
	var talking := _social(rig, "social:2")
	assert_true(_join(rig, talking, 110.0))
	talking.converse()
	rig.tick(200.0)
	assert_eq(rig.brain.task_state(talking.task_id), "RUNNING")
	rig.dispose()

func test_routine_waits_for_the_session_and_resumes_after_it() -> void:
	var rig := Routine.Rig.new()
	var routine := NpcRoutineTask.create(Routine.routine_params("work", "bakery", 900.0), rig.tuning)
	assert_true(rig.start(routine, 100.0))
	var task := _social(rig, "social:1", "garrin_holt", "partner")
	assert_true(_join(rig, task, 101.0))
	assert_eq(rig.brain.task_state(routine.task_id), "SUSPENDED")
	assert_eq(rig.executor.cancelled, [routine.task_id] as Array[String], "talking never travels")
	rig.brain.interrupt(NpcTask.Interrupt.SCHEDULE)
	assert_eq(rig.brain.task_state(task.task_id), "RUNNING")
	assert_true(rig.brain.end_task(task.task_id))
	rig.brain.finish_conversation("social:1")
	rig.tick(102.0)
	assert_eq(rig.brain.task_state(routine.task_id), "RUNNING")
	rig.dispose()

func test_danger_hurt_player_and_death_cancel_the_session() -> void:
	var interrupts: Dictionary = {NpcTask.Interrupt.DANGER: &"danger", NpcTask.Interrupt.HURT: &"hurt",
		NpcTask.Interrupt.CONVERSATION: &"conversation", NpcTask.Interrupt.DEATH: &"death"}
	for interrupt: NpcTask.Interrupt in interrupts:
		var rig := Routine.Rig.new()
		var task := _social(rig)
		assert_true(_join(rig, task, 100.0))
		rig.brain.interrupt(interrupt)
		assert_eq(rig.last_finished()["task_id"], task.task_id)
		assert_eq(rig.last_finished()["status"], "CANCELLED")
		assert_eq(rig.last_finished()["reason"], interrupts[interrupt])
		assert_eq(rig.brain.controller.claim_owner(&"locomotion"), "")
		rig.dispose()

func test_shelter_replaces_the_session_and_its_late_release_changes_nothing() -> void:
	var rig := Routine.Rig.new()
	var task := _social(rig)
	assert_true(_join(rig, task, 100.0))
	var shelter := NpcSafetyTask.create(Safety.safety_params("SHELTER", 300.0, "plaza", [1.0, 2.0]),
		rig.tuning)
	assert_true(rig.start(shelter, 101.0))
	assert_eq(rig.last_finished()["task_id"], task.task_id)
	assert_eq(rig.last_finished()["status"], "CANCELLED")
	assert_false(rig.brain.end_task(task.task_id))
	rig.brain.finish_conversation("social:1")
	assert_eq(rig.brain.controller.claim_owner(&"locomotion"), shelter.task_id)
	assert_eq(rig.brain.controller.claim_owner(&"conversation"), shelter.task_id)
	rig.dispose()

func test_urgent_duty_refuses_a_session() -> void:
	var rig := Routine.Rig.new()
	var caution := NpcSafetyTask.create(Safety.safety_params("CAUTION", 500.0), rig.tuning)
	assert_true(rig.start(caution, 100.0))
	assert_false(rig.brain.accepts_conversation())
	var task := _social(rig, "player:1", "player", "partner")
	assert_false(_join(rig, task, 101.0))
	assert_false(rig.brain.request_task(task))
	assert_eq(rig.brain.current_activity()["task_id"], caution.task_id)
	rig.dispose()

func test_sessions_are_runtime_only_and_never_restored() -> void:
	var rig := Routine.Rig.new()
	var task := _social(rig)
	assert_true(_join(rig, task, 100.0))
	task.converse()
	assert_true(rig.brain.save_checkpoint())
	var loaded := Routine.Rig.new()
	assert_true(loaded.mind.from_data(JSON.parse_string(JSON.stringify(rig.mind.to_data()))))
	loaded.brain.restore_checkpoint(105.0)
	assert_eq(loaded.last_finished()["task_id"], task.task_id)
	assert_eq(loaded.last_finished()["reason"], &"restore_invalid")
	assert_true(loaded.brain.current_activity().is_empty())
	assert_eq(loaded.brain.controller.claim_owner(&"conversation"), "")
	rig.dispose()
	loaded.dispose()

func test_invalid_params_are_rejected() -> void:
	var rig := Routine.Rig.new()
	for task: NpcSocialTask in [_social(rig, ""), _social(rig, "social:1", ""),
			_social(rig, "social:1", "garrin_holt", "bystander")]:
		assert_false(rig.brain.request_task(task), str(task.params))
	assert_true(rig.brain.current_activity().is_empty())
	rig.dispose()

func test_a_delivered_exchange_eases_social_need_once_and_only_while_talking() -> void:
	var rig := Routine.Rig.new()
	rig.mind.needs.social = 0.6
	var task := _social(rig)
	assert_true(_join(rig, task, 100.0))
	assert_false(task.deliver_exchange(), "nothing is said while still approaching")
	assert_eq(rig.mind.needs.social, 0.6)
	task.converse()
	assert_true(task.deliver_exchange())
	assert_true(is_equal_approx(rig.mind.needs.social, 0.6 - rig.tuning.exchange_social_relief))
	assert_false(task.deliver_exchange(), "one exchange per session")
	assert_true(is_equal_approx(rig.mind.needs.social, 0.6 - rig.tuning.exchange_social_relief))
	assert_true(rig.brain.end_task(task.task_id))
	assert_false(task.deliver_exchange(), "a finished session delivers nothing")
	rig.dispose()

func test_conversation_suspends_work_engagement() -> void:
	var rig := Routine.Rig.new()
	var routine := NpcRoutineTask.create(Routine.routine_params("work", "bakery", 900.0), rig.tuning)
	assert_true(rig.start(routine, 100.0))
	rig.executor.arrive()
	rig.tick(101.0)
	assert_eq(routine.confirmed_engagement(), &"work")
	var task := _social(rig, "social:1", "garrin_holt", "partner")
	assert_true(_join(rig, task, 102.0))
	assert_eq(routine.confirmed_engagement(), &"")
	rig.dispose()
