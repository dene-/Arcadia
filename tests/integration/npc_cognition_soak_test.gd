extends SceneTree

## Accelerated soak of the integrated cognition stack: 7 game days with the 35-resident reference town
## and a 70-resident stress day, deterministic mock providers with simulated latency, one 100-event
## burst and one provider outage. Prints every metric it collects; asserts behavior and the 2 ms
## per-frame cognition budget for the reference town.
const Simulation = preload("res://tests/fixtures/npc_simulation_fixture.gd")
const FakeService = preload("res://tests/fixtures/npc_fake_decision_service.gd")

const REFERENCE_RESIDENTS: int = 35
const STRESS_RESIDENTS: int = 70
const SOAK_DAYS: int = 7
const STRESS_DAYS: int = 1
const DAY_MINUTES: float = 1440.0
const START_MINUTE: float = 360.0
## Game minutes simulated at real speed (time scale 1, one 60 Hz frame per step) for CPU timing.
const MEASURE_MINUTES: float = 120.0
const STRESS_MEASURE_MINUTES: float = 60.0
## Engine time scale for the accelerated remainder: actors walk TIME_SCALE times farther per frame.
const TIME_SCALE: float = 8.0
const FPS: float = 60.0
const FRAME_BUDGET_USEC: float = 2000.0
const CONSIDER_BUDGET_USEC: float = 500.0
const BURST_EVENTS: int = 100
## Minutes after START_MINUTE; inside the first day after the CPU window.
const BURST_AT: float = 8.0 * 60.0
const OUTAGE_AT: float = DAY_MINUTES + 4.0 * 60.0
const OUTAGE_MINUTES: float = 120.0
const OUTAGE_EVENTS: int = 6
## The retry ladder ends in a 60 s backoff (90 game minutes); two backoffs bound recovery.
const RECOVERY_LIMIT_MINUTES: float = 180.0
const EVENT_KIND: StringName = &"soak_bell"
const SANITIZER_VARIABLES: Array[String] = ["ASAN_OPTIONS", "TSAN_OPTIONS", "UBSAN_OPTIONS",
	"LSAN_OPTIONS", "MSAN_OPTIONS"]

## Answers each request after a deterministic simulated delay; `deliver` advances its clock. Counts
## calls instead of recording payloads, which a week of simulation would pile up.
class SoakBackend extends FakeService:
	signal delivered
	var now_msec: float = 0.0
	var totals: Dictionary = {}

	func deliver(msec: float) -> void:
		now_msec = msec
		delivered.emit()

	static func latency_msec(handle: String) -> float:
		return 250.0 + float(posmod(hash(handle), 1000))

	func _respond(endpoint: String, _payload: Dictionary, handle: String) -> Variant:
		totals[endpoint] = int(totals.get(endpoint, 0)) + 1
		var due: float = now_msec + latency_msec(handle)
		while (now_msec < due or _held.has(endpoint)) and not _cancelled.has(handle):
			await delivered
		if _cancelled.has(handle):
			_cancelled.erase(handle)
			return null
		var queue: Array = _queues[endpoint]
		var response: Dictionary = queue.pop_front() if not queue.is_empty() else _defaults[endpoint]
		return response.duplicate(true)

## Times every pair consideration TownLife makes on its one-second social tick.
class TimedEncounters extends TownEncounters:
	var usec: int = 0
	var calls: int = 0

	func consider(first: BaseNpc, second: BaseNpc) -> void:
		var start: int = Time.get_ticks_usec()
		super.consider(first, second)
		usec += Time.get_ticks_usec() - start
		calls += 1

