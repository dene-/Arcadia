extends SceneTree

## Runtime smoke: the real world scene runs about two game hours under the engine's own frame loop
## (TownLife processing, accelerated time scale), then a save/reload must restore the same tasks.
## Fails on any script error the engine logs during the run.
const Simulation = preload("res://tests/fixtures/npc_simulation_fixture.gd")

const START_MINUTE: float = 480.0
const RUN_MINUTES: float = 120.0
const TIME_SCALE: float = 8.0
const FRAME_LIMIT: int = 20000
const MIN_TRAVEL: float = 16.0

## Collects errors from every thread; the engine calls it outside the main loop.
class ErrorLog extends Logger:
	var script_errors: Array[String] = []
	var other_errors: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var text: String = "%s (%s:%d %s)" % [rationale if not rationale.is_empty() else code, file, line, function]
		_mutex.lock()
		if error_type == ERROR_TYPE_SCRIPT:
			script_errors.append(text)
		else:
			other_errors.append(text)
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

var failures: Array[String] = []
var _decided: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var errors := ErrorLog.new()
	OS.add_logger(errors)
	var wall: int = Time.get_ticks_msec()
	var cognition: Node = root.get_node("NpcCognition")
	var sim := Simulation.new()
	sim.setup(self)
	sim.save_game().life.minute = START_MINUTE
	await sim.load_world()
	_check(sim.problems.is_empty(), "World did not load: %s" % [sim.problems])
	if not sim.problems.is_empty():
		await _finish(sim, errors, wall)
		return
	var ids: Array[String] = sim.resident_ids()
	_check(ids.size() >= 30, "Only %d residents loaded" % ids.size())
	var start_positions: Dictionary = {}
	for id: String in ids:
		start_positions[id] = sim.resident(id).global_position
	var saves_before: Dictionary = cognition.saves.status()
	cognition.decisions.request_settled.connect(_on_settled)
	# The engine drives TownLife from here: no manual ticks.
	sim.life.set_process(true)
	Engine.time_scale = TIME_SCALE
	var frames: int = 0
	var travelled: Dictionary = {}
	while sim.save_game().life.minute < START_MINUTE + RUN_MINUTES and frames < FRAME_LIMIT:
		await process_frame
		frames += 1
		for id: String in ids:
			var npc: BaseNpc = sim.resident(id)
			if npc != null:
				travelled[id] = maxf(float(travelled.get(id, 0.0)),
					npc.global_position.distance_to(start_positions[id]))
	Engine.time_scale = 1.0
	sim.life.set_process(false)
	cognition.decisions.request_settled.disconnect(_on_settled)
	var elapsed: float = sim.save_game().life.minute - START_MINUTE
	_check(elapsed >= RUN_MINUTES, "Only %.1f game minutes passed in %d frames" % [elapsed, frames])
	var living: Array[String] = sim.resident_ids()
	_check(living.size() == ids.size(), "Residents died in a quiet town: %s" % [
		ids.filter(func(id: String) -> bool: return not id in living)])
	var still: Array[String] = []
	var undecided: Array[String] = []
	for id: String in living:
		if float(travelled.get(id, 0.0)) < MIN_TRAVEL:
			still.append(id)
		if int(_decided.get(id, 0)) == 0:
			undecided.append(id)
	_check(still.is_empty(), "Residents did not move: %s" % [still])
	_check(undecided.is_empty(), "Residents without a successful decision: %s" % [undecided])
	var saves: Dictionary = cognition.saves.status()
	var writes: int = saves.writes - saves_before.writes
	var requests: int = saves.requests - saves_before.requests
	_check(requests > 0 and writes * 4 <= requests,
		"Saves were not coalesced: %d writes for %d requests" % [writes, requests])
	_check(saves.failures == saves_before.failures, "%d save writes failed" % (saves.failures - saves_before.failures))
	var decisions: int = 0
	for id: String in _decided:
		decisions += int(_decided[id])
	print("Runtime smoke: %d residents, %.1f game minutes in %d frames at time scale %.0f; %d successful decisions; %d writes for %d save requests (%d coalesced)" % [
		living.size(), elapsed, frames, TIME_SCALE, decisions, writes, requests, saves.coalesced - saves_before.coalesced])
	await _check_reload(sim, living)
	await _finish(sim, errors, wall)

## A restart from the save restores every resident's current and suspended task by identity.
func _check_reload(sim: Simulation, ids: Array[String]) -> void:
	var before: Dictionary = {}
	var with_task: int = 0
	for id: String in ids:
		before[id] = _task_ids(sim, id)
		if not String(before[id][0]).is_empty():
			with_task += 1
	_check(with_task * 2 >= ids.size(), "Only %d of %d residents had a task to save" % [with_task, ids.size()])
	await sim.reload_world()
	_check(sim.problems.is_empty(), "Reload problems: %s" % [sim.problems])
	if not sim.problems.is_empty():
		return
	var changed: Array[String] = []
	for id: String in ids:
		var restored: Array[String] = _task_ids(sim, id)
		if restored != before[id]:
			changed.append("%s %s -> %s" % [id, before[id], restored])
	_check(changed.is_empty(), "Reload changed tasks: %s" % [changed])
	print("Runtime smoke reload: %d of %d residents restored with their task, %d changed" % [
		with_task - changed.size(), ids.size(), changed.size()])

## [current task id, suspended task id]; empty strings when absent.
func _task_ids(sim: Simulation, id: String) -> Array[String]:
	var brain: NpcBrain = sim.life.brain_for(id)
	if brain == null:
		return ["", ""]
	var controller: NpcTaskController = brain.controller
	return [controller.current.task_id if controller.current != null else "",
		controller.suspended.task_id if controller.suspended != null else ""]

func _on_settled(entry: Dictionary) -> void:
	if String(entry.outcome) == "success":
		var id: String = String(entry.npc_id)
		_decided[id] = int(_decided.get(id, 0)) + 1

func _finish(sim: Simulation, errors: ErrorLog, wall: int) -> void:
	Engine.time_scale = 1.0
	await sim.teardown()
	OS.remove_logger(errors)
	_check(errors.script_errors.is_empty(), "%d script errors: %s" % [errors.script_errors.size(),
		errors.script_errors.slice(0, 5)])
	_check(errors.other_errors.is_empty(), "%d engine errors: %s" % [errors.other_errors.size(),
		errors.other_errors.slice(0, 5)])
	print("Runtime smoke: %.1f s wall" % ((Time.get_ticks_msec() - wall) / 1000.0))
	for failure: String in failures:
		push_error(failure)
	print("NPC runtime smoke: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
