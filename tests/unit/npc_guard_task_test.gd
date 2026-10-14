extends "res://tests/test_case.gd"

class FakeAlert extends RefCounted:
	func active() -> bool:
		return false

class FakeActor extends RefCounted:
	var health: int = 3
	var world_space: StringName = &"outdoors"
	var global_position: Vector2 = Vector2.ZERO
	var alert_response := FakeAlert.new()
	var sleeping: bool = false
	var log: Array[String] = []
	var can_follow: bool = true

	func is_sleeping() -> bool:
		return sleeping

	func wake_from_noise(reason: String) -> void:
		sleeping = false
		log.append("wake:" + reason)

	func interrupt_for_safety() -> void:
		wake_from_noise("danger")

	func can_follow_routine() -> bool:
		return can_follow

class FakeExecutor extends RefCounted:
	var begun: Array[Dictionary] = []
	var states: Dictionary = {}
	var _journey_owner: String = ""

	func begin_task_travel(_npc: Object, _npc_id: String, space: StringName, point: Vector2,
			label: String, owner_task_id: String) -> bool:
		begun.append({"space": space, "point": point, "label": label, "owner": owner_task_id})
		_journey_owner = owner_task_id
		states[owner_task_id] = &"traveling"
		return true

	func cancel_task_travel(_npc_id: String, owner_task_id: String) -> bool:
		if owner_task_id != _journey_owner:
			return false
		states.erase(owner_task_id)
		_journey_owner = ""
		return true

	func task_travel_state(_npc_id: String, owner_task_id: String) -> StringName:
		return states.get(owner_task_id, &"none") as StringName

	func bed_for(_npc_id: String) -> Variant:
		return null

	func arrive() -> void:
		states[_journey_owner] = &"arrived"

	func last_point() -> Vector2:
		return begun[begun.size() - 1]["point"] as Vector2

# The watch's side of the contract: what this guard perceived and what its body does.
class FakeWatch extends RefCounted:
	var on_duty: bool = true
	var reports: Array[Dictionary] = []
	var leads: Array[Dictionary] = []
	var visible: Array[String] = []
	var engaged: String = ""
	var duties: Array[Array] = []
	var patrols: Array[int] = []

	func provide(brain: NpcBrain) -> void:
		brain.provide_service(&"guard_on_duty", func() -> bool: return on_duty)
		brain.provide_service(&"guard_patrol", _patrol)
		brain.provide_service(&"guard_reports", func() -> Array[Dictionary]: return reports)
		brain.provide_service(&"guard_leads", func() -> Array[Dictionary]: return leads)
		brain.provide_service(&"guard_sees", func(subject: String) -> bool: return subject in visible)
		brain.provide_service(&"guard_engage", _engage)
		brain.provide_service(&"guard_disengage", func() -> void: engaged = "")
		brain.provide_service(&"guard_duty", func(activity: String, label: String) -> void:
			duties.append([activity, label]))

	func _patrol(stop: int) -> Dictionary:
		var index: int = posmod(stop, 4)
		patrols.append(index)
		return {"stop": index, "space": "outdoors", "x": 100.0 * index, "y": 10.0,
			"label": "patrol stop %d" % index}

	func _engage(subject: String) -> bool:
		engaged = subject
		return true

	func activity() -> String:
		return duties[duties.size() - 1][0] if not duties.is_empty() else ""

class Rig extends RefCounted:
	var brain := NpcBrain.new()
	var actor := FakeActor.new()
	var executor := FakeExecutor.new()
	var mind: NpcMindState
	var tuning := NpcBehaviorTuning.new()
	var watch := FakeWatch.new()
	var finished: Array[Dictionary] = []

	func _init(saved_mind: NpcMindState = null) -> void:
		mind = saved_mind if saved_mind != null else NpcMindState.new("vale_guard")
		watch.provide(brain)
		brain.setup("vale_guard", mind, actor, executor, tuning, 7)
		brain.task_finished.connect(func(task_id: String, status: String, reason: StringName) -> void:
			finished.append({"task_id": task_id, "status": status, "reason": reason}))

	func start(stop: int, incident: bool, minute: float) -> NpcGuardTask:
		brain.advance(minute, 0.0)
		var task := NpcGuardTask.create(stop, "the watch", tuning, incident)
		return task if brain.request_task(task) else null

	func tick(minute: float) -> void:
		brain.advance(minute, 1.0)

	func phase() -> String:
		return brain.current_activity().get("phase", "") as String

	func report(status: String, minute: float) -> void:
		watch.reports = [{"guard": "vale_guard", "suspect": "player", "kind": "assault",
			"minute": minute, "assaults": 1, "status": status,
			"until": minute if status == "surrendered" else minute + 30.0}]

	func dispose() -> void:
		brain.free()

