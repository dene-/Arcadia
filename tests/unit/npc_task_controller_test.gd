extends "res://tests/test_case.gd"

class ProbeTask extends NpcTask:
	var log: Array[String] = []
	var advance_result: NpcTaskResult = NpcTaskResult.running()
	var responses: Dictionary = {}
	var params_valid: bool = true
	var revalidates: bool = true

	func _init(id: String = "probe:1", task_kind: StringName = &"probe",
			task_priority: float = 0.5) -> void:
		task_id = id
		kind = task_kind
		priority = task_priority

	func _on_start(_context: NpcTaskContext) -> NpcTaskResult:
		log.append("start")
		return NpcTaskResult.running()

	func _on_advance(_context: NpcTaskContext, _minutes: float) -> NpcTaskResult:
		log.append("advance")
		return advance_result

	func _on_suspend(_context: NpcTaskContext) -> void:
		log.append("suspend")

	func _on_resume(_context: NpcTaskContext) -> NpcTaskResult:
		log.append("resume")
		return NpcTaskResult.running()

	func _on_cancel(_context: NpcTaskContext, reason: StringName) -> void:
		log.append("cancel:" + String(reason))

	func _interrupt_response(interrupt: Interrupt) -> Response:
		if responses.has(interrupt):
			return responses[interrupt]
		return super._interrupt_response(interrupt)

	func _validate_params(value: Dictionary) -> bool:
		return params_valid and not value.has("bad")

	func _revalidate(_context: NpcTaskContext) -> bool:
		return revalidates

class InstantTask extends ProbeTask:
	func _on_start(_context: NpcTaskContext) -> NpcTaskResult:
		log.append("start")
		return NpcTaskResult.completed(&"instant")

func _context(minute: float = 100.0) -> NpcTaskContext:
	var context := NpcTaskContext.new()
	context.npc_id = "holt_partner"
	context.minute = minute
	context.mind = NpcMindState.new("holt_partner")
	return context

func _probe(id: String, task_priority: float = 0.5) -> ProbeTask:
	return ProbeTask.new(id, &"probe", task_priority)

func _kinds(controller: NpcTaskController) -> void:
	controller.register_kind(&"probe", ProbeTask)

func _last(controller: NpcTaskController) -> Dictionary:
	var entries: Array[Dictionary] = controller.transitions()
	return entries[entries.size() - 1] if not entries.is_empty() else {}

func test_start_rejects_invalid_tasks_without_an_actor() -> void:
	var controller := NpcTaskController.new()
	var context := _context()
	assert_null(context.actor)
	var bad_params := _probe("bad:1")
	bad_params.params = {"bad": true}
	assert_false(controller.start(bad_params, context))
	var unsaveable := _probe("bad:2")
	unsaveable.params = {"speed": INF}
	assert_false(controller.start(unsaveable, context))
	var terminal := _probe("done:1")
	terminal.status = NpcTask.Status.COMPLETED
	assert_false(controller.start(terminal, context))
	assert_false(controller.start(_probe(""), context))
	assert_null(controller.current)
	assert_true(controller.transitions().is_empty())
	assert_true(controller.start(_probe("ok:1"), context))
	assert_false(controller.start(_probe("ok:1"), context), "duplicate id")
	var started := _probe("ok:2")
	assert_true(controller.start(started, context))
	assert_false(controller.start(started, context), "task objects start once")

func test_lower_priority_task_cannot_displace_current() -> void:
	var controller := NpcTaskController.new()
	var context := _context()
	assert_true(controller.start(_probe("urgent:1", 0.8), context))
	assert_false(controller.start(_probe("idle:1", 0.2), context))
	assert_eq(controller.current.task_id, "urgent:1")
	assert_null(controller.suspended)
	var stubborn := _probe("stubborn:1", 0.6)
	stubborn.responses[NpcTask.Interrupt.REPLACED] = NpcTask.Response.CONTINUE
	var other := NpcTaskController.new()
	assert_true(other.start(stubborn, context))
	assert_false(other.start(_probe("peer:1", 0.9), context))
	assert_eq(other.current.task_id, "stubborn:1")

func test_start_acquires_claims_and_completion_releases_them() -> void:
	var controller := NpcTaskController.new()
	var context := _context()
	var task := _probe("routine:1")
	assert_true(controller.start(task, context))
	assert_eq(controller.claim_owner(&"locomotion"), "routine:1")
	assert_eq(task.generation, 1)
	assert_eq(task.started_minute, 100.0)
	task.advance_result = NpcTaskResult.completed(&"arrived")
	controller.advance(context, 5.0)
	assert_null(controller.current)
	assert_eq(task.status, NpcTask.Status.COMPLETED)
	assert_eq(controller.claim_owner(&"locomotion"), "")
	assert_eq(_last(controller)["reason"], "arrived")

