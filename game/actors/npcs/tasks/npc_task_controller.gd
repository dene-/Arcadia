class_name NpcTaskController
extends RefCounted

signal transitioned(entry: Dictionary)
signal claim_revoked(claim: StringName, old_owner: String)

const MAX_TRANSITIONS: int = 64
# Tasks at or above this priority take claims from sessions instead of waiting for them.
const URGENT_PRIORITY: float = 0.9

var current: NpcTask
var suspended: NpcTask
var generation: int = 0

var _claims: Dictionary = {}
var _kinds: Dictionary = {}
var _transitions: Array[Dictionary] = []
var _blocked_reason: StringName = &""

func transitions() -> Array[Dictionary]:
	return _transitions.duplicate(true)

func register_kind(kind: StringName, script: Script) -> void:
	_kinds[kind] = script

# --- Claims ---

func claim_owner(claim: StringName) -> String:
	return _claims.get(claim, "") as String

func acquire_claim(claim: StringName, owner_id: String) -> bool:
	if owner_id.is_empty():
		return false
	var owner: String = claim_owner(claim)
	if not owner.is_empty() and owner != owner_id:
		return false
	_claims[claim] = owner_id
	return true

func release_claim(claim: StringName, owner_id: String) -> bool:
	if owner_id.is_empty() or claim_owner(claim) != owner_id:
		return false
	_claims.erase(claim)
	return true

# --- Lifecycle ---

func start(task: NpcTask, context: NpcTaskContext) -> bool:
	if task == null or context == null or task.status != NpcTask.Status.CREATED:
		return false
	if task.task_id.is_empty() or task.kind.is_empty() or _is_live_id(task.task_id):
		return false
	if not task._validate_params(task.params) or not _is_storable(task, context):
		return false
	var response: NpcTask.Response = NpcTask.Response.SUSPEND
	if current != null:
		if task.priority < current.priority:
			return false
		response = current._interrupt_response(NpcTask.Interrupt.REPLACED)
		if response == NpcTask.Response.CONTINUE:
			return false
	var displaced_owner: String = current.task_id if current != null else ""
	if task.priority < URGENT_PRIORITY and not _claims_free(task, displaced_owner):
		return false
	if current != null:
		if response == NpcTask.Response.SUSPEND:
			_suspend_current(context, &"replaced")
		else:
			_end(current, NpcTask.Status.CANCELLED, &"replaced", context, true, false)
	_revoke_blockers(task)
	_acquire_required(task)
	generation += 1
	task.generation = generation
	task.started_minute = context.minute
	task.status = NpcTask.Status.RUNNING
	current = task
	_blocked_reason = &""
	_record(task, NpcTask.Status.CREATED, NpcTask.Status.RUNNING, &"started", context.minute)
	_apply_result(task, task._on_start(context), context)
	return true

func advance(context: NpcTaskContext, minutes: float) -> void:
	if current == null:
		return
	var task: NpcTask = current
	if task.deadline_minute >= 0.0 and context.minute > task.deadline_minute:
		_end(task, NpcTask.Status.FAILED, &"deadline", context, true, true)
		return
	_apply_result(task, task._on_advance(context, minutes), context)

# Resumes the suspended task when no task is current and its claims are free.
func resume(context: NpcTaskContext) -> bool:
	return _resume_suspended(context)

func interrupt(kind: NpcTask.Interrupt, context: NpcTaskContext) -> void:
	if kind == NpcTask.Interrupt.DEATH:
		_cancel_all(context)
		return
	if current == null:
		return
	match current._interrupt_response(kind):
		NpcTask.Response.SUSPEND:
			_suspend_current(context, StringName(NpcTask.interrupt_name(kind)))
		NpcTask.Response.CANCEL:
			_end(current, NpcTask.Status.CANCELLED, StringName(NpcTask.interrupt_name(kind)),
				context, true, false)

func cancel(task_id: String, reason: StringName, context: NpcTaskContext) -> bool:
	var task: NpcTask = _live_task(task_id)
	if task == null:
		return false
	_end(task, NpcTask.Status.CANCELLED, reason, context, true, true)
	return true

# External completion notice; only the current task at the same generation accepts it.
func finish(task_id: String, task_generation: int, result: NpcTaskResult,
		context: NpcTaskContext) -> bool:
	if current == null or result == null or current.task_id != task_id \
			or current.generation != task_generation:
		return false
	match result.status:
		NpcTaskResult.Status.COMPLETED:
			_end(current, NpcTask.Status.COMPLETED, result.reason, context, false, true)
		NpcTaskResult.Status.FAILED:
			_end(current, NpcTask.Status.FAILED, result.reason, context, false, true)
		_:
			return false
	return true

