class_name NpcDirectedTravelTask
extends NpcTask

## Temporary adapter for systems that still direct movement themselves (watch, funerals).
## Travels to a point, then completes, or holds there until its owner ends the task.
## Params: owner, activity, label, space (Strings), point ([x, y]), priority (0..1),
## hold_on_arrival (bool).

const PHASE_TRAVEL: String = "travel"
const PHASE_HOLD: String = "hold"

func _init() -> void:
	kind = &"directed_travel"

static func create(task_params: Dictionary, id: String = "") -> NpcDirectedTravelTask:
	var task := NpcDirectedTravelTask.new()
	task.task_id = id
	task.params = task_params.duplicate(true)
	task.priority = float(task.params.get("priority", 0.0))
	return task

func restore_from(saved: Dictionary) -> bool:
	if not super.restore_from(saved):
		return false
	priority = float(params["priority"])
	return true

func _on_start(context: NpcTaskContext) -> NpcTaskResult:
	progress = {}
	if context.call_service(&"is_sleeping") == true:
		context.call_service(&"wake", ["called"])
	return _begin_travel(context)

func _on_advance(context: NpcTaskContext, _minutes: float) -> NpcTaskResult:
	if phase != PHASE_TRAVEL:
		return NpcTaskResult.running()
	var state: Variant = context.call_service(&"travel_state", [task_id])
	if state == &"arrived":
		_release_travel(context)
		if params["hold_on_arrival"] == true:
			phase = PHASE_HOLD
			return NpcTaskResult.running()
		return NpcTaskResult.completed(&"arrived")
	if state == &"failed":
		return _fail_unreachable(context)
	var tuning: NpcBehaviorTuning = context.call_service(&"tuning") as NpcBehaviorTuning
	var started: float = float(progress.get("travel_started", context.minute))
	if tuning != null and context.minute - started > tuning.travel_timeout_minutes:
		return _fail_unreachable(context)
	if state != &"traveling":
		return _issue_travel(context)
	return NpcTaskResult.running()

func _on_suspend(context: NpcTaskContext) -> void:
	_release_travel(context)

func _on_resume(context: NpcTaskContext) -> NpcTaskResult:
	if phase == PHASE_TRAVEL:
		return _begin_travel(context)
	return NpcTaskResult.running()

func _on_cancel(context: NpcTaskContext, _reason: StringName) -> void:
	_release_travel(context)

func _interrupt_response(interrupt: Interrupt) -> Response:
	match interrupt:
		Interrupt.HURT:
			return Response.SUSPEND
		Interrupt.CONVERSATION, Interrupt.SCHEDULE:
			return Response.CONTINUE
	return Response.CANCEL

func _revalidate(_context: NpcTaskContext) -> bool:
	priority = float(params["priority"])
	return true

func _validate_params(value: Dictionary) -> bool:
	for key: String in ["owner", "activity", "space"]:
		if not value.get(key) is String or (value[key] as String).is_empty():
			return false
	if not value.get("label") is String or not value.get("hold_on_arrival") is bool:
		return false
	var weight: Variant = value.get("priority")
	if not _is_number(weight) or float(weight) < 0.0 or float(weight) > 1.0:
		return false
	var point: Variant = value.get("point")
	if not point is Array or (point as Array).size() != 2:
		return false
	for axis: Variant in point as Array:
		if not _is_number(axis):
			return false
	return true

static func _is_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _begin_travel(context: NpcTaskContext) -> NpcTaskResult:
	phase = PHASE_TRAVEL
	progress["travel_started"] = context.minute
	return _issue_travel(context)

func _issue_travel(context: NpcTaskContext) -> NpcTaskResult:
	var point_data: Array = params["point"]
	var point := Vector2(float(point_data[0]), float(point_data[1]))
	var started: Variant = context.call_service(&"travel",
		[StringName(params["space"] as String), point, params["label"], task_id])
	if started != true:
		return NpcTaskResult.failed(&"unreachable")
	return NpcTaskResult.running()

func _fail_unreachable(context: NpcTaskContext) -> NpcTaskResult:
	_release_travel(context)
	return NpcTaskResult.failed(&"unreachable")

func _release_travel(context: NpcTaskContext) -> void:
	context.call_service(&"cancel_travel", [task_id])
