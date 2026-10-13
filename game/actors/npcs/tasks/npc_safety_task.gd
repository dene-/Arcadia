class_name NpcSafetyTask
extends NpcTask

## Reaction to possible danger. CAUTION stands still and assesses; SHELTER waits out the
## real-second orientation reflex, then flees to the refuge chosen by the caller (or stays put
## when none is given) until `until_minute`.
## Params: response ("CAUTION"|"SHELTER"), origin_id, label, refuge_space (Strings),
## refuge_point ([x, y] or []), until_minute (game minute).

const CAUTION: String = "CAUTION"
const SHELTER: String = "SHELTER"
const PHASE_ASSESS: String = "assess"
const PHASE_ORIENT: String = "orient"
const PHASE_FLEE: String = "flee"
const PHASE_SHELTER: String = "shelter"

func _init() -> void:
	kind = &"safety"

static func create(task_params: Dictionary, tuning: NpcBehaviorTuning,
		id: String = "") -> NpcSafetyTask:
	var task := NpcSafetyTask.new()
	task.task_id = id
	task.params = task_params.duplicate(true)
	task._apply_tuning(tuning)
	return task

func required_claims() -> Array[StringName]:
	if params.get("response") == SHELTER:
		return [&"locomotion", &"conversation"]
	return [&"locomotion"]

func _on_start(context: NpcTaskContext) -> NpcTaskResult:
	progress = {}
	_release_travel(context)
	if not _is_shelter():
		phase = PHASE_ASSESS
		return NpcTaskResult.running()
	return _orient(context)

func _on_advance(context: NpcTaskContext, _minutes: float) -> NpcTaskResult:
	var ended: NpcTaskResult = _ended(context)
	if ended != null:
		return ended
	match phase:
		PHASE_ORIENT:
			return _orient(context)
		PHASE_FLEE:
			return _advance_flee(context)
	return NpcTaskResult.running()

func _on_resume(context: NpcTaskContext) -> NpcTaskResult:
	var ended: NpcTaskResult = _ended(context)
	if ended != null:
		return ended
	match phase:
		PHASE_ORIENT:
			return _orient(context)
		PHASE_FLEE:
			return _begin_flee(context)
	return NpcTaskResult.running()

func _on_cancel(context: NpcTaskContext, _reason: StringName) -> void:
	_release_travel(context)

func _interrupt_response(interrupt: Interrupt) -> Response:
	if interrupt == Interrupt.DEATH or interrupt == Interrupt.REPLACED:
		return Response.CANCEL
	return Response.CONTINUE

func _revalidate(context: NpcTaskContext) -> bool:
	_apply_tuning(context.call_service(&"tuning") as NpcBehaviorTuning)
	return float(params["until_minute"]) >= context.minute

func _validate_params(value: Dictionary) -> bool:
	if not value.get("response") in [CAUTION, SHELTER]:
		return false
	for key: String in ["origin_id", "label", "refuge_space"]:
		if not value.get(key) is String:
			return false
	var point: Variant = value.get("refuge_point")
	if not point is Array or not (point as Array).size() in [0, 2]:
		return false
	for axis: Variant in point as Array:
		if not _is_number(axis):
			return false
	if (value["refuge_space"] as String).is_empty() != (point as Array).is_empty():
		return false
	return _is_number(value.get("until_minute"))

static func _is_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _apply_tuning(tuning: NpcBehaviorTuning) -> void:
	if tuning != null:
		priority = tuning.shelter_priority if _is_shelter() else tuning.caution_priority

func _is_shelter() -> bool:
	return params["response"] == SHELTER

func _has_refuge() -> bool:
	return not (params["refuge_space"] as String).is_empty()

# Null while the task is still needed.
func _ended(context: NpcTaskContext) -> NpcTaskResult:
	if context.minute >= float(params["until_minute"]):
		return _complete(context, &"until")
	if not _is_shelter():
		var tuning: NpcBehaviorTuning = context.call_service(&"tuning") as NpcBehaviorTuning
		if tuning != null and context.minute - started_minute >= tuning.caution_minutes:
			return _complete(context, &"caution_elapsed")
	return null

# The alert reflex runs in real seconds; the task only waits for it to finish. Danger then
# breaks whatever holds the actor in place (sleep or a conversation) before fleeing.
func _orient(context: NpcTaskContext) -> NpcTaskResult:
	if context.call_service(&"alert_active") == true:
		phase = PHASE_ORIENT
		return NpcTaskResult.running()
	context.call_service(&"wake_for_danger")
	if not _has_refuge():
		phase = PHASE_SHELTER
		return NpcTaskResult.running()
	return _begin_flee(context)

func _begin_flee(context: NpcTaskContext) -> NpcTaskResult:
	phase = PHASE_FLEE
	progress["travel_started"] = context.minute
	return _issue_travel(context)

# A refuge that cannot be reached leaves the resident sheltering where they stand.
func _issue_travel(context: NpcTaskContext) -> NpcTaskResult:
	var point_data: Array = params["refuge_point"]
	var point := Vector2(float(point_data[0]), float(point_data[1]))
	var started: Variant = context.call_service(&"travel",
		[StringName(params["refuge_space"] as String), point, params["label"], task_id])
	if started != true:
		return _shelter_here(context)
	return NpcTaskResult.running()

func _advance_flee(context: NpcTaskContext) -> NpcTaskResult:
	var state: Variant = context.call_service(&"travel_state", [task_id])
	if state == &"arrived" or state == &"failed":
		return _shelter_here(context)
	var tuning: NpcBehaviorTuning = context.call_service(&"tuning") as NpcBehaviorTuning
	var started: float = float(progress.get("travel_started", context.minute))
	if tuning != null and context.minute - started > tuning.travel_timeout_minutes:
		return _shelter_here(context)
	if state != &"traveling":
		return _issue_travel(context)
	return NpcTaskResult.running()

func _shelter_here(context: NpcTaskContext) -> NpcTaskResult:
	_release_travel(context)
	phase = PHASE_SHELTER
	return NpcTaskResult.running()

func _complete(context: NpcTaskContext, reason: StringName) -> NpcTaskResult:
	_release_travel(context)
	return NpcTaskResult.completed(reason)

func _release_travel(context: NpcTaskContext) -> void:
	context.call_service(&"cancel_travel", [task_id])
