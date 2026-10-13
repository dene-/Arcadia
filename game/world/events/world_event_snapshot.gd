class_name WorldEventSnapshot
extends RefCounted

## Frozen value copy of a WorldEvent at publication. Holds ids, time, place and JSON-safe facts only,
## so freeing or moving an actor never changes it and no scene node crosses the cognition boundary.
var event_id: String = ""
var kind: StringName = &""
var minute: float = 0.0
var space_id: StringName = &""
var has_position: bool = false
var position: Vector2 = Vector2.ZERO
var subject_id: String = ""
var instigator_id: String = ""
var facts: Dictionary = {}

static func actor_id(actor: Variant) -> String:
	if not is_instance_valid(actor):
		return ""
	if actor is Node and (actor as Node).is_in_group(&"players"):
		return "player"
	if actor.has_method("get_npc_profile"):
		var profile: Variant = actor.call("get_npc_profile")
		if profile != null and profile.get("npc_id") != null:
			return String(profile.get("npc_id"))
	return ""

static func capture(event: WorldEvent, event_id: String, minute: float) -> WorldEventSnapshot:
	var snapshot := WorldEventSnapshot.new()
	snapshot.event_id = event_id
	snapshot.kind = event.kind
	snapshot.minute = minute
	snapshot.subject_id = actor_id(event.subject)
	snapshot.instigator_id = actor_id(event.instigator)
	if event.subject != null and is_instance_valid(event.subject):
		var space: Variant = event.subject.get("world_space")
		if space is StringName or space is String:
			snapshot.space_id = StringName(space)
		if event.subject is Node2D and (event.subject as Node2D).is_inside_tree():
			snapshot.position = (event.subject as Node2D).global_position
			snapshot.has_position = true
	for key: Variant in event.facts:
		if key is String and NpcMindState.is_json_safe(event.facts[key]):
			snapshot.facts[key] = _copy(event.facts[key])
	return snapshot

func to_data() -> Dictionary:
	return {"event_id": event_id, "kind": String(kind), "minute": minute,
		"space_id": String(space_id), "has_position": has_position,
		"position": {"x": position.x, "y": position.y}, "subject_id": subject_id,
		"instigator_id": instigator_id, "facts": facts.duplicate(true)}

static func _copy(value: Variant) -> Variant:
	if value is Array or value is Dictionary:
		return value.duplicate(true)
	return value