func test_patrol_continues_from_the_stop_after_the_origin_and_cycles() -> void:
	var rig := Rig.new()
	var task: NpcGuardTask = rig.start(2, false, 100.0)
	assert_true(task != null)
	assert_eq(task.priority, rig.tuning.routine_priority)
	assert_eq(rig.phase(), "patrol")
	assert_eq(rig.watch.patrols, [3] as Array[int])
	assert_eq(rig.executor.last_point(), Vector2(300.0, 10.0))
	assert_eq(rig.watch.duties, [["patrol", "patrol stop 3"]] as Array[Array])
	rig.executor.arrive()
	rig.tick(105.0)
	assert_eq(rig.watch.patrols, [3, 0] as Array[int])
	assert_eq(rig.executor.last_point(), Vector2(0.0, 10.0))
	assert_eq(rig.executor.begun.size(), 2)
	rig.dispose()

func test_an_off_duty_guard_ends_the_watch() -> void:
	var rig := Rig.new()
	var task: NpcGuardTask = rig.start(0, false, 100.0)
	rig.watch.on_duty = false
	rig.tick(101.0)
	assert_eq(rig.brain.task_state(task.task_id), "")
	assert_eq(rig.finished[rig.finished.size() - 1]["reason"], &"off_duty")
	assert_eq(rig.executor.states.get(task.task_id, &"none"), &"none", "travel released")
	rig.dispose()

func test_a_warning_heads_for_the_last_perceived_location_not_the_live_one() -> void:
	var rig := Rig.new()
	rig.mind.knowledge.record_sighting("player", "outdoors", Vector2(40.0, 50.0), 99.0, "seen")
	var task: NpcGuardTask = rig.start(0, false, 100.0)
	rig.report("warning", 100.0)
	rig.tick(100.0)
	assert_eq(rig.phase(), "warn")
	assert_eq(task.priority, rig.tuning.caution_priority)
	assert_eq(rig.watch.activity(), "investigate")
	assert_eq(rig.executor.last_point(), Vector2(40.0, 50.0))
	rig.watch.visible = ["player"]
	rig.tick(101.0)
	assert_eq(rig.phase(), "warn", "a warning never authorizes force")
	assert_eq(rig.watch.engaged, "")
	rig.dispose()

func test_combat_intervenes_only_on_sight_and_otherwise_pursues_the_known_location() -> void:
	var rig := Rig.new()
	rig.mind.knowledge.record_sighting("player", "outdoors", Vector2(-20.0, 5.0), 99.0, "seen")
	rig.report("combat", 100.0)
	rig.start(0, true, 100.0)
	assert_eq(rig.phase(), "pursue")
	assert_eq(rig.watch.engaged, "")
	assert_eq(rig.executor.last_point(), Vector2(-20.0, 5.0))
	rig.watch.visible = ["player"]
	rig.tick(101.0)
	assert_eq(rig.phase(), "intervene")
	assert_eq(rig.watch.engaged, "player")
	rig.watch.visible = []
	rig.tick(102.0)
	assert_eq(rig.phase(), "pursue")
	assert_eq(rig.watch.engaged, "", "an unseen suspect is not attacked")
	rig.dispose()

func test_surrender_stops_enforcement_and_the_patrol_resumes_at_its_stop() -> void:
	var rig := Rig.new()
	var task: NpcGuardTask = rig.start(1, false, 100.0)
	assert_eq(rig.executor.last_point(), Vector2(200.0, 10.0))
	rig.watch.visible = ["player"]
	rig.report("combat", 100.0)
	rig.tick(100.0)
	assert_eq(rig.watch.engaged, "player")
	rig.report("surrendered", 101.0)
	# A disturbance heard before the surrender of its subject is stale.
	rig.watch.leads = [{"subject": "player", "minute": 100.5, "until": 120.0}]
	rig.tick(101.0)
	assert_eq(rig.watch.engaged, "")
	assert_eq(rig.phase(), "surrendered")
	rig.tick(105.0)
	assert_eq(rig.phase(), "surrendered", "no restart while standing down")
	assert_eq(rig.watch.engaged, "")
	rig.tick(106.0)
	assert_eq(rig.phase(), "patrol")
	assert_eq(task.priority, rig.tuning.routine_priority)
	assert_eq(rig.watch.patrols, [2] as Array[int], "the interrupted stop is kept")
	assert_eq(rig.executor.last_point(), Vector2(200.0, 10.0))
	assert_eq(rig.watch.activity(), "patrol")
	rig.dispose()

func test_a_heard_lead_is_investigated_where_it_was_heard_without_force() -> void:
	var rig := Rig.new()
	rig.watch.visible = ["player"]
	rig.watch.leads = [{"subject": "disturbance", "minute": 100.0, "until": 112.0,
		"space": "outdoors", "x": 8.0, "y": 128.0}]
	rig.start(0, true, 100.0)
	assert_eq(rig.phase(), "investigate")
	assert_eq(rig.executor.last_point(), Vector2(8.0, 128.0))
	rig.executor.arrive()
	rig.tick(105.0)
	assert_eq(rig.phase(), "investigate", "holds at the scene")
	assert_eq(rig.executor.begun.size(), 1)
	assert_eq(rig.watch.engaged, "")
	rig.watch.leads = [{"subject": "player", "minute": 106.0, "until": 118.0}]
	rig.tick(106.0)
	assert_eq(rig.phase(), "investigate")
	assert_eq(rig.watch.engaged, "", "a lead about a named suspect is not evidence")
	rig.watch.leads = []
	rig.tick(107.0)
	assert_eq(rig.phase(), "patrol")
	rig.dispose()

