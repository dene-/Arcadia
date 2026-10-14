class_name NpcGuardTask
extends NpcTask

## A guard's watch duty: patrol, then investigate, warn, intervene, pursue or stand down.
## Enforcement escalates only on the guard's own justice reports (`guard_reports`). A lead
## (`guard_leads`: something the guard heard) sends it to where the lead was perceived, or to
## the location its own knowledge holds for the lead's subject; never to a live position.
## A surrender ends enforcement; only a newer report of the guard's own restarts it.
## Once an incident is over the guard resumes the patrol from the stop it left; the task ends
## when no incident is open and the guard is off duty (`off_duty`).
## Params: activity ("watch"), label (String), stop (patrol stop the route continues after).
## Town services: guard_on_duty() -> bool; guard_patrol(stop) -> {stop, space, x, y, label};
## guard_reports() -> Array of own TownJustice reports; guard_leads() -> Array of
## {subject, minute, until, space?, x?, y?}; guard_sees(subject) -> bool;
## guard_engage(subject) -> bool; guard_disengage(); guard_duty(activity, label).

const PHASE_PATROL: String = "patrol"
const PHASE_INVESTIGATE: String = "investigate"
const PHASE_WARN: String = "warn"
const PHASE_INTERVENE: String = "intervene"
const PHASE_PURSUE: String = "pursue"
const PHASE_SURRENDERED: String = "surrendered"
const ACTIVITY: String = "watch"
## Minutes a guard stands down beside a suspect who surrendered before returning to duty.
const STAND_DOWN_MINUTES: float = 5.0

func _init() -> void:
	kind = &"guard"

## `incident` starts the duty at caution priority so it can displace ordinary activities.
static func create(stop: int, label: String, tuning: NpcBehaviorTuning, incident: bool,
		id: String = "") -> NpcGuardTask:
	var task := NpcGuardTask.new()
	task.task_id = id
	task.params = {"activity": ACTIVITY, "label": label, "stop": stop}
	task.priority = tuning.caution_priority if incident else tuning.routine_priority
	return task

func _on_start(context: NpcTaskContext) -> NpcTaskResult:
	progress = {}
	if context.call_service(&"is_sleeping") == true:
		context.call_service(&"wake", ["called"])
	return _decide(context)

func _on_advance(context: NpcTaskContext, _minutes: float) -> NpcTaskResult:
	return _decide(context)

func _on_suspend(context: NpcTaskContext) -> void:
	_release_travel(context)
	_disengage(context)

# Travel and the routine's activity label were lost while suspended or saved.
func _on_resume(context: NpcTaskContext) -> NpcTaskResult:
	progress.erase("target")
	progress.erase("duty")
	return _decide(context)

func _on_cancel(context: NpcTaskContext, _reason: StringName) -> void:
	_release_travel(context)
	_disengage(context)

func _interrupt_response(interrupt: Interrupt) -> Response:
	match interrupt:
		Interrupt.DEATH:
			return Response.CANCEL
		Interrupt.REPLACED:
			return Response.SUSPEND
	return Response.CONTINUE

func _revalidate(context: NpcTaskContext) -> bool:
	var tuning: NpcBehaviorTuning = context.call_service(&"tuning") as NpcBehaviorTuning
	if tuning == null:
		return false
	priority = tuning.routine_priority if phase == PHASE_PATROL else tuning.caution_priority
	return true

func _validate_params(value: Dictionary) -> bool:
	if value.get("activity") != ACTIVITY or not value.get("label") is String \
			or (value["label"] as String).is_empty():
		return false
	var stop: Variant = value.get("stop")
	return (stop is int or stop is float) and is_finite(float(stop)) and float(stop) >= 0.0 \
		and float(stop) == floorf(float(stop))

# --- Decisions ---

