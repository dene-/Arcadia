class_name NpcPerceptionRouter
extends RefCounted

## Add an event-specific perception adapter here without changing dialogue or the queue.
var _handlers: Dictionary[StringName, Callable] = {}

func _init() -> void:
	register(&"actor_hurt", _combat)
	register(&"actor_died", _combat)

func register(kind: StringName, handler: Callable) -> void:
	_handlers[kind] = handler

func perceive(observer: BaseNpc, event: WorldEvent) -> Dictionary:
	if not _handlers.has(event.kind):
		return {}
	return _handlers[event.kind].call(observer, event)

func _combat(observer: BaseNpc, event: WorldEvent) -> Dictionary:
	var perceived: Dictionary = NpcPerception.observe(observer, event.subject,
		event.instigator, event.kind == &"actor_died")
	if perceived.is_empty():
		return {}
	# Unseen deaths and identities must never leak into the model's metadata.
	perceived.kind = String(event.kind) if perceived.sense != "hearing" else "combat_noise"
	perceived.directly_affected = observer == event.subject
	perceived.topics = (["combat", "injury" if event.kind == &"actor_hurt" else "death"]
		if perceived.sense != "hearing" else ["combat"])
	if observer == event.subject:
		perceived.health_remaining = event.facts.health_remaining
		perceived.max_health = event.facts.max_health
	return perceived
