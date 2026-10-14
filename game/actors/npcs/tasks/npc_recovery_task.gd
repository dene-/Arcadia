class_name NpcRecoveryTask
extends NpcTask

## Reporting and recovering a body. Every lifecycle change goes through the TownDeaths intent
## API; arrival comes from executor travel and every wait is measured in world minutes.
## Params: role ("witness" | "guard"), body (deceased id), activity, label (Strings).
## Town services (TownFunerals): deaths, guard_roster, visible_guards, assess_scene,
## cemetery_plot, recovery_event. A missing service only pauses the task.

const WITNESS: String = "witness"
const GUARD: String = "guard"

const PHASE_ABSORB: String = "absorb"
const PHASE_SEEK_HELP: String = "seek_help"
const PHASE_REPORT: String = "report"
const PHASE_DEFERRED: String = "deferred"
const PHASE_ACKNOWLEDGE: String = "acknowledge"
const PHASE_REACH_BODY: String = "reach_body"
const PHASE_ASSESS: String = "assess"
const PHASE_PREPARE: String = "prepare"
const PHASE_CARRY: String = "carry"
const PHASE_REACH_CEMETERY: String = "reach_cemetery"
const PHASE_BURY: String = "bury"

## A moment to take in the discovery before setting off for help.
const ABSORB_MINUTES: float = 4.0
## Covering and readying the body before lifting it.
const PREPARE_MINUTES: float = 6.0
## Lifting the shrouded body before setting off.
const LIFT_MINUTES: float = 1.0
const BURY_MINUTES: float = 12.0
## Distance at which a witness can speak to a guard.
const REPORT_DISTANCE: float = 28.0
## A visible guard who moved further than this from the approach point is re-approached.
const REACQUIRE_DISTANCE: float = 16.0
## Places closer than this are one search stop.
const SAME_STOP_DISTANCE: float = 24.0
const MAX_STOPS: int = 16
## Where a carrier stands relative to the body or plot it works at.
const STAND_OFFSET := Vector2(0, 12)

func _init() -> void:
	kind = &"recovery"

static func create(task_params: Dictionary, tuning: NpcBehaviorTuning,
		id: String = "") -> NpcRecoveryTask:
	var task := NpcRecoveryTask.new()
	task.task_id = id
	task.params = task_params.duplicate(true)
	task._apply_tuning(tuning)
	return task

func body_id() -> String:
	return params["body"] as String

func is_witness() -> bool:
	return params["role"] == WITNESS

# --- Lifecycle ---

func _on_start(context: NpcTaskContext) -> NpcTaskResult:
	progress = {}
	# Both duties walk somewhere; a routine resumed in the same tick may have put the resident to bed.
	_wake(context)
	if is_witness():
		_enter(context, PHASE_ABSORB)
		context.call_service(&"cancel_travel", [task_id])
		return NpcTaskResult.running()
	_enter(context, PHASE_ACKNOWLEDGE)
	return _advance_guard(context)

func _on_advance(context: NpcTaskContext, _minutes: float) -> NpcTaskResult:
	return _advance_witness(context) if is_witness() else _advance_guard(context)

func _on_suspend(context: NpcTaskContext) -> void:
	_release_travel(context)
	if not is_witness():
		_let_go(context)

func _on_resume(context: NpcTaskContext) -> NpcTaskResult:
	progress.erase("travel_started")
	_wake(context)
	if is_witness():
		if phase == PHASE_REPORT:
			_enter(context, PHASE_SEEK_HELP)
		return _advance_witness(context)
	_enter(context, _guard_phase_for(context))
	return _advance_guard(context)

func _on_cancel(context: NpcTaskContext, reason: StringName) -> void:
	_release_travel(context)
	if is_witness():
		if reason == &"death":
			_deaths_call(context, &"release_assignment", [body_id(), context.npc_id, context.minute])
		return
	if reason == &"death":
		# A dead carrier leaves the body where it was last carried.
		_deaths_call(context, &"release_assignment", [body_id(), context.npc_id, context.minute])
	else:
		_let_go(context)

func _interrupt_response(interrupt: Interrupt) -> Response:
	if interrupt == Interrupt.DEATH:
		return Response.CANCEL
	if interrupt == Interrupt.SCHEDULE:
		return Response.CONTINUE
	return Response.SUSPEND