func _decide(context: NpcTaskContext) -> NpcTaskResult:
	var tuning: NpcBehaviorTuning = context.call_service(&"tuning") as NpcBehaviorTuning
	if tuning == null:
		return NpcTaskResult.failed(&"no_tuning")
	var reports: Array = _list(context.call_service(&"guard_reports"))
	var report: Dictionary = _active_report(reports, context.minute)
	if not report.is_empty():
		priority = tuning.caution_priority
		return _enforce(context, report)
	_disengage(context)
	var lead: Dictionary = _active_lead(context, reports)
	if not lead.is_empty():
		priority = tuning.caution_priority
		return _investigate(context, lead)
	if _standing_down(reports, context.minute):
		priority = tuning.caution_priority
		_set_phase(context, PHASE_SURRENDERED, PHASE_INVESTIGATE)
		_release_travel(context)
		return NpcTaskResult.running()
	if context.call_service(&"guard_on_duty") != true:
		return _finish(context, &"off_duty")
	priority = tuning.routine_priority
	return _patrol(context)

# Escalation consumes only the guard's own report; combat needs the suspect in sight.
func _enforce(context: NpcTaskContext, report: Dictionary) -> NpcTaskResult:
	var subject: String = report["suspect"] as String
	progress["subject"] = subject
	if report["status"] == "combat" and context.call_service(&"guard_sees", [subject]) == true:
		_set_phase(context, PHASE_INTERVENE, PHASE_INVESTIGATE)
		_release_travel(context)
		if context.call_service(&"guard_engage", [subject]) == true:
			progress["engaged"] = true
		return NpcTaskResult.running()
	_disengage(context)
	_set_phase(context, PHASE_PURSUE if report["status"] == "combat" else PHASE_WARN,
		PHASE_INVESTIGATE)
	_approach_known(context, subject)
	return NpcTaskResult.running()

func _investigate(context: NpcTaskContext, lead: Dictionary) -> NpcTaskResult:
	_set_phase(context, PHASE_INVESTIGATE, PHASE_INVESTIGATE)
	if lead.has_all(["space", "x", "y"]):
		_go(context, StringName(lead["space"] as String), Vector2(float(lead["x"]), float(lead["y"])))
	elif not _approach_known(context, lead["subject"] as String):
		_release_travel(context)
	return NpcTaskResult.running()

func _patrol(context: NpcTaskContext) -> NpcTaskResult:
	if not progress.has("patrol") and not _next_stop(context):
		return _finish(context, &"no_route")
	_set_phase(context, PHASE_PATROL, PHASE_PATROL)
	var state: StringName = _go(context, _stop_space(), _stop_point())
	if state == &"arrived" or state == &"failed":
		if not _next_stop(context):
			return _finish(context, &"no_route")
		_go(context, _stop_space(), _stop_point())
	return NpcTaskResult.running()

# The newest live warning or combat report the guard holds.
static func _active_report(reports: Array, minute: float) -> Dictionary:
	var best: Dictionary = {}
	for entry: Variant in reports:
		if not entry is Dictionary:
			continue
		var report: Dictionary = entry
		if not report.get("status") in ["warning", "combat"] or float(report.get("until", 0.0)) <= minute:
			continue
		if best.is_empty() or float(report["minute"]) > float(best["minute"]):
			best = report
	return best

# A lead that predates its subject's surrender is stale and is never acted on.
func _active_lead(context: NpcTaskContext, reports: Array) -> Dictionary:
	var best: Dictionary = {}
	for entry: Variant in _list(context.call_service(&"guard_leads")):
		if not entry is Dictionary or not entry.get("subject") is String:
			continue
		var lead: Dictionary = entry
		if float(lead.get("until", 0.0)) <= context.minute:
			continue
		var stale: bool = false
		for report: Variant in reports:
			if report is Dictionary and report.get("suspect") == lead["subject"] \
					and report.get("status") == "surrendered" \
					and float(report["minute"]) >= float(lead.get("minute", 0.0)):
				stale = true
		if not stale and (best.is_empty() or float(lead["minute"]) > float(best["minute"])):
			best = lead
	return best

static func _standing_down(reports: Array, minute: float) -> bool:
	for entry: Variant in reports:
		if entry is Dictionary and entry.get("status") == "surrendered" \
				and minute < float(entry["minute"]) + STAND_DOWN_MINUTES:
			return true
	return false

