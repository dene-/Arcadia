class_name NpcHoldTask
extends NpcTask

## Temporary adapter that keeps a resident still for an external owner until it ends the task.
## Params: owner, reason (Strings), priority (0..1).

const PHASE_HOLD: String = "hold"

func _init() -> void:
	kind = &"hold"

static func create(task_params: Dictionary, id: String = "") -> NpcHoldTask:
	var task := NpcHoldTask.new()
	task.task_id = id
	task.params = task_params.duplicate(true)
	task.priority = float(task.params.get("priority", 0.0))
	return task

func _on_start(context: NpcTaskContext) -> NpcTaskResult:
	phase = PHASE_HOLD
	context.call_service(&"cancel_travel", [task_id])
	return NpcTaskResult.running()

func _interrupt_response(interrupt: Interrupt) -> Response:
	match interrupt:
		Interrupt.CONVERSATION, Interrupt.SCHEDULE:
			return Response.CONTINUE
	return Response.CANCEL

# Holds never suspend, so revalidation only happens on restore; the owning session is not saved.
func _revalidate(_context: NpcTaskContext) -> bool:
	return false

func _validate_params(value: Dictionary) -> bool:
	for key: String in ["owner", "reason"]:
		if not value.get(key) is String:
			return false
	var weight: Variant = value.get("priority")
	return (weight is float or weight is int) and is_finite(float(weight)) \
		and float(weight) >= 0.0 and float(weight) <= 1.0
