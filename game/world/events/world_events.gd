extends Node

## Producers publish facts; subscribers own perception, persistence and presentation.
signal occurred(event: WorldEvent)

func publish(event: WorldEvent) -> void:
	assert(event != null and not event.kind.is_empty(), "World events need a kind.")
	occurred.emit(event)
