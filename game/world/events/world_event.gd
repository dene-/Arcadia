class_name WorldEvent
extends RefCounted

## Transient world facts. Perception runs synchronously before asynchronous cognition.
## Only an observer's filtered description is persisted or sent to a model.
var kind: StringName
var subject: BaseActor
var instigator: BaseActor
var facts: Dictionary = {}

static func damage(victim: BaseActor, attacker: BaseActor) -> WorldEvent:
	var event := WorldEvent.new()
	event.kind = &"actor_died" if victim.health <= 0 else &"actor_hurt"
	event.subject = victim
	event.instigator = attacker
	event.facts = {"health_remaining": victim.health, "max_health": victim.max_health}
	return event
