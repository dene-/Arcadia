class_name NpcBrain
extends Node

## Owns one resident's task controller. Tasks reach the actor and the town only through the
## services handed out in their context, so the brain can run against test doubles.

signal task_finished(task_id: String, status: String, reason: StringName)

const CONVERSATION_CLAIM: StringName = &"conversation"
const RECENT_TRANSITIONS: int = 8

var controller := NpcTaskController.new()

var _npc_id: String = ""
var _mind: NpcMindState
var _actor: Object
var _executor: Object
var _tuning: NpcBehaviorTuning
var _seed: int = 0
var _minute: float = 0.0
var _dead: bool = false
var _services: Dictionary = {}

func setup(npc_id: String, mind: NpcMindState, actor: Object, executor: Object,
		tuning: NpcBehaviorTuning, seed_value: int) -> void:
	_npc_id = npc_id
	_mind = mind
	_actor = actor
	_executor = executor
	_tuning = tuning
	_seed = seed_value
	controller.register_kind(&"routine", NpcRoutineTask)
	controller.register_kind(&"safety", NpcSafetyTask)
	controller.register_kind(&"directed_travel", NpcDirectedTravelTask)
	controller.register_kind(&"hold", NpcHoldTask)
	if not controller.transitioned.is_connected(_on_transitioned):
		controller.transitioned.connect(_on_transitioned)
	_services = {
		&"travel": _travel, &"cancel_travel": _cancel_travel, &"travel_state": _travel_state,
		&"bed": _bed, &"space": _space, &"sleep": _sleep, &"wake": _wake,
		&"wake_for_danger": _wake_for_danger, &"is_sleeping": _is_sleeping,
		&"alert_active": _alert_active, &"can_move": _can_move, &"tuning": _get_tuning,
	}

# `minute` is the world minute; it also timestamps later requests until the next advance.
func advance(minute: float, minutes: float) -> void:
	_minute = minute
	if _dead or not _has_actor():
		return
	if _health() <= 0:
		_die()
		return
	var context: NpcTaskContext = _context()
	controller.advance(context, minutes)
	if controller.current == null and controller.suspended != null and _can_move():
		controller.resume(context)

func request_task(task: NpcTask) -> bool:
	if task == null or _dead or not _has_actor():
		return false
	if task.task_id.is_empty():
		task.task_id = "%s:%s:%d" % [task.kind, _npc_id, _mind.next_decision()]
	return controller.start(task, _context())

# For the owner of an adapter task to end it; stale or unknown ids change nothing.
func end_task(task_id: String, reason: StringName = &"released") -> bool:
	if _dead or not _has_actor():
		return false
	return controller.cancel(task_id, reason, _context())

func task_state(task_id: String) -> String:
	if controller.current != null and controller.current.task_id == task_id:
		return NpcTask.status_name(controller.current.status)
	if controller.suspended != null and controller.suspended.task_id == task_id:
		return NpcTask.status_name(controller.suspended.status)
	return ""

func interrupt(kind: NpcTask.Interrupt) -> void:
	if _dead or not _has_actor():
		return
	if kind == NpcTask.Interrupt.DEATH:
		_die()
		return
	controller.interrupt(kind, _context())

# Urgent duties (caution and above) refuse to be pulled into a conversation.
func request_conversation(session_id: String) -> bool:
	if _dead or session_id.is_empty():
		return false
	if controller.current != null and controller.current.priority >= _tuning.caution_priority:
		return false
	return controller.acquire_claim(CONVERSATION_CLAIM, _session_owner(session_id))

func finish_conversation(session_id: String) -> void:
	controller.release_claim(CONVERSATION_CLAIM, _session_owner(session_id))

func current_activity() -> Dictionary:
	var task: NpcTask = controller.current
	if task == null:
		return {}
	return {"task_id": task.task_id, "kind": String(task.kind), "phase": task.phase,
		"activity": _activity_of(task), "label": task.params.get("label", ""),
		"status": NpcTask.status_name(task.status)}

