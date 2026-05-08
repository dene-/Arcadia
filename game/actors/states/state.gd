class_name State
extends Node

## Reusable node state for actors controlled by a StateMachine.

var machine: Node
var actor: Node

func get_state_name() -> StringName:
	return StringName(String(name).to_snake_case())

func transition_to(next_state: StringName, data: Dictionary = {}) -> void:
	machine.transition_to(next_state, data)

func enter(_previous_state: Node, _data: Dictionary = {}) -> void:
	pass

func exit() -> void:
	pass

func physics_update(_delta: float) -> void:
	pass

func animation_finished() -> void:
	pass