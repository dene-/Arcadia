class_name NpcRoutineTask
extends NpcTask

## Scheduled activity at a place: travel there, then perform it (or sleep, for "rest").
## Params: activity, place, label, space (Strings), point ([x, y]), until_minute (game minute).

const PHASE_TRAVEL: String = "travel"
const PHASE_PERFORM: String = "perform"
const PHASE_SLEEP: String = "sleep"
const REST: String = "rest"

func _init() -> void:
	kind = &"routine"

static func create(task_params: Dictionary, tuning: NpcBehaviorTuning,
		id: String = "") -> NpcRoutineTask:
	var task := NpcRoutineTask.new()
	task.task_id = id
	task.params = task_params.duplicate(true)
	task.priority = tuning.routine_priority
	return task

func _on_start(context: NpcTaskContext) -> NpcTaskResult:
	progress = {}
	if _is_sleeping(context):
		if _is_rest() and _in_target_space(context):
			phase = PHASE_SLEEP
			return NpcTaskResult.running()
		context.call_service(&"wake", ["schedule"])
	return _begin_travel(context)

func _on_advance(context: NpcTaskContext, _minutes: float) -> NpcTaskResult:
	if _expired(context):
		return _complete(context)
	match phase:
		PHASE_TRAVEL:
			return _advance_travel(context)
		PHASE_SLEEP:
			# Someone woke the sleeper (a noise, a visitor): the rest is over and the
			# resident replans instead of being put straight back to bed.
			if not _is_sleeping(context):
				return _complete(context, &"woke")
			return NpcTaskResult.running()
	return NpcTaskResult.running()

func _on_suspend(context: NpcTaskContext) -> void:
	_release_travel(context)

# _revalidate already rejected an expired task, so resuming never completes immediately.
func _on_resume(context: NpcTaskContext) -> NpcTaskResult:
	if phase == PHASE_TRAVEL or not _in_target_space(context):
		return _begin_travel(context)
	if phase == PHASE_SLEEP:
		return _advance_sleep(context)
	return NpcTaskResult.running()

func _on_cancel(context: NpcTaskContext, _reason: StringName) -> void:
	_release_travel(context)

func _interrupt_response(interrupt: Interrupt) -> Response:
	match interrupt:
		Interrupt.HURT, Interrupt.CONVERSATION, Interrupt.REPLACED:
			return Response.SUSPEND
		Interrupt.SCHEDULE:
			return Response.CONTINUE
	return Response.CANCEL

func _revalidate(context: NpcTaskContext) -> bool:
	var tuning: NpcBehaviorTuning = context.call_service(&"tuning") as NpcBehaviorTuning
	if tuning != null:
		priority = tuning.routine_priority
	return not _expired(context)

func _validate_params(value: Dictionary) -> bool:
	for key: String in ["activity", "space"]:
		if not value.get(key) is String or (value[key] as String).is_empty():
			return false
	for key: String in ["place", "label"]:
		if not value.get(key) is String:
			return false
	var point: Variant = value.get("point")
	if not point is Array or (point as Array).size() != 2:
		return false
	for axis: Variant in point as Array:
		if not _is_number(axis):
			return false
	return _is_number(value.get("until_minute"))

static func _is_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _is_rest() -> bool:
	return params["activity"] == REST

func _expired(context: NpcTaskContext) -> bool:
	return context.minute >= float(params["until_minute"])

func _target_space() -> StringName:
	return StringName(params["space"] as String)

func _is_sleeping(context: NpcTaskContext) -> bool:
	return context.call_service(&"is_sleeping") == true

func _in_target_space(context: NpcTaskContext) -> bool:
	var space: Variant = context.call_service(&"space")
	return (space is StringName or space is String) and StringName(space) == _target_space()

func _begin_travel(context: NpcTaskContext) -> NpcTaskResult:
	phase = PHASE_TRAVEL
	progress["travel_started"] = context.minute
	return _issue_travel(context)

func _issue_travel(context: NpcTaskContext) -> NpcTaskResult:
	var point_data: Array = params["point"]
	var point := Vector2(float(point_data[0]), float(point_data[1]))
	var started: Variant = context.call_service(&"travel",
		[_target_space(), point, params["label"], task_id])
	if started != true:
		return NpcTaskResult.failed(&"unreachable")
	return NpcTaskResult.running()

func _advance_travel(context: NpcTaskContext) -> NpcTaskResult:
	var state: Variant = context.call_service(&"travel_state", [task_id])
	if state == &"arrived":
		return _arrive(context)
	if state == &"failed":
		return _fail_unreachable(context)
	var tuning: NpcBehaviorTuning = context.call_service(&"tuning") as NpcBehaviorTuning
	var started: float = float(progress.get("travel_started", context.minute))
	if tuning != null and context.minute - started > tuning.travel_timeout_minutes:
		return _fail_unreachable(context)
	if state != &"traveling":
		return _issue_travel(context)
	return NpcTaskResult.running()

func _arrive(context: NpcTaskContext) -> NpcTaskResult:
	_release_travel(context)
	if _is_rest() and context.call_service(&"bed") is Vector2:
		return _advance_sleep(context)
	phase = PHASE_PERFORM
	return NpcTaskResult.running()

func _advance_sleep(context: NpcTaskContext) -> NpcTaskResult:
	phase = PHASE_SLEEP
	if _is_sleeping(context):
		return NpcTaskResult.running()
	var bed: Variant = context.call_service(&"bed")
	if bed is Vector2:
		context.call_service(&"sleep", [bed])
		return NpcTaskResult.running()
	return _begin_travel(context)

func _fail_unreachable(context: NpcTaskContext) -> NpcTaskResult:
	_release_travel(context)
	return NpcTaskResult.failed(&"unreachable")

# Completion never wakes a sleeper; the next task decides.
func _complete(context: NpcTaskContext, reason: StringName = &"until") -> NpcTaskResult:
	_release_travel(context)
	return NpcTaskResult.completed(reason)

func _release_travel(context: NpcTaskContext) -> void:
	context.call_service(&"cancel_travel", [task_id])