func _revalidate(context: NpcTaskContext) -> bool:
	_apply_tuning(context.call_service(&"tuning") as NpcBehaviorTuning)
	var entry: Dictionary = _snapshot(context)
	if entry.is_empty():
		return false
	if is_witness():
		return entry["stage"] == "discovered" and entry["reporter"] == context.npc_id
	var guard: String = entry["guard"]
	match entry["stage"]:
		"reported":
			return guard.is_empty() or guard == context.npc_id
		"recovering", "carried":
			return guard == context.npc_id
	return false

func _validate_params(value: Dictionary) -> bool:
	if not value.get("role") in [WITNESS, GUARD]:
		return false
	for key: String in ["body", "activity", "label"]:
		if not value.get(key) is String or (value[key] as String).is_empty():
			return false
	return true

# --- Witness ---

func _advance_witness(context: NpcTaskContext) -> NpcTaskResult:
	if phase == PHASE_DEFERRED:
		return NpcTaskResult.blocked(&"deferred")
	var entry: Dictionary = _snapshot(context)
	if entry.is_empty():
		return NpcTaskResult.running() if _deaths(context) == null else NpcTaskResult.failed(&"body_missing")
	if entry["stage"] != "discovered":
		return NpcTaskResult.completed(&"already_reported")
	if entry["reporter"] != context.npc_id:
		return NpcTaskResult.failed(&"not_reporter")
	match phase:
		PHASE_ABSORB:
			if context.minute - float(progress.get("phase_started", context.minute)) < ABSORB_MINUTES:
				return NpcTaskResult.running()
			_enter(context, PHASE_SEEK_HELP)
			return _seek_help(context)
		PHASE_SEEK_HELP:
			return _seek_help(context)
		PHASE_REPORT:
			return _approach_guard(context)
	return NpcTaskResult.running()

func _seek_help(context: NpcTaskContext) -> NpcTaskResult:
	var seen: Dictionary = _nearest_visible_guard(context)
	if not seen.is_empty():
		_release_travel(context)
		_enter(context, PHASE_REPORT)
		progress["guard"] = seen["id"]
		return _approach_guard(context)
	if not progress.has("stops"):
		progress["stops"] = _search_stops(context)
		progress["stop"] = 0
	var stops: Array = progress["stops"]
	var index: int = int(progress["stop"])
	if index >= stops.size():
		_release_travel(context)
		_enter(context, PHASE_DEFERRED)
		return NpcTaskResult.blocked(&"deferred")
	var state: Variant = context.call_service(&"travel_state", [task_id])
	if state == &"arrived" or state == &"failed" or _travel_timed_out(context):
		_release_travel(context)
		progress["stop"] = index + 1
		return _seek_help(context)
	if state != &"traveling":
		var stop: Array = stops[index]
		return _travel_to(context, StringName(stop[0] as String), Vector2(float(stop[1]), float(stop[2])))
	return NpcTaskResult.running()

# Approaches the guard where the witness perceives it; losing sight resumes the search.
func _approach_guard(context: NpcTaskContext) -> NpcTaskResult:
	var guard_id: String = progress.get("guard", "")
	var seen: Dictionary = _visible_guard(context, guard_id)
	if seen.is_empty():
		_release_travel(context)
		_enter(context, PHASE_SEEK_HELP)
		return NpcTaskResult.running()
	var space: StringName = StringName(seen["space"])
	var at: Vector2 = seen["position"]
	if _space(context) == space and _position(context).distance_to(at) < REPORT_DISTANCE:
		_release_travel(context)
		var result: Variant = _deaths_call(context, &"acknowledge_report",
			[body_id(), guard_id, context.npc_id, context.minute])
		if result != TownDeaths.OK_RESULT:
			return NpcTaskResult.running() if result == null else NpcTaskResult.failed(StringName(result))
		_ask(context, &"recovery_event", [&"reported", body_id(), guard_id])
		return NpcTaskResult.completed(&"reported")
	var target: Variant = progress.get("target")
	var state: Variant = context.call_service(&"travel_state", [task_id])
	if state == &"traveling" and target is Array and String(target[0]) == String(space) \
			and Vector2(float(target[1]), float(target[2])).distance_to(at) <= REACQUIRE_DISTANCE:
		return NpcTaskResult.running()
	if state == &"failed":
		_release_travel(context)
		_enter(context, PHASE_SEEK_HELP)
		return NpcTaskResult.running()
	progress["target"] = [String(space), at.x, at.y]
	return _travel_to(context, space, at + STAND_OFFSET)