func test_immediate_completion_resumes_displaced_task() -> void:
	var controller := NpcTaskController.new()
	var context := _context()
	var routine := _probe("routine:1")
	assert_true(controller.start(routine, context))
	var quick := InstantTask.new("quick:1", &"quick", 0.7)
	assert_true(controller.start(quick, context))
	assert_eq(quick.status, NpcTask.Status.COMPLETED)
	assert_eq(controller.current, routine)
	assert_eq(routine.log, ["start", "suspend", "resume"] as Array[String])
	assert_eq(controller.claim_owner(&"locomotion"), "routine:1")

func test_claims_are_owner_checked() -> void:
	var controller := NpcTaskController.new()
	var context := _context()
	assert_true(controller.start(_probe("routine:1"), context))
	assert_false(controller.release_claim(&"locomotion", "session:social:1"))
	assert_eq(controller.claim_owner(&"locomotion"), "routine:1")
	assert_false(controller.acquire_claim(&"locomotion", "session:social:1"))
	assert_true(controller.acquire_claim(&"conversation", "session:social:1"))
	assert_true(controller.acquire_claim(&"conversation", "session:social:1"), "re-acquire by owner")
	assert_false(controller.acquire_claim(&"conversation", "session:other"))
	assert_false(controller.release_claim(&"conversation", "session:other"))
	assert_true(controller.release_claim(&"conversation", "session:social:1"))
	assert_false(controller.release_claim(&"conversation", "session:social:1"), "idempotent")

func test_session_claim_blocks_ordinary_task_but_not_urgent_one() -> void:
	var controller := NpcTaskController.new()
	var context := _context()
	var revoked: Array[String] = []
	controller.claim_revoked.connect(
		func(claim: StringName, owner: String) -> void: revoked.append("%s:%s" % [claim, owner]))
	assert_true(controller.acquire_claim(&"locomotion", "session:social:1"))
	assert_false(controller.start(_probe("routine:1"), context))
	assert_null(controller.current)
	assert_eq(controller.claim_owner(&"locomotion"), "session:social:1")
	assert_true(revoked.is_empty())
	assert_true(controller.start(_probe("safety:1", 0.95), context))
	assert_eq(controller.claim_owner(&"locomotion"), "safety:1")
	assert_eq(revoked, ["locomotion:session:social:1"] as Array[String])
	assert_false(controller.release_claim(&"locomotion", "session:social:1"))

func test_second_task_suspends_first_and_third_displaces_the_older_suspended() -> void:
	var controller := NpcTaskController.new()
	var context := _context()
	var first := _probe("first:1")
	var second := _probe("second:1")
	var third := _probe("third:1")
	assert_true(controller.start(first, context))
	assert_true(controller.start(second, context))
	assert_eq(controller.current, second)
	assert_eq(controller.suspended, first)
	assert_eq(first.status, NpcTask.Status.SUSPENDED)
	assert_eq(controller.claim_owner(&"locomotion"), "second:1")
	assert_true(controller.start(third, context))
	assert_eq(controller.current, third)
	assert_eq(controller.suspended, second)
	assert_eq(first.status, NpcTask.Status.CANCELLED)
	assert_eq(first.log.back(), "cancel:displaced")
	third.advance_result = NpcTaskResult.completed()
	controller.advance(context, 1.0)
	assert_eq(controller.current, second)
	assert_null(controller.suspended)
	assert_eq(second.status, NpcTask.Status.RUNNING)
	assert_eq(second.log, ["start", "suspend", "resume"] as Array[String])
	assert_eq(first.status, NpcTask.Status.CANCELLED, "cancelled tasks never resume")
	assert_eq(controller.claim_owner(&"locomotion"), "second:1")

func test_resume_revalidates_and_cancels_invalid_suspended_task() -> void:
	var controller := NpcTaskController.new()
	var context := _context()
	var first := _probe("first:1")
	var second := _probe("second:1")
	assert_true(controller.start(first, context))
	assert_true(controller.start(second, context))
	first.revalidates = false
	second.advance_result = NpcTaskResult.completed()
	controller.advance(context, 1.0)
	assert_null(controller.current)
	assert_null(controller.suspended)
	assert_eq(first.status, NpcTask.Status.CANCELLED)
	assert_eq(_last(controller)["reason"], "invalid_on_resume")
	assert_false(first.log.has("resume"))

