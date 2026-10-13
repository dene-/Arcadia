class_name NpcTaskResult
extends RefCounted

enum Status { RUNNING, COMPLETED, BLOCKED, FAILED }

var status: Status = Status.RUNNING
var reason: StringName = &""
var retry_after_minute: float = -1.0

static func running() -> NpcTaskResult:
	return NpcTaskResult.new()

static func completed(code: StringName = &"done") -> NpcTaskResult:
	var result := NpcTaskResult.new()
	result.status = Status.COMPLETED
	result.reason = code
	return result

static func blocked(code: StringName, retry_after: float = -1.0) -> NpcTaskResult:
	var result := NpcTaskResult.new()
	result.status = Status.BLOCKED
	result.reason = code
	result.retry_after_minute = retry_after
	return result

static func failed(code: StringName) -> NpcTaskResult:
	var result := NpcTaskResult.new()
	result.status = Status.FAILED
	result.reason = code
	return result
