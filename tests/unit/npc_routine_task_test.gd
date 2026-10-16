extends "res://tests/test_case.gd"

class FakeAlert extends RefCounted:
	var alert_active: bool = false

	func active() -> bool:
		return alert_active

class FakeActor extends RefCounted:
	var health: int = 3
	var world_space: StringName = &"town"
	var global_position: Vector2 = Vector2.ZERO
	var alert_response := FakeAlert.new()
	var sleeping: bool = false
	var slept_at: Vector2 = Vector2.INF
	var can_follow: bool = true
	var log: Array[String] = []

	func is_sleeping() -> bool:
		return sleeping

	func sleep_at(center: Vector2) -> void:
		sleeping = true
		log.append("sleep")
		slept_at = center

	func wake_from_noise(reason: String) -> void:
		sleeping = false
		log.append("wake:" + reason)

	func interrupt_for_safety() -> void:
		wake_from_noise("danger")

	func can_follow_routine() -> bool:
		return can_follow

class FakeExecutor extends RefCounted:
	var actor: FakeActor
	var begun: Array[Dictionary] = []
	var cancelled: Array[String] = []
	var nudges: Array[Dictionary] = []
	var states: Dictionary = {}
	var accept: bool = true
	var bed: Variant = null
	var _journey_owner: String = ""
	var _journey_space: StringName = &""

	func begin_task_travel(_npc: Object, npc_id: String, space: StringName, point: Vector2,
			label: String, owner_task_id: String) -> bool:
		begun.append({"npc_id": npc_id, "space": space, "point": point, "label": label,
			"owner": owner_task_id})
		if not accept:
			return false
		_journey_owner = owner_task_id
		_journey_space = space
		states[owner_task_id] = &"traveling"
		return true

	func begin_task_nudge(_npc: Object, _npc_id: String, point: Vector2, owner_task_id: String) -> bool:
		nudges.append({"point": point, "owner": owner_task_id})
		_journey_owner = owner_task_id
		states[owner_task_id] = &"traveling"
		return true

	func finish_nudge() -> void:
		states[_journey_owner] = &"arrived"
		actor.global_position = nudges[nudges.size() - 1]["point"]

	func cancel_task_travel(_npc_id: String, owner_task_id: String) -> bool:
		if owner_task_id != _journey_owner:
			return false
		cancelled.append(owner_task_id)
		states.erase(owner_task_id)
		_journey_owner = ""
		return true

	func task_travel_state(_npc_id: String, owner_task_id: String) -> StringName:
		return states.get(owner_task_id, &"none") as StringName

	func bed_for(_npc_id: String) -> Variant:
		return bed

	func arrive() -> void:
		states[_journey_owner] = &"arrived"
		actor.world_space = _journey_space
		actor.global_position = begun[begun.size() - 1]["point"]

	func fail() -> void:
		states[_journey_owner] = &"failed"

	func owners() -> Array[String]:
		var result: Array[String] = []
		for entry: Dictionary in begun:
			result.append(entry["owner"] as String)
		return result

	func spaces() -> Array[StringName]:
		var result: Array[StringName] = []
		for entry: Dictionary in begun:
			result.append(entry["space"] as StringName)
		return result

class Rig extends RefCounted:
	var brain := NpcBrain.new()
	var actor := FakeActor.new()
	var executor := FakeExecutor.new()
	var mind := NpcMindState.new("holt_partner")
	var tuning := NpcBehaviorTuning.new()
	var finished: Array[Dictionary] = []

	func _init() -> void:
		executor.actor = actor
		brain.setup("holt_partner", mind, actor, executor, tuning, 7)
		brain.task_finished.connect(_on_finished)

	func _on_finished(task_id: String, status: String, reason: StringName) -> void:
		finished.append({"task_id": task_id, "status": status, "reason": reason})

	func start(task: NpcTask, minute: float) -> bool:
		brain.advance(minute, 0.0)
		return brain.request_task(task)

	func tick(minute: float) -> void:
		brain.advance(minute, 1.0)

	func phase() -> String:
		return brain.current_activity().get("phase", "") as String

	func last_finished() -> Dictionary:
		return finished[finished.size() - 1] if not finished.is_empty() else {}

	func dispose() -> void:
		brain.free()

