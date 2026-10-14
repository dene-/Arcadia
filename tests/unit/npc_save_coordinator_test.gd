extends "res://tests/test_case.gd"

var _now: int = 0
var _hook_calls: int = 0
var _coordinator: NpcSaveCoordinator

func before_each() -> void:
	_now = 1000
	_hook_calls = 0
	var save := NpcWorldSave.new()
	save.path = OS.get_temp_dir().path_join("arcadia-save-coordinator-%d.json" % OS.get_process_id())
	save.legacy_world_path = save.path + ".legacy-world"
	save.legacy_memory_path = save.path + ".legacy-memory"
	_coordinator = NpcSaveCoordinator.new()
	_coordinator.save_game = save
	_coordinator.clock = func() -> int: return _now
	_coordinator.add_snapshot_hook(func() -> void: _hook_calls += 1)

func after_each() -> void:
	var path: String = _coordinator.save_game.path
	for file: String in [path, path + ".tmp"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
	_coordinator.free()

func _advance(msec: int) -> void:
	_now += msec
	_coordinator.poll()

func test_a_request_waits_for_the_debounce_after_the_latest_request() -> void:
	_coordinator.request(&"first")
	_advance(NpcSaveCoordinator.DEBOUNCE_MSEC - 500)
	_coordinator.request(&"second")
	_advance(NpcSaveCoordinator.DEBOUNCE_MSEC - 1)
	assert_eq(_coordinator.writes, 0, "A newer request restarts the debounce")
	assert_true(_coordinator.pending())
	_advance(1)
	assert_eq(_coordinator.writes, 1)
	assert_false(_coordinator.pending())
	assert_eq(_coordinator.last_reason, &"first")
	assert_true(FileAccess.file_exists(_coordinator.save_game.path))
	assert_eq(_coordinator.bytes_last, FileAccess.get_file_as_bytes(_coordinator.save_game.path).size())
	assert_eq(_coordinator.bytes_total, _coordinator.bytes_last)
	_advance(NpcSaveCoordinator.MAX_PENDING_MSEC)
	assert_eq(_coordinator.writes, 1, "Nothing pending, nothing written")

func test_steady_requests_never_leave_more_than_the_max_window_unsaved() -> void:
	_coordinator.request(&"steady")
	var waited: int = 0
	while _coordinator.writes == 0 and waited < NpcSaveCoordinator.MAX_PENDING_MSEC * 2:
		_advance(500)
		waited += 500
		_coordinator.request(&"steady")
	assert_eq(_coordinator.writes, 1)
	assert_eq(waited, NpcSaveCoordinator.MAX_PENDING_MSEC)

func test_a_critical_flush_writes_at_once_and_cancels_the_pending_write() -> void:
	_coordinator.request(&"ordinary")
	assert_true(_coordinator.flush(&"death"))
	assert_eq(_coordinator.writes, 1)
	assert_eq(_coordinator.last_reason, &"death")
	assert_false(_coordinator.pending())
	_advance(NpcSaveCoordinator.MAX_PENDING_MSEC)
	assert_eq(_coordinator.writes, 1, "The cancelled request is not written again")

func test_snapshot_hooks_run_once_before_every_write() -> void:
	var seen: Array[int] = []
	_coordinator.add_snapshot_hook(func() -> void: seen.append(_coordinator.writes))
	_coordinator.request(&"one")
	_advance(NpcSaveCoordinator.DEBOUNCE_MSEC)
	_coordinator.flush(&"two")
	assert_eq(_hook_calls, 2)
	assert_eq(seen, [0, 1], "Each hook ran before its write was counted")

func test_requests_made_by_a_hook_join_the_write_in_progress() -> void:
	_coordinator.add_snapshot_hook(func() -> void: _coordinator.request(&"from_hook"))
	assert_true(_coordinator.flush(&"checkpoint"))
	assert_false(_coordinator.pending())
	assert_eq(_coordinator.coalesced, 1)

func test_a_hundred_same_frame_requests_make_one_write() -> void:
	for index: int in 100:
		_coordinator.request(&"burst")
	_advance(NpcSaveCoordinator.DEBOUNCE_MSEC)
	_advance(NpcSaveCoordinator.MAX_PENDING_MSEC)
	assert_eq(_coordinator.writes, 1)
	assert_eq(_coordinator.requests, 100)
	assert_eq(_coordinator.coalesced, 99)
	assert_eq(_hook_calls, 1)

func test_a_failed_write_is_counted_reported_and_traced() -> void:
	_coordinator.save_game.path = OS.get_temp_dir().path_join("arcadia-missing-dir-%d/save.json" % OS.get_process_id())
	var trace := NpcDecisionTrace.new()
	var failed: Array = []
	_coordinator.write_failed.connect(func(reason: StringName, error: Error) -> void:
		failed.append([reason, error])
		trace.record(480.0, NpcDecisionTrace.SAVE_FAILURE, {"reason": "save_error:%d" % error}))
	_coordinator.request(&"ordinary")
	_advance(NpcSaveCoordinator.DEBOUNCE_MSEC)
	assert_eq(_coordinator.writes, 0)
	assert_eq(_coordinator.failures, 1)
	assert_ne(_coordinator.last_status, OK)
	assert_eq(failed.size(), 1)
	assert_eq(failed[0][0], &"ordinary")
	assert_eq(trace.latest(NpcDecisionTrace.SAVE_FAILURE).reason, "save_error:%d" % _coordinator.last_status)
	assert_false(_coordinator.flush(&"death"))
	assert_eq(_coordinator.failures, 2)
	var status: Dictionary = _coordinator.status()
	assert_eq(status.failures, 2)
	assert_eq(status.reason, "death")