# Search order from the witness's own knowledge: each guard's last-known location (most recent
# first, never a guard known to be dead), then known help places. Never a live position.
func _search_stops(context: NpcTaskContext) -> Array:
	var stops: Array = []
	var knowledge: NpcKnowledge = context.mind.knowledge if context.mind != null else null
	if knowledge == null:
		return stops
	var sightings: Array[Dictionary] = []
	var roster: Variant = _ask(context, &"guard_roster")
	if roster is Array:
		for guard_id: Variant in roster:
			if not guard_id is String or guard_id == context.npc_id or _known_dead(knowledge, guard_id):
				continue
			var locations: Array[Dictionary] = knowledge.known_locations(guard_id)
			if not locations.is_empty():
				sightings.append(locations[0])
	sightings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["observed_minute"]) > float(b["observed_minute"]))
	for fact: Dictionary in sightings:
		_add_stop(stops, fact["value"])
	for fact: Dictionary in knowledge.known_help_places():
		_add_stop(stops, fact["value"])
	return stops

static func _known_dead(knowledge: NpcKnowledge, person_id: String) -> bool:
	for fact: Dictionary in knowledge.current(person_id, "status"):
		if fact["value"] == "dead":
			return true
	return false

static func _add_stop(stops: Array, value: Variant) -> void:
	if not value is Dictionary or stops.size() >= MAX_STOPS:
		return
	var space: String = String(value.get("space", ""))
	var point := Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	if space.is_empty():
		return
	for stop: Array in stops:
		if stop[0] == space and Vector2(float(stop[1]), float(stop[2])).distance_to(point) < SAME_STOP_DISTANCE:
			return
	stops.append([space, point.x, point.y])

func _nearest_visible_guard(context: NpcTaskContext) -> Dictionary:
	var best: Dictionary = {}
	var distance: float = INF
	var here: Vector2 = _position(context)
	for seen: Dictionary in _visible_guards(context):
		var next: float = here.distance_to(seen["position"])
		if next < distance:
			distance = next
			best = seen
	return best

func _visible_guard(context: NpcTaskContext, guard_id: String) -> Dictionary:
	for seen: Dictionary in _visible_guards(context):
		if seen["id"] == guard_id:
			return seen
	return {}

func _visible_guards(context: NpcTaskContext) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Variant = _ask(context, &"visible_guards")
	if seen is Array:
		for entry: Variant in seen:
			if entry is Dictionary and entry.get("id") is String and entry.get("position") is Vector2 \
					and entry.get("id") != context.npc_id:
				result.append(entry)
	return result

# --- Guard ---

func _advance_guard(context: NpcTaskContext) -> NpcTaskResult:
	var entry: Dictionary = _snapshot(context)
	if entry.is_empty():
		return NpcTaskResult.running() if _deaths(context) == null else NpcTaskResult.failed(&"body_missing")
	if entry["stage"] == "buried":
		return NpcTaskResult.completed(&"already_buried")
	match phase:
		PHASE_ACKNOWLEDGE:
			return _acknowledge(context, entry)
		PHASE_REACH_BODY:
			return _reach_body(context, entry)
		PHASE_ASSESS, PHASE_PREPARE:
			return _assess(context, entry)
		PHASE_CARRY, PHASE_REACH_CEMETERY, PHASE_BURY:
			return _carry(context, entry)
	return NpcTaskResult.running()

func _acknowledge(context: NpcTaskContext, entry: Dictionary) -> NpcTaskResult:
	if entry["stage"] in ["recovering", "carried"] and entry["guard"] == context.npc_id:
		_enter(context, _guard_phase_for(context))
		return _advance_guard(context)
	# After danger at the scene, the body is claimed again only once that danger has passed.
	if progress.get("unsafe", false):
		if _ask(context, &"assess_scene", [StringName(entry["space"] as String), _entry_point(entry)]) \
				== &"danger":
			return NpcTaskResult.blocked(&"danger")
		progress.erase("unsafe")
	var result: Variant = _deaths_call(context, &"begin_recovery", [body_id(), context.npc_id, context.minute])
	if result == TownDeaths.ALREADY_CLAIMED:
		return NpcTaskResult.completed(&"claimed_by_other")
	if result != TownDeaths.OK_RESULT:
		return NpcTaskResult.blocked(StringName(result) if result != null else &"no_deaths")
	_ask(context, &"recovery_event", [&"recovering", body_id(), context.npc_id])
	_enter(context, PHASE_REACH_BODY)
	return _reach_body(context, _snapshot(context))