static func routine_params(activity: String, space: String, until: float) -> Dictionary:
	return {"activity": activity, "place": "bakery", "label": "Heading to the bakery",
		"space": space, "point": [40.0, 24.0], "until_minute": until}

func _routine(rig: Rig, activity: String, space: String, until: float) -> NpcRoutineTask:
	return NpcRoutineTask.create(routine_params(activity, space, until), rig.tuning)

func test_travels_then_performs_until_the_deadline() -> void:
	var rig := Rig.new()
	var task: NpcRoutineTask = _routine(rig, "work", "bakery", 200.0)
	assert_true(rig.start(task, 100.0))
	assert_eq(task.priority, rig.tuning.routine_priority)
	assert_eq(rig.phase(), "travel")
	assert_eq(rig.executor.begun.size(), 1)
	assert_eq(rig.executor.begun[0]["space"], &"bakery")
	assert_eq(rig.executor.begun[0]["point"], Vector2(40.0, 24.0))
	assert_eq(rig.executor.begun[0]["label"], "Heading to the bakery")
	assert_eq(rig.executor.begun[0]["owner"], task.task_id)
	rig.tick(110.0)
	assert_eq(rig.phase(), "travel")
	rig.executor.arrive()
	rig.tick(120.0)
	assert_eq(rig.phase(), "perform")
	assert_eq(rig.executor.begun.size(), 1, "arrival does not travel again")
	assert_eq(rig.executor.states.get(task.task_id, &"none"), &"none", "journey released on arrival")
	rig.tick(199.0)
	assert_eq(rig.brain.task_state(task.task_id), "RUNNING")
	rig.tick(200.0)
	assert_eq(rig.brain.task_state(task.task_id), "")
	assert_eq(rig.last_finished()["status"], "COMPLETED")
	assert_eq(rig.last_finished()["reason"], &"until")
	rig.dispose()

func test_completion_cancels_a_journey_still_underway() -> void:
	var rig := Rig.new()
	var task: NpcRoutineTask = _routine(rig, "work", "bakery", 150.0)
	assert_true(rig.start(task, 100.0))
	rig.tick(150.0)
	assert_eq(rig.last_finished()["reason"], &"until")
	assert_eq(rig.executor.cancelled, [task.task_id] as Array[String])
	rig.dispose()

func test_rest_with_a_bed_sleeps_on_arrival_and_completion_leaves_the_sleeper() -> void:
	var rig := Rig.new()
	rig.executor.bed = Vector2(8.0, 9.0)
	assert_true(rig.start(_routine(rig, "rest", "home", 400.0), 100.0))
	assert_false(rig.actor.sleeping)
	rig.executor.arrive()
	rig.tick(110.0)
	assert_eq(rig.phase(), "sleep")
	assert_true(rig.actor.sleeping)
	assert_eq(rig.actor.log, ["sleep"] as Array[String])
	assert_eq(rig.actor.slept_at, Vector2(8.0, 9.0))
	rig.tick(399.0)
	assert_eq(rig.brain.controller.current.status, NpcTask.Status.RUNNING)
	rig.tick(400.0)
	assert_eq(rig.last_finished()["status"], "COMPLETED")
	assert_true(rig.actor.sleeping, "the next task decides about waking")
	assert_eq(rig.actor.log, ["sleep"] as Array[String])
	rig.dispose()

func test_rest_without_a_bed_is_performed_awake() -> void:
	var rig := Rig.new()
	assert_true(rig.start(_routine(rig, "rest", "tavern", 400.0), 100.0))
	rig.executor.arrive()
	rig.tick(110.0)
	assert_eq(rig.phase(), "perform")
	assert_false(rig.actor.sleeping)
	rig.dispose()