# --- Persistence ---

# When only a suspended task exists it is the top-level entry (status SUSPENDED).
func checkpoint() -> Dictionary:
	if current != null:
		var saved: Dictionary = current.checkpoint()
		if suspended != null:
			saved["suspended"] = suspended.checkpoint()
		return saved
	if suspended != null:
		return suspended.checkpoint()
	return {}

func restore(saved: Dictionary, context: NpcTaskContext) -> bool:
	if current != null or suspended != null:
		return false
	if saved.is_empty():
		return true
	if not NpcMindState.is_valid_task_checkpoint(saved):
		return false
	var nested: Dictionary = saved["suspended"]
	var top_status: String = saved["status"] as String
	var restored_current: NpcTask = null
	var restored_suspended: NpcTask = null
	if top_status == NpcTask.status_name(NpcTask.Status.RUNNING):
		restored_current = _restore_task(saved, context)
	elif top_status == NpcTask.status_name(NpcTask.Status.SUSPENDED) and nested.is_empty():
		restored_suspended = _restore_task(saved, context)
	else:
		_record_raw(saved["task_id"] as String, saved["kind"] as String, top_status,
			NpcTask.status_name(NpcTask.Status.CANCELLED), &"restore_invalid", context.minute)
	if not nested.is_empty():
		if (nested["status"] as String) == NpcTask.status_name(NpcTask.Status.SUSPENDED):
			restored_suspended = _restore_task(nested, context)
		else:
			_record_raw(nested["task_id"] as String, nested["kind"] as String,
				nested["status"] as String, NpcTask.status_name(NpcTask.Status.CANCELLED),
				&"restore_invalid", context.minute)
	if restored_suspended != null:
		restored_suspended.status = NpcTask.Status.SUSPENDED
		suspended = restored_suspended
		generation = maxi(generation, restored_suspended.generation)
	if restored_current != null:
		generation = maxi(generation, restored_current.generation)
		if not _claims_free(restored_current, ""):
			_record(restored_current, NpcTask.Status.RUNNING, NpcTask.Status.CANCELLED,
				&"claims_unavailable", context.minute)
			return false
		_acquire_required(restored_current)
		restored_current.status = NpcTask.Status.RUNNING
		current = restored_current
		_blocked_reason = &""
		_record(restored_current, NpcTask.Status.CREATED, NpcTask.Status.RUNNING, &"restored",
			context.minute)
		_apply_result(restored_current, restored_current._on_resume(context), context)
	return current != null or suspended != null

# --- Internals ---

func _restore_task(saved: Dictionary, context: NpcTaskContext) -> NpcTask:
	var script: Script = _kinds.get(StringName(saved["kind"] as String)) as Script
	var task: NpcTask = null
	if script is GDScript:
		task = (script as GDScript).new() as NpcTask
	if task == null or not task.restore_from(saved) or not task._revalidate(context):
		_record_raw(saved["task_id"] as String, saved["kind"] as String, saved["status"] as String,
			NpcTask.status_name(NpcTask.Status.CANCELLED), &"restore_invalid", context.minute)
		return null
	return task

func _is_live_id(task_id: String) -> bool:
	return _live_task(task_id) != null

func _live_task(task_id: String) -> NpcTask:
	if current != null and current.task_id == task_id:
		return current
	if suspended != null and suspended.task_id == task_id:
		return suspended
	return null

func _is_storable(task: NpcTask, context: NpcTaskContext) -> bool:
	var data: Dictionary = task.checkpoint()
	data["started_minute"] = context.minute
	data["status"] = NpcTask.status_name(NpcTask.Status.RUNNING)
	return NpcMindState.is_valid_task_checkpoint(data)

# True when every required claim is free or owned by the task or by `released_owner`.
func _claims_free(task: NpcTask, released_owner: String) -> bool:
	for claim: StringName in task.required_claims():
		var owner: String = claim_owner(claim)
		if not owner.is_empty() and owner != task.task_id and owner != released_owner:
			return false
	return true

func _acquire_required(task: NpcTask) -> void:
	for claim: StringName in task.required_claims():
		_claims[claim] = task.task_id

