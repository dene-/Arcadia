class_name NpcSocialTask
extends NpcTask

## Keeps a resident in one conversation session (with another resident or the player).
## Its id is the brain's session owner, so the session's conversation claim and the task's
## claims share one owner and end together. Sessions are runtime-only and never restored.
## Params: session_id, partner_id, role ("initiator"|"partner") (Strings), priority (0..1).

const PHASE_APPROACH: String = "approach"
const PHASE_CONVERSE: String = "converse"
const PHASE_LEAVE: String = "leave"
const ROLES: Array[String] = ["initiator", "partner"]
const APPROACH_MINUTES: float = 1.0

func _init() -> void:
	kind = &"social"

static func owner_for(session_id: String) -> String:
	return "session:" + session_id

static func create(session_id: String, partner_id: String, role: String,
		tuning: NpcBehaviorTuning) -> NpcSocialTask:
	var task := NpcSocialTask.new()
	task.task_id = owner_for(session_id)
	task.priority = tuning.hold_priority
	task.params = {"session_id": session_id, "partner_id": partner_id, "role": role,
		"priority": task.priority}
	return task

func required_claims() -> Array[StringName]:
	return [&"locomotion", &"conversation"]

## The session's participants face each other and start talking.
func converse() -> void:
	if status == Status.RUNNING and phase == PHASE_APPROACH:
		phase = PHASE_CONVERSE

## Marks the session as winding down; its owner then ends the task.
func leave() -> void:
	if status == Status.RUNNING:
		phase = PHASE_LEAVE

func _on_start(context: NpcTaskContext) -> NpcTaskResult:
	progress = {}
	phase = PHASE_APPROACH
	context.call_service(&"cancel_travel", [task_id])
	return NpcTaskResult.running()

func _on_advance(context: NpcTaskContext, _minutes: float) -> NpcTaskResult:
	if phase == PHASE_APPROACH and context.minute - started_minute > APPROACH_MINUTES:
		return NpcTaskResult.failed(&"approach_timeout")
	return NpcTaskResult.running()

func _interrupt_response(interrupt: Interrupt) -> Response:
	if interrupt == Interrupt.SCHEDULE:
		return Response.CONTINUE
	return Response.CANCEL

func _revalidate(_context: NpcTaskContext) -> bool:
	return false

func _validate_params(value: Dictionary) -> bool:
	for key: String in ["session_id", "partner_id"]:
		if not value.get(key) is String or (value[key] as String).is_empty():
			return false
	if not value.get("role") in ROLES:
		return false
	var weight: Variant = value.get("priority")
	return (weight is float or weight is int) and is_finite(float(weight)) \
		and float(weight) >= 0.0 and float(weight) <= 1.0