func _finish(context: NpcTaskContext, reason: StringName) -> NpcTaskResult:
	_release_travel(context)
	_disengage(context)
	return NpcTaskResult.completed(reason)

# --- Movement ---

# Heads for the newest location the guard's own knowledge holds; false when it knows none.
func _approach_known(context: NpcTaskContext, subject: String) -> bool:
	if context.mind == null:
		return false
	var known: Array[Dictionary] = context.mind.knowledge.known_locations(subject)
	if known.is_empty():
		return false
	var value: Dictionary = known[0]["value"]
	_go(context, StringName(value["space"] as String), Vector2(float(value["x"]), float(value["y"])))
	return true

# Returns &"traveling", &"arrived" (also once unreachable: the guard holds where it got to),
# &"failed" the first time travel fails, or &"waiting" while the guard cannot move.
func _go(context: NpcTaskContext, space: StringName, point: Vector2) -> StringName:
	var target: Array = [String(space), point.x, point.y]
	if progress.get("target") != target:
		_release_travel(context)
		progress["target"] = target
		progress["travel_started"] = context.minute
		progress["arrived"] = false
		return _issue(context, space, point)
	if progress.get("arrived") == true:
		return &"arrived"
	var state: Variant = context.call_service(&"travel_state", [task_id])
	if state == &"arrived":
		return _arrive(context, &"arrived")
	var tuning: NpcBehaviorTuning = context.call_service(&"tuning") as NpcBehaviorTuning
	if state == &"failed" or (tuning != null
			and context.minute - float(progress.get("travel_started", context.minute)) > tuning.travel_timeout_minutes):
		return _arrive(context, &"failed")
	if state != &"traveling":
		return _issue(context, space, point)
	return &"traveling"

func _issue(context: NpcTaskContext, space: StringName, point: Vector2) -> StringName:
	if context.call_service(&"can_move") != true:
		return &"waiting"
	var label: String = progress.get("duty_label", params["label"]) as String
	if context.call_service(&"travel", [space, point, label, task_id]) != true:
		return _arrive(context, &"failed")
	return &"traveling"

# The journey ends but the target stays, so the guard holds there until the target changes.
func _arrive(context: NpcTaskContext, state: StringName) -> StringName:
	context.call_service(&"cancel_travel", [task_id])
	progress["arrived"] = true
	return state

func _release_travel(context: NpcTaskContext) -> void:
	if progress.has("target"):
		context.call_service(&"cancel_travel", [task_id])
		progress.erase("target")

func _next_stop(context: NpcTaskContext) -> bool:
	var from: int = int(progress.get("stop", params["stop"]))
	var data: Variant = context.call_service(&"guard_patrol", [from + 1])
	if not data is Dictionary or not (data as Dictionary).has_all(["stop", "space", "x", "y", "label"]):
		return false
	progress["stop"] = int(data["stop"])
	progress["patrol"] = {"space": String(data["space"]), "x": float(data["x"]),
		"y": float(data["y"]), "label": String(data["label"])}
	progress.erase("duty")
	_set_phase(context, PHASE_PATROL, PHASE_PATROL)
	return true

func _stop_space() -> StringName:
	return StringName(progress["patrol"]["space"] as String)

func _stop_point() -> Vector2:
	return Vector2(float(progress["patrol"]["x"]), float(progress["patrol"]["y"]))

# --- Town effects ---

func _set_phase(context: NpcTaskContext, next: String, activity: String) -> void:
	if phase != next:
		_release_travel(context)
	phase = next
	var label: String = params["label"] as String
	if next == PHASE_PATROL and progress.has("patrol"):
		label = progress["patrol"]["label"] as String
	if progress.get("duty") != [activity, label]:
		progress["duty"] = [activity, label]
		progress["duty_label"] = label
		context.call_service(&"guard_duty", [activity, label])

func _disengage(context: NpcTaskContext) -> void:
	if progress.get("engaged") == true:
		progress.erase("engaged")
		context.call_service(&"guard_disengage")

static func _list(value: Variant) -> Array:
	return value if value is Array else []