func test_sleeper_at_home_is_not_woken_for_rest_there() -> void:
	var rig := Rig.new()
	rig.actor.sleeping = true
	rig.actor.world_space = &"home"
	rig.executor.bed = Vector2(8.0, 9.0)
	assert_true(rig.start(_routine(rig, "rest", "home", 400.0), 100.0))
	assert_eq(rig.phase(), "sleep")
	assert_true(rig.actor.sleeping)
	assert_true(rig.actor.log.is_empty())
	assert_true(rig.executor.begun.is_empty())
	rig.tick(150.0)
	assert_true(rig.actor.sleeping)
	assert_true(rig.executor.begun.is_empty())
	rig.dispose()

func test_sleeper_is_woken_for_work_or_for_rest_elsewhere() -> void:
	var work := Rig.new()
	work.actor.sleeping = true
	work.actor.world_space = &"home"
	assert_true(work.start(_routine(work, "work", "home", 400.0), 100.0))
	assert_eq(work.actor.log, ["wake:schedule"] as Array[String], "work wakes even at home")
	assert_eq(work.phase(), "travel")
	work.dispose()
	var elsewhere := Rig.new()
	elsewhere.actor.sleeping = true
	elsewhere.actor.world_space = &"inn"
	assert_true(elsewhere.start(_routine(elsewhere, "rest", "home", 400.0), 100.0))
	assert_eq(elsewhere.actor.log, ["wake:schedule"] as Array[String])
	assert_eq(elsewhere.executor.begun.size(), 1)
	elsewhere.dispose()

func test_failed_journey_refused_start_and_timeout_are_unreachable() -> void:
	var failed := Rig.new()
	assert_true(failed.start(_routine(failed, "work", "bakery", 900.0), 100.0))
	failed.executor.fail()
	failed.tick(105.0)
	assert_eq(failed.last_finished()["status"], "FAILED")
	assert_eq(failed.last_finished()["reason"], &"unreachable")
	failed.dispose()
	var refused := Rig.new()
	refused.executor.accept = false
	assert_true(refused.start(_routine(refused, "work", "bakery", 900.0), 100.0))
	assert_eq(refused.last_finished()["reason"], &"unreachable")
	assert_true(refused.brain.current_activity().is_empty())
	refused.dispose()
	var slow := Rig.new()
	var task: NpcRoutineTask = _routine(slow, "work", "bakery", 900.0)
	assert_true(slow.start(task, 100.0))
	slow.tick(100.0 + slow.tuning.travel_timeout_minutes)
	assert_eq(slow.brain.task_state(task.task_id), "RUNNING", "the timeout is exclusive")
	slow.tick(101.0 + slow.tuning.travel_timeout_minutes)
	assert_eq(slow.last_finished()["reason"], &"unreachable")
	assert_eq(slow.executor.cancelled, [task.task_id] as Array[String])
	slow.dispose()

func test_a_lost_journey_is_reissued_under_the_same_owner() -> void:
	var rig := Rig.new()
	var task: NpcRoutineTask = _routine(rig, "work", "bakery", 900.0)
	assert_true(rig.start(task, 100.0))
	rig.executor.states.clear()
	rig.tick(110.0)
	assert_eq(rig.executor.owners(), [task.task_id, task.task_id] as Array[String])
	assert_eq(rig.brain.task_state(task.task_id), "RUNNING")
	rig.dispose()

func test_interrupt_policy() -> void:
	var rig := Rig.new()
	var task: NpcRoutineTask = _routine(rig, "work", "bakery", 900.0)
	assert_true(rig.start(task, 100.0))
	rig.brain.interrupt(NpcTask.Interrupt.SCHEDULE)
	assert_eq(rig.brain.task_state(task.task_id), "RUNNING")
	rig.brain.interrupt(NpcTask.Interrupt.DANGER)
	assert_eq(rig.last_finished()["status"], "CANCELLED")
	assert_eq(rig.last_finished()["reason"], &"danger")
	assert_eq(rig.executor.cancelled, [task.task_id] as Array[String])
	var other := Rig.new()
	var talker: NpcRoutineTask = _routine(other, "work", "bakery", 900.0)
	assert_true(other.start(talker, 100.0))
	other.brain.interrupt(NpcTask.Interrupt.CONVERSATION)
	assert_eq(other.brain.task_state(talker.task_id), "SUSPENDED")
	assert_eq(other.executor.cancelled, [talker.task_id] as Array[String])
	rig.dispose()
	other.dispose()

