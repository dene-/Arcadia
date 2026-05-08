class_name NpcState
extends "res://game/actors/states/state.gd"

func get_npc() -> BaseNpc:
	return actor as BaseNpc

## Default animation_finished: returns to idle.
## Override in states that need custom behavior (hurt, dead).
func animation_finished() -> void:
	transition_to_default_state()

func transition_to_default_state() -> void:
	transition_to(&"idle")