# A revoked session loses every claim it holds so it can wind down as a whole.
func _revoke_blockers(task: NpcTask) -> void:
	for claim: StringName in task.required_claims():
		var owner: String = claim_owner(claim)
		if not owner.is_empty() and owner != task.task_id:
			_revoke_owner(owner)

func _revoke_owner(owner: String) -> void:
	for claim: StringName in _claims.keys():
		if _claims[claim] == owner:
			_claims.erase(claim)
			claim_revoked.emit(claim, owner)

func _release_owned(owner: String) -> void:
	for claim: StringName in _claims.keys():
		if _claims[claim] == owner:
			_claims.erase(claim)

func _cancel_all(context: NpcTaskContext) -> void:
	if current != null:
		_end(current, NpcTask.Status.CANCELLED, &"death", context, true, false)
	if suspended != null:
		_end(suspended, NpcTask.Status.CANCELLED, &"death", context, true, false)
	for claim: StringName in _claims.keys():
		var owner: String = _claims[claim]
		_claims.erase(claim)
		claim_revoked.emit(claim, owner)

func _suspend_current(context: NpcTaskContext, reason: StringName) -> void:
	var task: NpcTask = current
	if suspended != null:
		_end(suspended, NpcTask.Status.CANCELLED, &"displaced", context, true, false)
	task._on_suspend(context)
	task.status = NpcTask.Status.SUSPENDED
	_release_owned(task.task_id)
	current = null
	suspended = task
	_blocked_reason = &""
	_record(task, NpcTask.Status.RUNNING, NpcTask.Status.SUSPENDED, reason, context.minute)

func _resume_suspended(context: NpcTaskContext) -> bool:
	if suspended == null or current != null:
		return false
	var task: NpcTask = suspended
	if not task._revalidate(context):
		_end(task, NpcTask.Status.CANCELLED, &"invalid_on_resume", context, true, false)
		return false
	if not _claims_free(task, ""):
		return false
	_acquire_required(task)
	suspended = null
	current = task
	task.status = NpcTask.Status.RUNNING
	_blocked_reason = &""
	_record(task, NpcTask.Status.SUSPENDED, NpcTask.Status.RUNNING, &"resumed", context.minute)
	_apply_result(task, task._on_resume(context), context)
	return true

# Moves a live task to a terminal status, releasing its claims. `notify` runs _on_cancel;
# `resume` then resumes the suspended task when the ended task was current.
func _end(task: NpcTask, to: NpcTask.Status, reason: StringName, context: NpcTaskContext,
		notify: bool, resume_after: bool) -> void:
	var was_current: bool = task == current
	if notify:
		task._on_cancel(context, reason)
	var from: NpcTask.Status = task.status
	task.status = to
	_release_owned(task.task_id)
	if was_current:
		current = null
		_blocked_reason = &""
	elif task == suspended:
		suspended = null
	_record(task, from, to, reason, context.minute)
	if resume_after and was_current:
		_resume_suspended(context)

func _apply_result(task: NpcTask, result: NpcTaskResult, context: NpcTaskContext) -> void:
	if task != current:
		return
	if result == null:
		_blocked_reason = &""
		return
	match result.status:
		NpcTaskResult.Status.COMPLETED:
			_end(task, NpcTask.Status.COMPLETED, result.reason, context, false, true)
		NpcTaskResult.Status.FAILED:
			_end(task, NpcTask.Status.FAILED, result.reason, context, false, true)
		NpcTaskResult.Status.BLOCKED:
			if task.deadline_minute >= 0.0 and result.retry_after_minute > task.deadline_minute:
				_end(task, NpcTask.Status.FAILED, &"deadline", context, true, true)
			elif result.reason != _blocked_reason:
				_blocked_reason = result.reason
				_record(task, NpcTask.Status.RUNNING, NpcTask.Status.RUNNING, result.reason,
					context.minute)
		_:
			_blocked_reason = &""

func _record(task: NpcTask, from: NpcTask.Status, to: NpcTask.Status, reason: StringName,
		minute: float) -> void:
	_record_raw(task.task_id, String(task.kind), NpcTask.status_name(from),
		NpcTask.status_name(to), reason, minute)

func _record_raw(task_id: String, kind: String, from: String, to: String, reason: StringName,
		minute: float) -> void:
	var entry: Dictionary = {"minute": minute, "task_id": task_id, "kind": kind, "from": from,
		"to": to, "reason": String(reason)}
	_transitions.append(entry)
	if _transitions.size() > MAX_TRANSITIONS:
		_transitions.pop_front()
	transitioned.emit(entry.duplicate())