func test_resume_reroutes_from_the_current_position_unless_already_arrived() -> void:
	var rig := Rig.new()
	var task: NpcRoutineTask = _routine(rig, "work", "bakery", 900.0)
	assert_true(rig.start(task, 100.0))
	rig.brain.interrupt(NpcTask.Interrupt.HURT)
	assert_eq(rig.brain.task_state(task.task_id), "SUSPENDED")
	rig.actor.can_follow = false
	rig.tick(110.0)
	assert_eq(rig.brain.task_state(task.task_id), "SUSPENDED", "not while the body cannot move")
	rig.actor.can_follow = true
	rig.tick(120.0)
	assert_eq(rig.brain.task_state(task.task_id), "RUNNING")
	assert_eq(rig.executor.owners(), [task.task_id, task.task_id] as Array[String])
	rig.executor.arrive()
	rig.tick(130.0)
	assert_eq(rig.phase(), "perform")
	rig.brain.interrupt(NpcTask.Interrupt.CONVERSATION)
	rig.tick(140.0)
	assert_eq(rig.brain.task_state(task.task_id), "RUNNING")
	assert_eq(rig.executor.begun.size(), 2, "already in place, so no new journey")
	assert_eq(rig.phase(), "perform")
	rig.actor.world_space = &"street"
	rig.brain.interrupt(NpcTask.Interrupt.HURT)
	rig.tick(150.0)
	assert_eq(rig.executor.begun.size(), 3, "moved away meanwhile, so travel again")
	rig.dispose()

func test_a_routine_that_ran_out_while_suspended_is_dropped_on_resume() -> void:
	var rig := Rig.new()
	var task: NpcRoutineTask = _routine(rig, "work", "bakery", 200.0)
	assert_true(rig.start(task, 100.0))
	rig.brain.interrupt(NpcTask.Interrupt.HURT)
	rig.actor.can_follow = false
	rig.tick(250.0)
	rig.actor.can_follow = true
	rig.tick(251.0)
	assert_eq(rig.last_finished()["status"], "CANCELLED")
	assert_eq(rig.last_finished()["reason"], &"invalid_on_resume")
	assert_eq(rig.executor.begun.size(), 1)
	rig.dispose()

func test_invalid_params_are_rejected() -> void:
	var rig := Rig.new()
	var broken: Array[Dictionary] = []
	for key: String in ["activity", "place", "label", "space", "point", "until_minute"]:
		var missing := routine_params("work", "bakery", 200.0)
		missing.erase(key)
		broken.append(missing)
	var empty_activity := routine_params("", "bakery", 200.0)
	broken.append(empty_activity)
	var short_point := routine_params("work", "bakery", 200.0)
	short_point["point"] = [1.0]
	broken.append(short_point)
	var text_time := routine_params("work", "bakery", 200.0)
	text_time["until_minute"] = "noon"
	broken.append(text_time)
	for params: Dictionary in broken:
		assert_false(rig.start(NpcRoutineTask.create(params, rig.tuning), 100.0), str(params))
	assert_true(rig.executor.begun.is_empty())
	assert_true(rig.start(_routine(rig, "work", "bakery", 200.0), 100.0))
	rig.dispose()

func test_engagement_begins_only_after_arrival_and_ends_when_suspended() -> void:
	var rig := Rig.new()
	var task: NpcRoutineTask = _routine(rig, "work", "bakery", 900.0)
	assert_true(rig.start(task, 100.0))
	assert_eq(task.confirmed_engagement(), &"", "travelling is not working")
	rig.executor.arrive()
	assert_eq(task.confirmed_engagement(), &"", "an arrival nobody has observed yet")
	rig.tick(110.0)
	assert_eq(task.confirmed_engagement(), &"work")
	rig.brain.interrupt(NpcTask.Interrupt.CONVERSATION)
	assert_eq(task.confirmed_engagement(), &"", "suspended work earns nothing")
	rig.tick(120.0)
	assert_eq(task.confirmed_engagement(), &"work", "still in place on resume")
	rig.brain.interrupt(NpcTask.Interrupt.HURT)
	rig.actor.global_position = Vector2(400.0, 400.0)
	rig.tick(130.0)
	assert_eq(task.confirmed_engagement(), &"", "displaced residents travel back first")
	assert_eq(rig.phase(), "travel")
	rig.executor.arrive()
	rig.tick(140.0)
	assert_eq(task.confirmed_engagement(), &"work")
	rig.tick(900.0)
	assert_eq(task.confirmed_engagement(), &"", "a finished task confirms nothing")
	rig.dispose()