var failures: Array[String] = []
var _cognition: Node
var _sim: Simulation
var _backend: SoakBackend
var _encounters: TimedEncounters
var _label: String = ""
var _sim_msec: float = 0.0
var _step: float = 1.0 / FPS
var _measuring: bool = false
var _frame_usec: Array[int] = []
## Whole engine iterations (physics, every node's processing, this driver) between frame starts.
var _frame_wall_usec: Array[int] = []
var _last_frame_start: int = 0
var _write_reasons: Dictionary = {}
var _counted_writes: int = 0
var _saves_start: Dictionary = {}
var _tick_consider_usec: Array[int] = []
## Cognition time of the frames that ran the one-second social tick.
var _tick_frame_usec: Array[int] = []
var _measured_consider_usec: int = 0
var _measured_consider_calls: int = 0
var _peaks: Dictionary = {}
var _waits: Array[int] = []
var _waits_by_npc: Dictionary = {}
var _outcomes: Dictionary = {}
var _decided: Dictionary = {}
var _transitions: int = 0
var _transitions_by_npc: Dictionary = {}
var _routine_starts: int = 0
var _evidence_peak_total: int = 0
var _evidence_peak_resident: int = 0
var _bell_serial: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	_cognition = root.get_node("NpcCognition")
	_cognition.perception.register(EVENT_KIND, _perceive_bell)
	print("Soak hardware: %s; %d logical cores; Godot %s; %s build; %s; physics %d Hz fixed; accelerated time scale %.0f" % [
		OS.get_processor_name(), OS.get_processor_count(), Engine.get_version_info().string,
		"debug" if OS.is_debug_build() else "release", OS.get_name(), int(FPS), TIME_SCALE])
	await _reference_soak()
	await _stress_soak()
	for failure: String in failures:
		push_error(failure)
	print("NPC cognition soak: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

# --- Runs ---

func _reference_soak() -> void:
	_label = "reference"
	var wall: int = Time.get_ticks_msec()
	if not await _start(REFERENCE_RESIDENTS):
		return
	var ids: Array[String] = _sim.resident_ids()
	_check(ids.size() == REFERENCE_RESIDENTS, "[reference] %d residents, expected %d" % [ids.size(), REFERENCE_RESIDENTS])
	var start_bytes: int = await _baseline_bytes()
	var start_memory: int = OS.get_static_memory_usage()
	var start_objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var positions: Dictionary = _positions()
	var travelled: Dictionary = {}
	await _measure_window(MEASURE_MINUTES)
	var cpu: Dictionary = _cpu_summary()
	_accelerate()
	var daily: Array[String] = []
	var day_writes: int = _cognition.saves.writes
	var day_transitions: int = _transitions
	var day_settled: int = _waits.size()
	for day: int in range(SOAK_DAYS):
		var day_end: float = START_MINUTE + (day + 1) * DAY_MINUTES
		if day == 0:
			await _advance_to(START_MINUTE + BURST_AT, positions, travelled)
			await _burst()
		if day == 1:
			await _advance_to(START_MINUTE + OUTAGE_AT, positions, travelled)
			await _outage(positions, travelled)
		await _advance_to(day_end, positions, travelled)
		var status: Dictionary = _cognition.saves.status()
		daily.append("day %d: writes %d, file %d B, task transitions %d, settled requests %d, static memory %.1f MB, objects %d" % [
			day + 1, status.writes - day_writes, status.bytes_last, _transitions - day_transitions,
			_waits.size() - day_settled, OS.get_static_memory_usage() / 1048576.0,
			int(Performance.get_monitor(Performance.OBJECT_COUNT))])
		day_writes = status.writes
		day_transitions = _transitions
		day_settled = _waits.size()
	var elapsed: float = _save().life.minute - START_MINUTE
	_check(absf(elapsed - SOAK_DAYS * DAY_MINUTES) < 1.0,
		"[reference] Clock advanced %.1f minutes, expected %.0f" % [elapsed, SOAK_DAYS * DAY_MINUTES])
	_check_daily_life(ids, travelled)
	_check(_sim.problems.is_empty(), "[reference] Fixture problems: %s" % [_sim.problems])
	_print_metrics(cpu, start_bytes, start_memory, start_objects, Time.get_ticks_msec() - wall)
	for line: String in daily:
		print("  ", line)
	if _under_sanitizer():
		print("  CPU budget not asserted: running under a sanitizer")
	else:
		_check(float(cpu.p95) < FRAME_BUDGET_USEC,
			"[reference] Cognition p95 %.3f ms/frame exceeds %.1f ms" % [cpu.p95 / 1000.0, FRAME_BUDGET_USEC / 1000.0])
	await _finish()

func _stress_soak() -> void:
	_label = "stress"
	var wall: int = Time.get_ticks_msec()
	if not await _start(STRESS_RESIDENTS):
		return
	var ids: Array[String] = _sim.resident_ids()
	_check(ids.size() == STRESS_RESIDENTS, "[stress] %d residents, expected %d" % [ids.size(), STRESS_RESIDENTS])
	var start_bytes: int = await _baseline_bytes()
	var start_memory: int = OS.get_static_memory_usage()
	var start_objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var positions: Dictionary = _positions()
	var travelled: Dictionary = {}
	await _measure_window(STRESS_MEASURE_MINUTES)
	var cpu: Dictionary = _cpu_summary()
	_accelerate()
	await _advance_to(START_MINUTE + STRESS_DAYS * DAY_MINUTES, positions, travelled)
	_check_daily_life(ids, travelled)
	_check(_sim.problems.is_empty(), "[stress] Fixture problems: %s" % [_sim.problems])
	_print_metrics(cpu, start_bytes, start_memory, start_objects, Time.get_ticks_msec() - wall)
	await _finish()

## Loads the town with `residents` people (the real 33 plus synthetic clones), wires the simulated
## clock, the latency backend and the timed encounters. False when the town failed to load.
func _start(residents: int) -> bool:
	_reset_metrics()
	_sim = Simulation.new()
	_sim.setup(self)
	_backend = SoakBackend.new()
	_backend.v2_base_url = Simulation.GUARD_ENDPOINT
	root.add_child(_backend)
	_sim.backend.queue_free()
	_sim.backend = _backend
	_cognition.backend = _backend
	_cognition.decisions.transport = _backend
	var simulated: Callable = func() -> int: return int(_sim_msec)
	_cognition.decisions.clock = simulated
	_cognition.events.clock = simulated
	_cognition.saves.clock = simulated
	_save().life.minute = START_MINUTE
	_add_synthetic_residents(residents)
	await _sim.load_world()
	_check(_sim.problems.is_empty(), "[%s] Fixture problems: %s" % [_label, _sim.problems])
	if not _sim.problems.is_empty():
		await _finish()
		return false
	_swap_encounters()
	_cognition.decisions.request_settled.connect(_on_settled)
	for id: String in _sim.resident_ids():
		_sim.life.brain_for(id).controller.transitioned.connect(_on_transition.bind(id))
	return true

func _finish() -> void:
	Engine.time_scale = 1.0
	if _cognition.decisions.request_settled.is_connected(_on_settled):
		_cognition.decisions.request_settled.disconnect(_on_settled)
	await _sim.teardown()
	var real: Callable = Callable(Time, "get_ticks_msec")
	_cognition.decisions.clock = real
	_cognition.events.clock = real
	_cognition.saves.clock = real

func _add_synthetic_residents(target: int) -> void:
	var population: TownPopulation = _save().population
	population.ensure_population(_save().region_seed)
	var templates: Array[String] = []
	for member: Array in TownPopulation.MEMBERS:
		if member[5] != "guard":
			templates.append(member[0])
	var serial: int = 0
	while population.people.size() < target:
		var source: Dictionary = population.people[templates[serial % templates.size()]]
		var id: String = "%s_synthetic_%02d" % [source.id, serial]
		var clone: Dictionary = source.duplicate(true)
		clone.id = id
		clone.name = "%s %d" % [source.name, serial + 2]
		clone.kin = {}
		clone.appearance = NpcRoutinePlan.random_for(_save().region_seed, id + ":looks").randi_range(0, 65535)
		population.people[id] = clone
		serial += 1

func _swap_encounters() -> void:
	var old: TownEncounters = _sim.life.encounters
	_encounters = TimedEncounters.new()
	_encounters.state = old.state
	_encounters.store = old.store
	_encounters.decisions = old.decisions
	_encounters.seed_value = old.seed_value
	_encounters.saves = old.saves
	_encounters.brains = old.brains
	_encounters.tuning = old.tuning
	_sim.life.remove_child(old)
	old.free()
	_sim.life.add_child(_encounters)
	_sim.life.encounters = _encounters

# --- Time ---

## One frame: provider answers due by now, one TownLife tick (timed together as cognition work),
## then one physics frame so actors move.
func _frame() -> void:
	_count_writes()
	_sim_msec += _step * 1000.0
	var consider_before: int = _encounters.usec
	var start: int = Time.get_ticks_usec()
	if _measuring and _last_frame_start > 0:
		_frame_wall_usec.append(start - _last_frame_start)
	_last_frame_start = start
	_backend.deliver(_sim_msec)
	_sim.life._process(_step)
	var spent: int = Time.get_ticks_usec() - start
	if _measuring:
		_frame_usec.append(spent)
		if _encounters.usec != consider_before:
			_tick_consider_usec.append(_encounters.usec - consider_before)
			_tick_frame_usec.append(spent)
	await physics_frame
	var decisions: NpcDecisionService = _cognition.decisions
	_peak("judgment queued", decisions.queued_count(NpcDecisionService.Pool.JUDGMENT))
	_peak("judgment active", decisions.active_count(NpcDecisionService.Pool.JUDGMENT))
	_peak("text queued", decisions.queued_count(NpcDecisionService.Pool.TEXT))
	_peak("text active", decisions.active_count(NpcDecisionService.Pool.TEXT))
	_peak("routine plans pending", _sim.life._pending.size())

func _measure_window(minutes: float) -> void:
	Engine.time_scale = 1.0
	_step = 1.0 / FPS
	_measuring = true
	_last_frame_start = 0
	var consider_usec: int = _encounters.usec
	var consider_calls: int = _encounters.calls
	var target: float = _save().life.minute + minutes
	while _save().life.minute < target - 0.0001:
		await _frame()
	_measuring = false
	_measured_consider_usec = _encounters.usec - consider_usec
	_measured_consider_calls = _encounters.calls - consider_calls

func _accelerate() -> void:
	Engine.time_scale = TIME_SCALE
	_step = TIME_SCALE / FPS

## Advances to the game minute `target`, sampling evidence and travel once per game hour.
func _advance_to(target: float, positions: Dictionary, travelled: Dictionary) -> void:
	var next_sample: float = _save().life.minute + 60.0
	while _save().life.minute < target - 0.0001:
		await _frame()
		if _save().life.minute >= next_sample:
			next_sample += 60.0
			_sample_evidence()
			_accumulate_travel(positions, travelled)

## Advances the frames needed for `minutes` game minutes at the current step.
func _advance_minutes(minutes: float, positions: Dictionary, travelled: Dictionary) -> void:
	await _advance_to(_save().life.minute + minutes, positions, travelled)

# --- Burst and outage ---

func _perceive_bell(observer: BaseNpc, event: WorldEvent) -> Dictionary:
	if observer != event.subject or observer.health <= 0:
		return {}
	return {"kind": "town_bell", "sense": "hearing", "player_involved": false, "danger_possible": false,
		"directly_affected": false, "topics": ["town"], "text": String(event.facts.text)}

func _publish_bell(subject: BaseNpc) -> void:
	_bell_serial += 1
	var event := WorldEvent.new()
	event.kind = EVENT_KIND
	event.subject = subject
	event.facts = {"text": "I heard the town bell ring %d times." % _bell_serial}
	root.get_node("WorldEvents").publish(event)

## 100 noncritical events in one frame must join one ordinary write.
func _burst() -> void:
	var saves: NpcSaveCoordinator = _cognition.saves
	var ids: Array[String] = _sim.resident_ids()
	var before: Dictionary = saves.status()
	for index: int in range(BURST_EVENTS):
		_publish_bell(_sim.resident(ids[index % ids.size()]))
	var after: Dictionary = saves.status()
	_check(after.writes == before.writes, "[burst] %d writes during the burst frame" % (after.writes - before.writes))
	_check(after.requests - before.requests >= BURST_EVENTS,
		"[burst] Only %d save requests for %d events" % [after.requests - before.requests, BURST_EVENTS])
	_check(saves.pending(), "[burst] No write was pending after the burst")
	var frames: int = 0
	while saves.writes == before.writes and frames < 10000:
		await _frame()
		frames += 1
	var landed: Dictionary = saves.status()
	var waited_msec: float = frames * _step * 1000.0
	_check(landed.writes - before.writes == 1,
		"[burst] %d writes for %d same-frame events, expected one coalesced write" % [landed.writes - before.writes, BURST_EVENTS])
	_check(landed.coalesced - before.coalesced >= BURST_EVENTS - 1,
		"[burst] Only %d requests coalesced" % (landed.coalesced - before.coalesced))
	_check(waited_msec <= NpcSaveCoordinator.MAX_PENDING_MSEC + 1000.0,
		"[burst] The coalesced write waited %.0f ms" % waited_msec)
	_check(landed.status == OK, "[burst] Coalesced write failed: %s" % landed.status)
	print("[%s] burst: %d events -> %d save requests, %d coalesced, %d write (reason %s) %.1f s (simulated) after the burst" % [
		_label, BURST_EVENTS, landed.requests - before.requests, landed.coalesced - before.coalesced,
		landed.writes - before.writes, landed.reason, waited_msec / 1000.0])

## Providers fail for OUTAGE_MINUTES: evidence perceived meanwhile is retained, daily life goes on,
## and the evidence is appraised once providers recover.
func _outage(positions: Dictionary, travelled: Dictionary) -> void:
	var ids: Array[String] = _sim.resident_ids()
	_backend.fail_all = true
	var unavailable_before: int = int(_outcomes.get("unavailable", 0))
	var transitions_before: int = _transitions
	var routines_before: int = _routine_starts
	var watched: Dictionary = {}
	for index: int in range(OUTAGE_EVENTS):
		var id: String = ids[(index * 5) % ids.size()]
		var inbox: NpcEvidenceInbox = _save().minds.get_mind(id).evidence
		var known: Dictionary = {}
		for observation: NpcObservation in inbox.pending_observations():
			known[observation.observation_id] = true
		_publish_bell(_sim.resident(id))
		for observation: NpcObservation in inbox.pending_observations():
			if not known.has(observation.observation_id) and String(observation.kind) == "town_bell":
				watched[observation.observation_id] = id
	_check(watched.size() == OUTAGE_EVENTS, "[outage] %d of %d observations entered the inbox" % [watched.size(), OUTAGE_EVENTS])
	await _advance_minutes(OUTAGE_MINUTES, positions, travelled)
	var retained: int = 0
	for observation_id: String in watched:
		var inbox: NpcEvidenceInbox = _save().minds.get_mind(watched[observation_id]).evidence
		if inbox.contains_pending(observation_id) and not inbox.has_receipt(observation_id):
			retained += 1
	_check(retained == watched.size(), "[outage] Only %d of %d observations were retained during the outage" % [retained, watched.size()])
	var failed_calls: int = int(_outcomes.get("unavailable", 0)) - unavailable_before
	_check(failed_calls > 0, "[outage] No request failed during the outage")
	_check(_routine_starts > routines_before, "[outage] No routine task started during the outage")
	_check_active_or_replanning(ids, "[outage]")
	var outage_transitions: int = _transitions - transitions_before
	_backend.fail_all = false
	var recovery_start: float = _save().life.minute
	var appraised: int = 0
	while _save().life.minute - recovery_start < RECOVERY_LIMIT_MINUTES:
		await _advance_minutes(10.0, positions, travelled)
		appraised = 0
		for observation_id: String in watched:
			if _save().minds.get_mind(watched[observation_id]).evidence.has_receipt(observation_id):
				appraised += 1
		if appraised == watched.size():
			break
	_check(appraised == watched.size(), "[outage] %d of %d retained observations appraised %.0f minutes after recovery" % [
		appraised, watched.size(), RECOVERY_LIMIT_MINUTES])
	print("[%s] outage: %.0f game minutes, %d failed requests, %d task transitions, %d routine starts; %d/%d observations retained, appraised within %.0f game minutes of recovery" % [
		_label, OUTAGE_MINUTES, failed_calls, outage_transitions, _routine_starts - routines_before, retained,
		watched.size(), _save().life.minute - recovery_start])

# --- Behavior checks ---

func _check_daily_life(ids: Array[String], travelled: Dictionary) -> void:
	var living: Array[String] = _sim.resident_ids()
	_check(living.size() == ids.size(), "[%s] Residents died in a quiet town: %s" % [_label,
		ids.filter(func(id: String) -> bool: return not id in living)])
	for id: String in living:
		_check(int(_decided.get(id, 0)) > 0, "[%s] %s never received a successful decision" % [_label, id])
		_check(float(travelled.get(id, 0.0)) > 32.0, "[%s] %s travelled only %.1f px" % [_label, id, float(travelled.get(id, 0.0))])
		_check(int(_transitions_by_npc.get(id, 0)) > 0, "[%s] %s never changed task" % [_label, id])
	_check_active_or_replanning(living, "[%s] end" % _label)

## Every resident runs a task or is about to plan one.
func _check_active_or_replanning(ids: Array[String], label: String) -> void:
	for id: String in ids:
		var brain: NpcBrain = _sim.life.brain_for(id)
		if brain == null:
			continue
		var current: NpcTask = brain.controller.current
		var active: bool = current != null and current.status == NpcTask.Status.RUNNING
		var replanning: bool = current == null and (_sim.life._pending.has(id) or _sim.life._routine_due(id))
		_check(active or replanning, "%s %s is inactive with nothing pending" % [label, id])

# --- Metrics ---

func _reset_metrics() -> void:
	_sim_msec = 0.0
	_step = 1.0 / FPS
	_measuring = false
	_frame_usec.clear()
	_frame_wall_usec.clear()
	_tick_frame_usec.clear()
	_write_reasons.clear()
	_counted_writes = _cognition.saves.writes
	_saves_start = _cognition.saves.status()
	_tick_consider_usec.clear()
	_measured_consider_usec = 0
	_measured_consider_calls = 0
	_peaks.clear()
	_waits.clear()
	_waits_by_npc.clear()
	_outcomes.clear()
	_decided.clear()
	_transitions = 0
	_transitions_by_npc.clear()
	_routine_starts = 0
	_evidence_peak_total = 0
	_evidence_peak_resident = 0

func _save() -> NpcWorldSave:
	return _cognition.save_game

## The file size right after load, written once so later growth is measured from a real file.
func _baseline_bytes() -> int:
	_cognition.saves.flush(&"soak_baseline")
	return _cognition.saves.bytes_last

func _on_settled(entry: Dictionary) -> void:
	var id: String = String(entry.npc_id)
	var latency: int = int(entry.latency_ms)
	_waits.append(latency)
	if not _waits_by_npc.has(id):
		_waits_by_npc[id] = [] as Array[int]
	(_waits_by_npc[id] as Array[int]).append(latency)
	var outcome: String = String(entry.outcome)
	_outcomes[outcome] = int(_outcomes.get(outcome, 0)) + 1
	if outcome == "success":
		_decided[id] = int(_decided.get(id, 0)) + 1

func _on_transition(entry: Dictionary, id: String) -> void:
	_transitions += 1
	_transitions_by_npc[id] = int(_transitions_by_npc.get(id, 0)) + 1
	if String(entry.kind) == "routine" and String(entry.to) == NpcTask.status_name(NpcTask.Status.RUNNING):
		_routine_starts += 1

func _peak(key: String, value: int) -> void:
	_peaks[key] = maxi(int(_peaks.get(key, 0)), value)

## Attributes writes since the last frame to the coordinator's latest reason.
func _count_writes() -> void:
	var writes: int = _cognition.saves.writes
	if writes != _counted_writes:
		var reason: String = String(_cognition.saves.last_reason)
		_write_reasons[reason] = int(_write_reasons.get(reason, 0)) + writes - _counted_writes
		_counted_writes = writes

func _sample_evidence() -> void:
	var total: int = 0
	for id: String in _save().population.people:
		var pending: int = _save().minds.get_mind(id).evidence.pending_observations().size()
		total += pending
		_evidence_peak_resident = maxi(_evidence_peak_resident, pending)
	_evidence_peak_total = maxi(_evidence_peak_total, total)

func _positions() -> Dictionary:
	var result: Dictionary = {}
	for id: String in _sim.resident_ids():
		result[id] = _sim.resident(id).global_position
	return result

## Sums hourly straight-line displacement: a lower bound on the distance each resident walked.
func _accumulate_travel(positions: Dictionary, travelled: Dictionary) -> void:
	for id: String in _sim.resident_ids():
		var now: Vector2 = _sim.resident(id).global_position
		travelled[id] = float(travelled.get(id, 0.0)) + now.distance_to(positions.get(id, now))
		positions[id] = now

func _cpu_summary() -> Dictionary:
	var frames: int = _frame_usec.size()
	return {"frames": frames, "p50": _percentile(_frame_usec, 0.5), "p95": _percentile(_frame_usec, 0.95),
		"max": _percentile(_frame_usec, 1.0), "wall_p50": _percentile(_frame_wall_usec, 0.5),
		"wall_p95": _percentile(_frame_wall_usec, 0.95), "tick_frame_p50": _percentile(_tick_frame_usec, 0.5),
		"tick_frame_p95": _percentile(_tick_frame_usec, 0.95),
		"consider_per_frame": float(_measured_consider_usec) / maxf(1.0, float(frames)),
		"consider_calls": _measured_consider_calls, "consider_ticks": _tick_consider_usec.size(),
		"consider_tick_p50": _percentile(_tick_consider_usec, 0.5),
		"consider_tick_p95": _percentile(_tick_consider_usec, 0.95),
		"consider_tick_max": _percentile(_tick_consider_usec, 1.0)}

func _print_metrics(cpu: Dictionary, start_bytes: int, start_memory: int, start_objects: int, wall_msec: int) -> void:
	var residents: int = _sim.resident_ids().size()
	var status: Dictionary = _cognition.saves.status()
	var game_days: float = (_save().life.minute - START_MINUTE) / DAY_MINUTES
	print("[%s] %d residents, %.2f game days, %.1f s wall" % [_label, residents, game_days, wall_msec / 1000.0])
	print("  cognition CPU per frame (provider delivery + TownLife tick, %d real-speed frames): p50 %.3f ms, p95 %.3f ms, max %.3f ms; social-tick frames p50 %.3f ms, p95 %.3f ms; whole engine frame p50 %.3f ms, p95 %.3f ms" % [
		cpu.frames, cpu.p50 / 1000.0, cpu.p95 / 1000.0, cpu.max / 1000.0, cpu.tick_frame_p50 / 1000.0,
		cpu.tick_frame_p95 / 1000.0, cpu.wall_p50 / 1000.0, cpu.wall_p95 / 1000.0])
	print("  TownEncounters.consider: %.3f ms/frame amortized (%d calls over %d social ticks); per tick p50 %.3f ms, p95 %.3f ms, max %.3f ms%s" % [
		cpu.consider_per_frame / 1000.0, cpu.consider_calls, cpu.consider_ticks, cpu.consider_tick_p50 / 1000.0,
		cpu.consider_tick_p95 / 1000.0, cpu.consider_tick_max / 1000.0,
		"  ABOVE 0.5 ms/frame" if cpu.consider_per_frame > CONSIDER_BUDGET_USEC else ""])
	var peaks: Array[String] = []
	for key: String in _peaks:
		peaks.append("%s %d" % [key, _peaks[key]])
	print("  queue peaks: ", ", ".join(peaks))
	var npc_p50: Array[int] = []
	var npc_p95: Array[int] = []
	var npc_max: Array[int] = []
	var npc_counts: Array[int] = []
	for id: String in _waits_by_npc:
		npc_p50.append(_percentile(_waits_by_npc[id], 0.5))
		npc_p95.append(_percentile(_waits_by_npc[id], 0.95))
		npc_max.append(_percentile(_waits_by_npc[id], 1.0))
		npc_counts.append((_waits_by_npc[id] as Array[int]).size())
	print("  request wait (simulated ms, queue + provider): all p50 %d, p95 %d, max %d over %d requests" % [
		_percentile(_waits, 0.5), _percentile(_waits, 0.95), _percentile(_waits, 1.0), _waits.size()])
	print("  per-resident wait (median / worst resident): p50 %d / %d, p95 %d / %d, max %d / %d; requests per resident min %d, max %d" % [
		_percentile(npc_p50, 0.5), _percentile(npc_p50, 1.0), _percentile(npc_p95, 0.5), _percentile(npc_p95, 1.0),
		_percentile(npc_max, 0.5), _percentile(npc_max, 1.0), _percentile(npc_counts, 0.0), _percentile(npc_counts, 1.0)])
	var outcomes: Array[String] = []
	for key: String in _outcomes:
		outcomes.append("%s %d" % [key, _outcomes[key]])
	var calls: Array[String] = []
	for key: String in _backend.totals:
		calls.append("%s %d" % [key, _backend.totals[key]])
	print("  outcomes: %s; provider calls: %s" % [", ".join(outcomes), ", ".join(calls)])
	var pending: int = 0
	var receipts: int = 0
	var memories: int = 0
	for id: String in _save().population.people:
		var inbox: NpcEvidenceInbox = _save().minds.get_mind(id).evidence
		pending += inbox.pending_observations().size()
		receipts += inbox.receipt_count()
		var snapshot: Dictionary = _save().memory.snapshot(id)
		memories += (snapshot.get("memories", []) as Array).size()
	print("  evidence: pending peak %d total / %d per resident, pending at end %d, receipts %d, memories %d" % [
		_evidence_peak_total, _evidence_peak_resident, pending, receipts, memories])
	var reasons: Array[String] = []
	for key: String in _write_reasons:
		reasons.append("%s %d" % [key, _write_reasons[key]])
	var writes: int = status.writes - int(_saves_start.writes)
	print("  saves (this run): %d writes for %d requests (%d coalesced, %d failures), %.1f writes per game hour; file %d B at start, %d B at end, %d B written in total; write reasons: %s" % [
		writes, status.requests - int(_saves_start.requests), status.coalesced - int(_saves_start.coalesced),
		status.failures - int(_saves_start.failures), writes / maxf(1.0, game_days * 24.0), start_bytes,
		status.bytes_last, status.bytes_total - int(_saves_start.bytes_total), ", ".join(reasons)])
	var churn: Array[int] = []
	for id: String in _transitions_by_npc:
		churn.append(int(_transitions_by_npc[id]))
	print("  task churn: %d transitions, %.1f per resident per game day (resident max %d), %d routine starts" % [
		_transitions, _transitions / maxf(1.0, residents * game_days), _percentile(churn, 1.0), _routine_starts])
	print("  memory growth: static %.1f -> %.1f MB, objects %d -> %d, save file %+d B" % [
		start_memory / 1048576.0, OS.get_static_memory_usage() / 1048576.0, start_objects,
		int(Performance.get_monitor(Performance.OBJECT_COUNT)), status.bytes_last - start_bytes])

static func _percentile(values: Array, fraction: float) -> int:
	if values.is_empty():
		return 0
	var sorted: Array = values.duplicate()
	sorted.sort()
	var index: int = clampi(ceili(fraction * sorted.size()) - 1, 0, sorted.size() - 1)
	return int(sorted[index])

static func _under_sanitizer() -> bool:
	for variable: String in SANITIZER_VARIABLES:
		if OS.has_environment(variable):
			return true
	return false
