extends "res://game/actors/states/state.gd"

var enter_count: int = 0
var exit_count: int = 0
var physics_update_count: int = 0
var animation_finished_count: int = 0
var last_previous_state: Node
var last_enter_data: Dictionary = {}
var last_physics_delta: float = 0.0

func enter(previous_state: Node, data: Dictionary = {}) -> void:
	enter_count += 1
	last_previous_state = previous_state
	last_enter_data = data.duplicate()

func exit() -> void:
	exit_count += 1

func physics_update(delta: float) -> void:
	physics_update_count += 1
	last_physics_delta = delta

func animation_finished() -> void:
	animation_finished_count += 1