func _reach_body(context: NpcTaskContext, entry: Dictionary) -> NpcTaskResult:
	if entry["stage"] != "recovering" or entry["guard"] != context.npc_id:
		return _lost_claim(context)
	var space := StringName(entry["space"] as String)
	var point: Vector2 = _entry_point(entry)
	var state: Variant = context.call_service(&"travel_state", [task_id])
	if state == &"arrived" or _at(context, space, point):
		_release_travel(context)
		_enter(context, PHASE_ASSESS)
		return _assess(context, entry)
	if state == &"failed" or _travel_timed_out(context):
		_release_travel(context)
		_deaths_call(context, &"interrupt_recovery", [body_id(), context.npc_id, context.minute])
		return NpcTaskResult.failed(&"unreachable")
	if state != &"traveling":
		return _travel_to(context, space, point + STAND_OFFSET)
	return NpcTaskResult.running()

# The scene is checked on arrival and throughout preparation; danger hands the guard to its
# enforcement duty and releases the claimed body.
func _assess(context: NpcTaskContext, entry: Dictionary) -> NpcTaskResult:
	if entry["stage"] != "recovering" or entry["guard"] != context.npc_id:
		return _lost_claim(context)
	var space := StringName(entry["space"] as String)
	var point: Vector2 = _entry_point(entry)
	if not _at(context, space, point):
		_enter(context, PHASE_REACH_BODY)
		return NpcTaskResult.running()
	var scene: Variant = _ask(context, &"assess_scene", [space, point])
	if scene == &"danger":
		_deaths_call(context, &"interrupt_recovery", [body_id(), context.npc_id, context.minute])
		_enter(context, PHASE_ACKNOWLEDGE)
		progress["unsafe"] = true
		return NpcTaskResult.blocked(&"danger")
	if scene != &"clear":
		_enter(context, PHASE_ASSESS)
		return NpcTaskResult.blocked(&"scene_unclear")
	if phase == PHASE_ASSESS:
		_enter(context, PHASE_PREPARE)
		_ask(context, &"recovery_event", [&"preparing", body_id(), context.npc_id])
		return NpcTaskResult.running()
	if context.minute - float(progress["phase_started"]) < PREPARE_MINUTES:
		return NpcTaskResult.running()
	var result: Variant = _deaths_call(context, &"pick_up",
		[body_id(), context.npc_id, String(_space(context)), _position(context), context.minute])
	if result == TownDeaths.NOT_AT_BODY:
		_enter(context, PHASE_REACH_BODY)
		return NpcTaskResult.running()
	if result != TownDeaths.OK_RESULT:
		return _lost_claim(context)
	_ask(context, &"recovery_event", [&"picked_up", body_id(), context.npc_id])
	_enter(context, PHASE_CARRY)
	return NpcTaskResult.running()

func _carry(context: NpcTaskContext, entry: Dictionary) -> NpcTaskResult:
	if entry["stage"] != "carried" or entry["guard"] != context.npc_id:
		return _lost_claim(context)
	# The body moves only with its carrier, through the same doors.
	_deaths_call(context, &"update_carried_position",
		[body_id(), context.npc_id, String(_space(context)), _position(context)])
	match phase:
		PHASE_CARRY:
			if context.minute - float(progress["phase_started"]) >= LIFT_MINUTES:
				_enter(context, PHASE_REACH_CEMETERY)
			return NpcTaskResult.running()
		PHASE_REACH_CEMETERY:
			var plot: Variant = _ask(context, &"cemetery_plot", [body_id()])
			if not plot is Vector2:
				return NpcTaskResult.running()
			var state: Variant = context.call_service(&"travel_state", [task_id])
			if state == &"arrived" or _at(context, &"outdoors", plot):
				_release_travel(context)
				_enter(context, PHASE_BURY)
				return NpcTaskResult.running()
			if state == &"failed" or _travel_timed_out(context):
				_release_travel(context)
				_let_go(context)
				return NpcTaskResult.failed(&"unreachable")
			if state != &"traveling":
				return _travel_to(context, &"outdoors", (plot as Vector2) + STAND_OFFSET)
			return NpcTaskResult.running()
		PHASE_BURY:
			if context.minute - float(progress["phase_started"]) < BURY_MINUTES:
				return NpcTaskResult.running()
			var result: Variant = _deaths_call(context, &"bury", [body_id(), context.npc_id, context.minute])
			if result != TownDeaths.OK_RESULT:
				return _lost_claim(context)
			_ask(context, &"recovery_event", [&"buried", body_id(), context.npc_id])
			return NpcTaskResult.completed(&"buried")
	return NpcTaskResult.running()

