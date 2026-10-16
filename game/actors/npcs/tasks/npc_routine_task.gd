class_name NpcRoutineTask
extends NpcTask

## Scheduled activity at a place: travel there, then perform it (or sleep, for "rest").
## Params: activity, place, label, space (Strings), point ([x, y]), until_minute (game minute).

const PHASE_TRAVEL: String = "travel"
const PHASE_PERFORM: String = "perform"
const PHASE_SLEEP: String = "sleep"
const REST: String = "rest"
const MEAL: StringName = &"meal"
## Distance from the scheduled point within which a resident counts as being at the activity.
const PRESENCE_RADIUS: float = 12.0
## An idle step is one navigation cell and may not take longer than this many game minutes.
const FIDGET_STEP: float = 8.0
const FIDGET_LIMIT_MINUTES: float = 3.0

# Runtime only: the activity the resident has confirmably begun at its place, else empty.
var _engagement: StringName = &""

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
		PHASE_PERFORM:
			return _advance_perform(context)
		PHASE_SLEEP:
			# Someone woke the sleeper (a noise, a visitor): the rest is over and the
			# resident replans instead of being put straight back to bed.
			if not _is_sleeping(context):
				return _complete(context, &"woke")
			return NpcTaskResult.running()
	return NpcTaskResult.running()

func _on_suspend(context: NpcTaskContext) -> void:
	_engagement = &""
	progress.erase("fidgeting")
	_release_travel(context)

## The activity this task has confirmably begun (arrived and in place), else &"" while
## travelling, sleeping, suspended or displaced.
func confirmed_engagement() -> StringName:
	return _engagement if status == Status.RUNNING and phase == PHASE_PERFORM else &""

# _revalidate already rejected an expired task, so resuming never completes immediately.
func _on_resume(context: NpcTaskContext) -> NpcTaskResult:
	_engagement = &""
	if phase == PHASE_TRAVEL or not _in_target_space(context):
		return _begin_travel(context)
	if phase == PHASE_SLEEP:
		return _advance_sleep(context)
	# Performing: engagement returns only once the body is still at the place.
	if not _at_place(context):
		return _begin_travel(context)
	_engagement = StringName(params["activity"] as String)
	return NpcTaskResult.running()

func _on_cancel(context: NpcTaskContext, _reason: StringName) -> void:
	_engagement = &""
	progress.erase("fidgeting")
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

# The body is within reach of the scheduled point; an actor without a position is nowhere.
func _at_place(context: NpcTaskContext) -> bool:
	var position: Variant = context.actor.get(&"global_position") if context.actor != null else null
	if not position is Vector2:
		return false
	var point_data: Array = params["point"]
	return (position as Vector2).distance_to(Vector2(float(point_data[0]), float(point_data[1]))) \
		<= PRESENCE_RADIUS

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

# While performing, a resident now and then takes a one-cell step near the scheduled spot
# instead of standing frozen for hours. The step stays inside `fidget_radius` of the spot (within
# the presence radius), so the activity stays confirmed; any interruption releases it like travel.
func _advance_perform(context: NpcTaskContext) -> NpcTaskResult:
	var tuning: NpcBehaviorTuning = context.call_service(&"tuning") as NpcBehaviorTuning
	if tuning == null or tuning.fidget_max_minutes <= 0.0 or _is_rest() \
			or not context.has_service(&"nudge"):
		return NpcTaskResult.running()
	if progress.get("fidgeting") == true:
		if context.call_service(&"travel_state", [task_id]) != &"traveling" \
				or context.minute - float(progress.get("fidget_began", context.minute)) > FIDGET_LIMIT_MINUTES:
			progress.erase("fidgeting")
			_release_travel(context)
			_schedule_fidget(context, tuning)
		return NpcTaskResult.running()
	if not progress.has("fidget_at"):
		_schedule_fidget(context, tuning)
	elif context.minute >= float(progress["fidget_at"]) \
			and context.call_service(&"can_move") == true:
		_start_fidget(context, tuning)
	return NpcTaskResult.running()

func _schedule_fidget(context: NpcTaskContext, tuning: NpcBehaviorTuning) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = hash("%s:fidget-gap:%d" % [task_id, int(progress.get("fidgets", 0))])
	progress["fidget_at"] = context.minute + random.randf_range(tuning.fidget_min_minutes,
		maxf(tuning.fidget_min_minutes, tuning.fidget_max_minutes))

# Tries the eight neighboring cells in a seeded order; the first one the town accepts is taken.
func _start_fidget(context: NpcTaskContext, tuning: NpcBehaviorTuning) -> void:
	var count: int = int(progress.get("fidgets", 0))
	progress["fidgets"] = count + 1
	var random := RandomNumberGenerator.new()
	random.seed = hash("%s:fidget:%d" % [task_id, count])
	var point_data: Array = params["point"]
	var spot := Vector2(float(point_data[0]), float(point_data[1]))
	var here_value: Variant = context.actor.get(&"global_position") if context.actor != null else null
	if not here_value is Vector2:
		_schedule_fidget(context, tuning)
		return
	var here: Vector2 = here_value
	var offset: int = random.randi_range(0, 7)
	for attempt: int in range(8):
		var direction: Vector2 = Vector2.RIGHT.rotated(TAU * float((offset + attempt) % 8) / 8.0).round()
		var target: Vector2 = here + direction * FIDGET_STEP
		if target.distance_to(spot) <= tuning.fidget_radius \
				and context.call_service(&"nudge", [target, task_id]) == true:
			progress["fidgeting"] = true
			progress["fidget_began"] = context.minute
			return
	_schedule_fidget(context, tuning)

func _arrive(context: NpcTaskContext) -> NpcTaskResult:
	_release_travel(context)
	if _is_rest() and context.call_service(&"bed") is Vector2:
		return _advance_sleep(context)
	phase = PHASE_PERFORM
	_engagement = StringName(params["activity"] as String)
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

# Completion never wakes a sleeper; the next task decides. A meal eaten at its place feeds.
func _complete(context: NpcTaskContext, reason: StringName = &"until") -> NpcTaskResult:
	if reason == &"until" and _engagement == MEAL and context.mind != null:
		var tuning: NpcBehaviorTuning = context.call_service(&"tuning") as NpcBehaviorTuning
		if tuning != null:
			context.mind.complete_meal(tuning)
	_engagement = &""
	_release_travel(context)
	return NpcTaskResult.completed(reason)

func _release_travel(context: NpcTaskContext) -> void:
	context.call_service(&"cancel_travel", [task_id])