func test_interrupt_policy_and_explicit_resume() -> void:
	var controller := NpcTaskController.new()
	var context := _context()
	var task := _probe("routine:1")
	assert_true(controller.start(task, context))
	controller.interrupt(NpcTask.Interrupt.SCHEDULE, context)
	assert_eq(controller.current, task)
	controller.interrupt(NpcTask.Interrupt.HURT, context)
	assert_null(controller.current)
	assert_eq(controller.suspended, task)
	assert_eq(controller.claim_owner(&"locomotion"), "")
	assert_eq(_last(controller)["reason"], "hurt")
	controller.advance(context, 1.0)
	assert_null(controller.current, "advance never resumes on its own")
	assert_true(controller.acquire_claim(&"locomotion", "session:social:1"))
	assert_false(controller.resume(context), "claims held by a session")
	assert_true(controller.release_claim(&"locomotion", "session:social:1"))
	assert_true(controller.resume(context))
	assert_eq(controller.current, task)
	task.responses[NpcTask.Interrupt.DANGER] = NpcTask.Response.CANCEL
	controller.interrupt(NpcTask.Interrupt.DANGER, context)
	assert_eq(task.status, NpcTask.Status.CANCELLED)
	assert_eq(controller.claim_owner(&"locomotion"), "")

func test_finish_and_cancel_are_idempotent_and_ignore_stale_notices() -> void:
	var controller := NpcTaskController.new()
	var context := _context()
	var task := _probe("routine:1")
	assert_true(controller.start(task, context))
	var generation: int = task.generation
	assert_false(controller.finish("routine:1", generation + 1, NpcTaskResult.completed(), context))
	assert_false(controller.finish("other:1", generation, NpcTaskResult.completed(), context))
	assert_false(controller.finish("routine:1", generation, NpcTaskResult.running(), context))
	assert_eq(controller.current, task)
	assert_true(controller.finish("routine:1", generation, NpcTaskResult.completed(), context))
	var transition_count: int = controller.transitions().size()
	assert_false(controller.finish("routine:1", generation, NpcTaskResult.failed(&"late"), context))
	assert_false(controller.cancel("routine:1", &"late", context))
	assert_eq(task.status, NpcTask.Status.COMPLETED)
	assert_eq(controller.transitions().size(), transition_count)
	var replacement := _probe("routine:1")
	assert_true(controller.start(replacement, context), "a finished id may be started again")
	assert_false(controller.finish("routine:1", generation, NpcTaskResult.completed(), context),
		"old generation of a reused id")
	assert_true(controller.cancel("routine:1", &"changed_mind", context))
	assert_false(controller.cancel("routine:1", &"changed_mind", context))
	assert_eq(replacement.log.back(), "cancel:changed_mind")

func test_death_cancels_everything_and_releases_all_claims() -> void:
	var controller := NpcTaskController.new()
	var context := _context()
	var first := _probe("first:1")
	var second := _probe("second:1")
	assert_true(controller.start(first, context))
	assert_true(controller.start(second, context))
	assert_true(controller.acquire_claim(&"conversation", "session:social:1"))
	var revoked: Array[String] = []
	controller.claim_revoked.connect(
		func(claim: StringName, owner: String) -> void: revoked.append("%s:%s" % [claim, owner]))
	controller.interrupt(NpcTask.Interrupt.DEATH, context)
	assert_null(controller.current)
	assert_null(controller.suspended)
	assert_eq(first.status, NpcTask.Status.CANCELLED)
	assert_eq(second.status, NpcTask.Status.CANCELLED)
	assert_eq(controller.claim_owner(&"locomotion"), "")
	assert_eq(controller.claim_owner(&"conversation"), "")
	assert_true(revoked.has("conversation:session:social:1"))
	assert_true(controller.checkpoint().is_empty())
	assert_false(controller.resume(context))
	controller.interrupt(NpcTask.Interrupt.DEATH, context)
	assert_eq(second.log.filter(func(entry: String) -> bool: return entry.begins_with("cancel")).size(), 1)