# Where a guard's task picks up again from the authoritative record.
func _guard_phase_for(context: NpcTaskContext) -> String:
	var entry: Dictionary = _snapshot(context)
	if entry.is_empty() or entry["guard"] != context.npc_id:
		return PHASE_ACKNOWLEDGE
	match entry["stage"]:
		"recovering":
			return PHASE_REACH_BODY
		"carried":
			return phase if phase in [PHASE_CARRY, PHASE_REACH_CEMETERY, PHASE_BURY] else PHASE_CARRY
	return PHASE_ACKNOWLEDGE

# Another guard holds the body: this recovery is over unless the body is free for this guard.
func _lost_claim(context: NpcTaskContext) -> NpcTaskResult:
	_release_travel(context)
	var entry: Dictionary = _snapshot(context)
	if not entry.is_empty() and entry["stage"] == "reported" \
			and String(entry["guard"]) in ["", context.npc_id]:
		_enter(context, PHASE_ACKNOWLEDGE)
		return NpcTaskResult.running()
	return NpcTaskResult.completed(&"claimed_by_other")

# Sets the body down where the guard stands, or gives up an unfinished claim.
func _let_go(context: NpcTaskContext) -> void:
	var entry: Dictionary = _snapshot(context)
	if entry.is_empty() or entry["guard"] != context.npc_id:
		return
	if entry["stage"] == "carried":
		if _deaths_call(context, &"drop", [body_id(), context.npc_id, String(_space(context)),
				_position(context), context.minute]) == TownDeaths.OK_RESULT:
			_ask(context, &"recovery_event", [&"dropped", body_id(), context.npc_id])
	elif entry["stage"] == "recovering":
		_deaths_call(context, &"interrupt_recovery", [body_id(), context.npc_id, context.minute])

# --- Helpers ---

func _enter(context: NpcTaskContext, next: String) -> void:
	phase = next
	progress["phase_started"] = context.minute

func _deaths(context: NpcTaskContext) -> TownDeaths:
	return _ask(context, &"deaths") as TownDeaths

func _snapshot(context: NpcTaskContext) -> Dictionary:
	var deaths: TownDeaths = _deaths(context)
	return deaths.snapshot(body_id()) if deaths != null else {}

func _deaths_call(context: NpcTaskContext, method: StringName, args: Array) -> Variant:
	var deaths: TownDeaths = _deaths(context)
	return deaths.callv(method, args) if deaths != null else null

# A town service, or null while the town has not provided it.
static func _ask(context: NpcTaskContext, service: StringName, args: Array = []) -> Variant:
	return context.call_service(service, args) if context.has_service(service) else null

func _travel_to(context: NpcTaskContext, space: StringName, point: Vector2) -> NpcTaskResult:
	if not progress.has("travel_started"):
		progress["travel_started"] = context.minute
	if context.call_service(&"travel", [space, point, params["label"], task_id]) != true:
		return NpcTaskResult.blocked(&"unreachable")
	return NpcTaskResult.running()

func _travel_timed_out(context: NpcTaskContext) -> bool:
	var tuning: NpcBehaviorTuning = context.call_service(&"tuning") as NpcBehaviorTuning
	return tuning != null and progress.has("travel_started") \
		and context.minute - float(progress["travel_started"]) > tuning.travel_timeout_minutes

func _release_travel(context: NpcTaskContext) -> void:
	progress.erase("travel_started")
	context.call_service(&"cancel_travel", [task_id])

func _wake(context: NpcTaskContext) -> void:
	if context.call_service(&"is_sleeping") == true:
		context.call_service(&"wake", ["called"])

func _at(context: NpcTaskContext, space: StringName, point: Vector2) -> bool:
	return _space(context) == space and _position(context).distance_to(point) <= TownDeaths.PICKUP_DISTANCE

static func _entry_point(entry: Dictionary) -> Vector2:
	return Vector2(float(entry["position"][0]), float(entry["position"][1]))

func _space(context: NpcTaskContext) -> StringName:
	var space: Variant = context.call_service(&"space")
	return StringName(space) if space is StringName or space is String else &""

func _position(context: NpcTaskContext) -> Vector2:
	var at: Variant = context.actor.get(&"global_position") if context.actor != null else null
	return at if at is Vector2 else Vector2.INF

func _apply_tuning(tuning: NpcBehaviorTuning) -> void:
	if tuning != null:
		priority = tuning.duty_priority