func save_checkpoint() -> bool:
	return _mind.set_task_checkpoint(controller.checkpoint())

# `minute` (when not negative) replaces the brain's clock so revalidation sees the loaded time.
func restore_checkpoint(minute: float = -1.0) -> bool:
	if minute >= 0.0:
		_minute = minute
	if _dead or not _has_actor():
		return false
	return controller.restore(_mind.task_checkpoint(), _context())

func debug_snapshot() -> Dictionary:
	var entries: Array[Dictionary] = controller.transitions()
	return {
		"npc_id": _npc_id,
		"dead": _dead,
		"current": controller.current.checkpoint() if controller.current != null else {},
		"suspended": controller.suspended.checkpoint() if controller.suspended != null else {},
		"claims": {"locomotion": controller.claim_owner(&"locomotion"),
			"conversation": controller.claim_owner(CONVERSATION_CLAIM)},
		"transitions": entries.slice(maxi(0, entries.size() - RECENT_TRANSITIONS)),
	}

func _context() -> NpcTaskContext:
	var context := NpcTaskContext.new()
	context.npc_id = _npc_id
	context.minute = _minute
	context.mind = _mind
	context.actor = _actor
	context.services = _services
	context.random = NpcRoutinePlan.random_for(_seed,
		"%s:brain:%d" % [_npc_id, _mind.decision_sequence])
	return context

func _die() -> void:
	_dead = true
	controller.interrupt(NpcTask.Interrupt.DEATH, _context())

func _on_transitioned(entry: Dictionary) -> void:
	var status: String = entry["to"] as String
	if status in [NpcTask.status_name(NpcTask.Status.COMPLETED),
			NpcTask.status_name(NpcTask.Status.CANCELLED),
			NpcTask.status_name(NpcTask.Status.FAILED)]:
		task_finished.emit(entry["task_id"] as String, status, StringName(entry["reason"] as String))

func _session_owner(session_id: String) -> String:
	return "session:" + session_id

func _activity_of(task: NpcTask) -> String:
	var activity: Variant = task.params.get("activity")
	if activity is String:
		return activity
	match task.kind:
		&"safety":
			return (task.params.get("response", "") as String).to_lower()
		&"hold":
			return task.params.get("reason", "") as String
	return ""

func _has_actor() -> bool:
	return _actor != null and is_instance_valid(_actor)

func _health() -> int:
	return int(_actor.get(&"health"))

# --- Services ---

func _travel(space: StringName, point: Vector2, label: String, owner_task_id: String) -> bool:
	return _executor.call(&"begin_task_travel", _actor, _npc_id, space, point, label,
		owner_task_id) == true

func _cancel_travel(owner_task_id: String) -> bool:
	return _executor.call(&"cancel_task_travel", _npc_id, owner_task_id) == true

func _travel_state(owner_task_id: String) -> StringName:
	var state: Variant = _executor.call(&"task_travel_state", _npc_id, owner_task_id)
	if state is StringName or state is String:
		return StringName(state)
	return &"none"

func _bed() -> Variant:
	var bed: Variant = _executor.call(&"bed_for", _npc_id)
	return bed if bed is Vector2 else null

func _space() -> StringName:
	var space: Variant = _actor.get(&"world_space")
	if space is StringName or space is String:
		return StringName(space)
	return &""

func _sleep(center: Vector2) -> void:
	_actor.call(&"sleep_at", center)

func _wake(reason: String) -> void:
	_actor.call(&"wake_from_noise", reason)

func _wake_for_danger() -> void:
	_actor.call(&"interrupt_for_safety")

func _is_sleeping() -> bool:
	return _actor.call(&"is_sleeping") == true

func _alert_active() -> bool:
	var alert: Object = _actor.get(&"alert_response") as Object
	return alert != null and alert.call(&"active") == true

func _can_move() -> bool:
	return _actor.call(&"can_follow_routine") == true

func _get_tuning() -> NpcBehaviorTuning:
	return _tuning
