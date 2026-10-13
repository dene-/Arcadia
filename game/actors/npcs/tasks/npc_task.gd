class_name NpcTask
extends RefCounted

enum Status { CREATED, RUNNING, SUSPENDED, COMPLETED, CANCELLED, FAILED }
enum Interrupt { DEATH, HURT, DANGER, CONVERSATION, SCHEDULE, REPLACED }
enum Response { CONTINUE, SUSPEND, CANCEL }

var task_id: String = ""
var kind: StringName = &""
var phase: String = ""
var status: Status = Status.CREATED
var started_minute: float = 0.0
var deadline_minute: float = -1.0
var generation: int = 0
var evidence_ids: Array[String] = []
var commitment_ids: Array[String] = []
var params: Dictionary = {}
var progress: Dictionary = {}
# Runtime weight in 0..1 derived by subclasses from kind/params; not saved.
var priority: float = 0.5

static func status_name(value: Status) -> String:
	return Status.keys()[value] as String

static func interrupt_name(value: Interrupt) -> String:
	return (Interrupt.keys()[value] as String).to_lower()

func required_claims() -> Array[StringName]:
	return [&"locomotion"]

func is_terminal() -> bool:
	return status == Status.COMPLETED or status == Status.CANCELLED or status == Status.FAILED

func _on_start(_context: NpcTaskContext) -> NpcTaskResult:
	return NpcTaskResult.running()

func _on_advance(_context: NpcTaskContext, _minutes: float) -> NpcTaskResult:
	return NpcTaskResult.running()

func _on_suspend(_context: NpcTaskContext) -> void:
	pass

func _on_resume(_context: NpcTaskContext) -> NpcTaskResult:
	return NpcTaskResult.running()

func _on_cancel(_context: NpcTaskContext, _reason: StringName) -> void:
	pass

func _interrupt_response(interrupt: Interrupt) -> Response:
	match interrupt:
		Interrupt.DEATH:
			return Response.CANCEL
		Interrupt.SCHEDULE:
			return Response.CONTINUE
		_:
			return Response.SUSPEND

func _validate_params(_params: Dictionary) -> bool:
	return true

# Called when a saved task is restored; false cancels it with reason restore_invalid.
func _revalidate(_context: NpcTaskContext) -> bool:
	return true

# `claims` lists the claims the task requires; the controller nests `suspended`.
func checkpoint() -> Dictionary:
	var claims: Array[String] = []
	for claim: StringName in required_claims():
		claims.append(String(claim))
	return {"task_id": task_id, "kind": String(kind), "phase": phase,
		"status": status_name(status), "started_minute": started_minute,
		"deadline_minute": deadline_minute, "generation": generation,
		"evidence_ids": evidence_ids.duplicate(), "commitment_ids": commitment_ids.duplicate(),
		"claims": claims, "params": params.duplicate(true), "progress": progress.duplicate(true),
		"suspended": {}}

func restore_from(saved: Dictionary) -> bool:
	if not NpcMindState.is_valid_task_checkpoint(saved):
		return false
	var saved_kind := StringName(saved["kind"] as String)
	if not kind.is_empty() and kind != saved_kind:
		return false
	var saved_status: int = Status.keys().find(saved["status"] as String)
	if saved_status < 0:
		return false
	var saved_params: Dictionary = (saved["params"] as Dictionary).duplicate(true)
	if not _validate_params(saved_params):
		return false
	task_id = saved["task_id"] as String
	kind = saved_kind
	phase = saved["phase"] as String
	status = saved_status as Status
	started_minute = float(saved["started_minute"])
	deadline_minute = float(saved["deadline_minute"])
	generation = int(saved["generation"])
	evidence_ids.assign(saved["evidence_ids"])
	commitment_ids.assign(saved["commitment_ids"])
	params = saved_params
	progress = (saved["progress"] as Dictionary).duplicate(true)
	return true