func test_a_suspended_watch_releases_force_and_a_restored_patrol_resumes() -> void:
	var rig := Rig.new()
	var task: NpcGuardTask = rig.start(0, false, 100.0)
	rig.watch.visible = ["player"]
	rig.report("combat", 100.0)
	rig.tick(100.0)
	assert_eq(rig.watch.engaged, "player")
	var other := NpcSafetyTask.create({"response": "SHELTER", "origin_id": "noise:1", "until_minute": 10000.0,
		"label": "Taking cover", "refuge_space": "", "refuge_point": []}, rig.tuning)
	assert_true(rig.brain.request_task(other))
	assert_eq(rig.brain.task_state(task.task_id), "SUSPENDED")
	assert_eq(rig.watch.engaged, "", "a suspended guard drops its target")
	rig.brain.end_task(other.task_id)
	rig.watch.reports = []
	rig.tick(101.0)
	assert_eq(rig.brain.task_state(task.task_id), "RUNNING")
	assert_eq(rig.phase(), "patrol")
	assert_eq(rig.executor.last_point(), Vector2(100.0, 10.0))
	assert_true(rig.brain.save_checkpoint())
	var restored := Rig.new(rig.mind)
	assert_true(restored.brain.restore_checkpoint(102.0))
	assert_eq(restored.phase(), "patrol")
	assert_eq(restored.brain.current_activity()["task_id"], task.task_id)
	assert_eq(restored.watch.patrols, [] as Array[int], "continues to the saved stop")
	assert_eq(restored.executor.last_point(), Vector2(100.0, 10.0))
	assert_eq(restored.watch.activity(), "patrol")
	rig.dispose()
	restored.dispose()

func test_interrupt_policy_and_waking() -> void:
	var rig := Rig.new()
	rig.actor.sleeping = true
	var task: NpcGuardTask = rig.start(0, true, 100.0)
	assert_eq(rig.actor.log, ["wake:called"] as Array[String])
	for kind: NpcTask.Interrupt in [NpcTask.Interrupt.HURT, NpcTask.Interrupt.DANGER,
			NpcTask.Interrupt.CONVERSATION, NpcTask.Interrupt.SCHEDULE]:
		rig.brain.interrupt(kind)
		assert_eq(rig.brain.task_state(task.task_id), "RUNNING")
	rig.brain.interrupt(NpcTask.Interrupt.DEATH)
	assert_eq(rig.brain.task_state(task.task_id), "")
	rig.dispose()

func test_invalid_params_are_rejected() -> void:
	var rig := Rig.new()
	for params: Dictionary in [{"activity": "watch", "label": "", "stop": 0},
			{"activity": "patrol", "label": "the watch", "stop": 0},
			{"activity": "watch", "label": "the watch", "stop": -1},
			{"activity": "watch", "label": "the watch", "stop": 1.5}]:
		var task := NpcGuardTask.create(0, "the watch", rig.tuning, false)
		task.params = params
		assert_false(rig.brain.request_task(task), str(params))
	assert_true(rig.executor.begun.is_empty())
	rig.dispose()

func test_patrol_engagement_only_while_walking_the_route_and_never_when_suspended() -> void:
	var rig := Rig.new()
	var task: NpcGuardTask = rig.start(0, false, 100.0)
	assert_eq(task.confirmed_engagement(), &"patrol", "walking toward a stop is on patrol")
	rig.executor.arrive()
	rig.tick(105.0)
	assert_eq(task.confirmed_engagement(), &"patrol")
	var other := NpcSafetyTask.create({"response": "SHELTER", "origin_id": "noise:1", "until_minute": 10000.0,
		"label": "Taking cover", "refuge_space": "", "refuge_point": []}, rig.tuning)
	assert_true(rig.brain.request_task(other))
	assert_eq(task.confirmed_engagement(), &"", "a suspended watch earns nothing")
	rig.brain.end_task(other.task_id)
	rig.tick(106.0)
	assert_eq(task.confirmed_engagement(), &"patrol")
	rig.watch.visible = ["player"]
	rig.report("combat", 107.0)
	rig.tick(107.0)
	assert_eq(rig.phase(), "intervene")
	assert_eq(task.confirmed_engagement(), &"", "enforcement is not patrolling")
	rig.dispose()

func test_a_guard_unable_to_move_is_not_patrolling() -> void:
	var rig := Rig.new()
	rig.actor.can_follow = false
	var task: NpcGuardTask = rig.start(0, false, 100.0)
	assert_eq(task.confirmed_engagement(), &"")
	rig.dispose()