func test_sleeping_and_cancelled_tasks_are_not_engaged() -> void:
	var rig := Rig.new()
	rig.executor.bed = Vector2(8.0, 9.0)
	var task: NpcRoutineTask = _routine(rig, "rest", "home", 400.0)
	assert_true(rig.start(task, 100.0))
	rig.executor.arrive()
	rig.tick(110.0)
	assert_eq(rig.phase(), "sleep")
	assert_eq(task.confirmed_engagement(), &"")
	var other := Rig.new()
	var work: NpcRoutineTask = _routine(other, "work", "bakery", 900.0)
	assert_true(other.start(work, 100.0))
	other.executor.arrive()
	other.tick(110.0)
	other.brain.interrupt(NpcTask.Interrupt.DANGER)
	assert_eq(work.confirmed_engagement(), &"")
	rig.dispose()
	other.dispose()

func test_a_meal_taken_at_its_place_feeds_only_once_completed() -> void:
	var rig := Rig.new()
	rig.mind.needs.hunger = 0.8
	var task: NpcRoutineTask = _routine(rig, "meal", "bakery", 200.0)
	assert_true(rig.start(task, 100.0))
	rig.tick(150.0)
	assert_eq(rig.mind.needs.hunger, 0.8, "not eaten while walking")
	rig.executor.arrive()
	rig.tick(160.0)
	assert_eq(task.confirmed_engagement(), &"meal")
	assert_eq(rig.mind.needs.hunger, 0.8, "still eating")
	rig.tick(200.0)
	assert_eq(rig.last_finished()["reason"], &"until")
	assert_eq(rig.mind.needs.hunger, rig.tuning.meal_hunger)
	rig.dispose()

func test_a_meal_that_never_reached_its_place_does_not_feed() -> void:
	var rig := Rig.new()
	rig.mind.needs.hunger = 0.8
	var task: NpcRoutineTask = _routine(rig, "meal", "bakery", 200.0)
	assert_true(rig.start(task, 100.0))
	rig.tick(200.0)
	assert_eq(rig.last_finished()["reason"], &"until")
	assert_eq(rig.mind.needs.hunger, 0.8)
	rig.dispose()

func test_a_performing_resident_takes_idle_steps_near_the_spot_and_stays_engaged() -> void:
	var rig := Rig.new()
	var task: NpcRoutineTask = _routine(rig, "work", "bakery", 900.0)
	assert_true(rig.start(task, 100.0))
	rig.executor.arrive()
	rig.tick(101.0)
	assert_eq(rig.phase(), "perform")
	rig.tick(102.0)
	assert_true(rig.executor.nudges.is_empty(), "the first step is scheduled, not taken at once")
	rig.tick(102.0 + rig.tuning.fidget_max_minutes + 1.0)
	assert_eq(rig.executor.nudges.size(), 1)
	assert_eq(rig.executor.nudges[0]["owner"], task.task_id)
	assert_true((rig.executor.nudges[0]["point"] as Vector2).distance_to(Vector2(40.0, 24.0))
		<= rig.tuning.fidget_radius)
	assert_eq(task.confirmed_engagement(), &"work", "still at work while stepping")
	rig.executor.finish_nudge()
	rig.tick(200.0)
	assert_eq(rig.phase(), "perform")
	assert_false(task.progress.has("fidgeting"))
	assert_eq(rig.executor.states.get(task.task_id, &"none"), &"none", "the step journey is released")
	rig.tick(200.0 + rig.tuning.fidget_max_minutes + 1.0)
	assert_eq(rig.executor.nudges.size(), 2)
	rig.dispose()
