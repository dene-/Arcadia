class_name NpcSaveCoordinator
extends Node

## The only writer of the NPC world save. Ordinary changes `request` a write and are coalesced:
## the write happens DEBOUNCE_MSEC after the latest request, but never later than MAX_PENDING_MSEC
## after the first unsaved one. Critical transitions `flush`, writing at once and cancelling the
## pending write. Snapshot hooks run right before every write so live state (positions, task
## checkpoints) lands in the same coherent snapshot. Times are real milliseconds from `clock`.

const DEBOUNCE_MSEC: int = 2000
const MAX_PENDING_MSEC: int = 10000

## Emitted after a write that failed, with the reason that caused it and the error.
signal write_failed(reason: StringName, error: Error)

var save_game: NpcWorldSave
## Returns the current real time in milliseconds; injectable for tests.
var clock: Callable = Callable(Time, "get_ticks_msec")
## Successful writes.
var writes: int = 0
## Size of the save file after the latest successful write, and the sum over all writes.
var bytes_last: int = 0
var bytes_total: int = 0
## Every `request` call, and those that joined an already pending (or running) write.
var requests: int = 0
var coalesced: int = 0
var failures: int = 0
var last_status: Error = OK
var last_reason: StringName = &""
var _hooks: Array[Callable] = []
var _pending: bool = false
var _first_msec: int = 0
var _latest_msec: int = 0
var _reason: StringName = &""
var _writing: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	poll()

func _exit_tree() -> void:
	if _pending:
		flush(&"exit")

## Marks the world dirty; the write follows once requests quiet down (see class notes).
func request(reason: StringName) -> void:
	requests += 1
	if _pending or _writing:
		coalesced += 1
		_latest_msec = int(clock.call())
		return
	_pending = true
	_reason = reason
	_first_msec = int(clock.call())
	_latest_msec = _first_msec

## Writes now (after the caller's synchronous changes) and cancels the pending write. False when
## the write failed.
func flush(reason: StringName) -> bool:
	if _writing:
		return false
	_pending = false
	return _write(reason) == OK

## Writes the pending request once it is due. Called every frame.
func poll() -> void:
	if not _pending or _writing:
		return
	var now: int = int(clock.call())
	if now - _latest_msec >= DEBOUNCE_MSEC or now - _first_msec >= MAX_PENDING_MSEC:
		_pending = false
		_write(_reason)

func pending() -> bool:
	return _pending

## `hook()` runs right before every write; adding it again does nothing.
func add_snapshot_hook(hook: Callable) -> void:
	if not _hooks.has(hook):
		_hooks.append(hook)

func remove_snapshot_hook(hook: Callable) -> void:
	_hooks.erase(hook)

## Counters for the inspector, tests and soak reports.
func status() -> Dictionary:
	return {"status": last_status, "reason": String(last_reason), "writes": writes,
		"bytes_last": bytes_last, "bytes_total": bytes_total, "requests": requests,
		"coalesced": coalesced, "failures": failures, "pending": _pending}

func _write(reason: StringName) -> Error:
	_writing = true
	for hook: Callable in _hooks.duplicate():
		if hook.is_valid():
			hook.call()
	var error: Error = save_game.save_file() if save_game != null else ERR_UNCONFIGURED
	_writing = false
	last_status = error
	last_reason = reason
	if error != OK:
		failures += 1
		push_warning("NPC world could not be saved (%s): %s" % [reason, error])
		write_failed.emit(reason, error)
		return error
	writes += 1
	var file := FileAccess.open(save_game.path, FileAccess.READ)
	bytes_last = int(file.get_length()) if file != null else 0
	bytes_total += bytes_last
	return OK
