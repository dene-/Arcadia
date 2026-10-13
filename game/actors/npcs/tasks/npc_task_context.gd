class_name NpcTaskContext
extends RefCounted

const MAX_ERRORS: int = 32

var npc_id: String = ""
var minute: float = 0.0
var mind: NpcMindState
var actor: Object
var services: Dictionary = {}
var random: RandomNumberGenerator
var errors: Array[String] = []

# A service is a Callable, or an Object exposing a method with the service's name.
func has_service(service: StringName) -> bool:
	var entry: Variant = _lookup(service)
	if entry is Callable:
		return (entry as Callable).is_valid()
	if entry is Object and is_instance_valid(entry):
		return (entry as Object).has_method(service)
	return false

func call_service(service: StringName, args: Array = []) -> Variant:
	if not has_service(service):
		errors.append("missing_service:%s" % String(service))
		if errors.size() > MAX_ERRORS:
			errors.pop_front()
		return null
	var entry: Variant = _lookup(service)
	if entry is Callable:
		return (entry as Callable).callv(args)
	return (entry as Object).callv(service, args)

func _lookup(service: StringName) -> Variant:
	if services.has(service):
		return services[service]
	return services.get(String(service))