func test_deadline_fails_the_task_and_blocked_retry_past_deadline_fails() -> void:
	var controller := NpcTaskController.new()
	var context := _context(100.0)
	var task := _probe("routine:1")
	task.deadline_minute = 130.0
	assert_true(controller.start(task, context))
	context.minute = 130.0
	controller.advance(context, 30.0)
	assert_eq(controller.current, task, "deadline is exclusive")
	context.minute = 130.5
	controller.advance(context, 0.5)
	assert_null(controller.current)
	assert_eq(task.status, NpcTask.Status.FAILED)
	assert_eq(_last(controller)["reason"], "deadline")
	assert_eq(controller.claim_owner(&"locomotion"), "")
	var blocked := _probe("routine:2")
	blocked.deadline_minute = 200.0
	context.minute = 150.0
	assert_true(controller.start(blocked, context))
	blocked.advance_result = NpcTaskResult.blocked(&"path_closed", 400.0)
	controller.advance(context, 1.0)
	assert_eq(blocked.status, NpcTask.Status.FAILED)
	assert_eq(_last(controller)["reason"], "deadline")

func test_blocked_result_is_recorded_once_per_reason() -> void:
	var controller := NpcTaskController.new()
	var context := _context()
	var task := _probe("routine:1")
	assert_true(controller.start(task, context))
	var count: int = controller.transitions().size()
	task.advance_result = NpcTaskResult.blocked(&"path_closed", 130.0)
	controller.advance(context, 1.0)
	controller.advance(context, 1.0)
	assert_eq(controller.transitions().size(), count + 1)
	assert_eq(controller.current, task)
	assert_eq(task.status, NpcTask.Status.RUNNING)
	task.advance_result = NpcTaskResult.blocked(&"door_locked", 130.0)
	controller.advance(context, 1.0)
	assert_eq(controller.transitions().size(), count + 2)

func test_transition_log_is_bounded() -> void:
	var controller := NpcTaskController.new()
	var context := _context()
	for index: int in NpcTaskController.MAX_TRANSITIONS:
		var task := InstantTask.new("quick:%d" % index, &"quick", 0.5)
		assert_true(controller.start(task, context))
	var entries: Array[Dictionary] = controller.transitions()
	assert_eq(entries.size(), NpcTaskController.MAX_TRANSITIONS)
	assert_eq(entries[entries.size() - 1]["task_id"], "quick:%d" % (NpcTaskController.MAX_TRANSITIONS - 1))

func test_services_report_missing_capabilities() -> void:
	var context := _context()
	var calls: Array[String] = []
	context.services["travel"] = func(target: String) -> bool:
		calls.append(target)
		return true
	assert_true(context.has_service(&"travel"))
	assert_eq(context.call_service(&"travel", ["bakery"]), true)
	assert_eq(calls, ["bakery"] as Array[String])
	assert_false(context.has_service(&"cancel_travel"))
	assert_null(context.call_service(&"cancel_travel"))
	assert_eq(context.errors.size(), 1)

func _checkpointed_controller(context: NpcTaskContext) -> NpcTaskController:
	var controller := NpcTaskController.new()
	_kinds(controller)
	var first := _probe("first:1")
	first.phase = "walking"
	first.params = {"target": "bakery", "wait": 12.5}
	first.progress = {"leg": "street"}
	first.evidence_ids = ["ev:1"] as Array[String]
	first.commitment_ids = ["cm:1"] as Array[String]
	first.deadline_minute = 500.0
	var second := _probe("second:1", 0.7)
	second.params = {"target": "well"}
	assert_true(controller.start(first, context))
	assert_true(controller.start(second, context))
	return controller

func test_checkpoint_round_trips_through_mind_state_and_json() -> void:
	var context := _context()
	var controller := _checkpointed_controller(context)
	var saved: Dictionary = controller.checkpoint()
	assert_true(NpcMindState.is_valid_task_checkpoint(saved))
	assert_true(context.mind.set_task_checkpoint(saved))
	var from_disk: Variant = JSON.parse_string(JSON.stringify(context.mind.task_checkpoint()))
	var reloaded := NpcMindState.new("holt_partner")
	assert_true(reloaded.set_task_checkpoint(from_disk as Dictionary))
	var restored_context := _context(200.0)
	var restored := NpcTaskController.new()
	_kinds(restored)
	assert_true(restored.restore(reloaded.task_checkpoint(), restored_context))
	assert_eq(restored.current.task_id, "second:1")
	assert_eq(restored.current.status, NpcTask.Status.RUNNING)
	assert_eq(restored.suspended.task_id, "first:1")
	assert_eq(restored.suspended.status, NpcTask.Status.SUSPENDED)
	assert_eq(restored.suspended.phase, "walking")
	assert_eq(restored.suspended.params, {"target": "bakery", "wait": 12.5})
	assert_eq(restored.suspended.progress, {"leg": "street"})
	assert_eq(restored.suspended.evidence_ids, ["ev:1"] as Array[String])
	assert_eq(restored.suspended.commitment_ids, ["cm:1"] as Array[String])
	assert_eq(restored.suspended.deadline_minute, 500.0)
	assert_eq(restored.claim_owner(&"locomotion"), "second:1")
	assert_eq(restored.generation, controller.generation)
	assert_eq(restored.checkpoint(), reloaded.task_checkpoint())
	assert_eq((restored.current as ProbeTask).log, ["resume"] as Array[String], "never restarts")
	assert_eq((restored.suspended as ProbeTask).log.size(), 0)

func test_restore_suspended_only_checkpoint() -> void:
	var context := _context()
	var controller := NpcTaskController.new()
	_kinds(controller)
	assert_true(controller.start(_probe("routine:1"), context))
	controller.interrupt(NpcTask.Interrupt.HURT, context)
	var saved: Dictionary = controller.checkpoint()
	assert_eq(saved["status"], "SUSPENDED")
	assert_true(context.mind.set_task_checkpoint(saved))
	var restored := NpcTaskController.new()
	_kinds(restored)
	assert_true(restored.restore(saved, _context()))
	assert_null(restored.current)
	assert_eq(restored.suspended.task_id, "routine:1")
	assert_eq(restored.claim_owner(&"locomotion"), "")

func test_restore_unknown_kind_or_failed_revalidation_cancels_with_reason() -> void:
	var context := _context()
	var controller := NpcTaskController.new()
	_kinds(controller)
	assert_true(controller.start(_probe("routine:1"), context))
	var saved: Dictionary = controller.checkpoint()
	var unknown := NpcTaskController.new()
	assert_false(unknown.restore(saved, context))
	assert_null(unknown.current)
	assert_eq(_last(unknown)["reason"], "restore_invalid")
	assert_eq(_last(unknown)["task_id"], "routine:1")
	assert_eq(_last(unknown)["to"], "CANCELLED")
	assert_eq(unknown.claim_owner(&"locomotion"), "")
	var stale := NpcTaskController.new()
	stale.register_kind(&"probe", StaleTask)
	assert_false(stale.restore(saved, context))
	assert_null(stale.current)
	assert_eq(_last(stale)["reason"], "restore_invalid")
	var malformed := NpcTaskController.new()
	_kinds(malformed)
	assert_false(malformed.restore({"task_id": "x"}, context))
	assert_true(malformed.transitions().is_empty())

class StaleTask extends ProbeTask:
	func _revalidate(_context: NpcTaskContext) -> bool:
		return false

# routine:1 is interrupted by a conversation session, then a safety task takes over. Late
# session release, late routine completion and a stale safety completion arrive in every order.
func test_late_callbacks_never_disturb_the_safety_owner_in_any_order() -> void:
	var orders: Array = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
	for order: Array in orders:
		var controller := NpcTaskController.new()
		var context := _context()
		var routine := _probe("routine:1")
		var safety := _probe("safety:1", 0.95)
		assert_true(controller.start(routine, context))
		var routine_generation: int = routine.generation
		controller.interrupt(NpcTask.Interrupt.CONVERSATION, context)
		assert_true(controller.acquire_claim(&"locomotion", "session:social:1"))
		assert_true(controller.acquire_claim(&"conversation", "session:social:1"))
		assert_true(controller.start(safety, context), str(order))
		for step: int in order:
			match step:
				0:
					controller.release_claim(&"locomotion", "session:social:1")
					controller.release_claim(&"conversation", "session:social:1")
				1:
					assert_false(controller.finish("routine:1", routine_generation,
						NpcTaskResult.completed(), context))
				2:
					assert_false(controller.finish("safety:1", safety.generation - 1,
						NpcTaskResult.failed(&"stale"), context))
			assert_eq(controller.current, safety, str(order))
			assert_eq(controller.claim_owner(&"locomotion"), "safety:1", str(order))
			assert_eq(controller.claim_owner(&"conversation"), "", str(order))
			assert_eq(controller.suspended, routine, str(order))
			assert_eq(routine.status, NpcTask.Status.SUSPENDED, str(order))
			assert_false(routine.log.has("resume"), str(order))
		controller.advance(context, 1.0)
		assert_eq(controller.current, safety)
		safety.advance_result = NpcTaskResult.completed()
		controller.advance(context, 1.0)
		assert_eq(controller.current, routine, str(order))
		assert_eq(controller.claim_owner(&"locomotion"), "routine:1")
		assert_eq(routine.log.count("resume"), 1)
