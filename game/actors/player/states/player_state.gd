class_name PlayerState
extends "res://game/actors/states/state.gd"

func get_player() -> Node:
	return actor

## Default physics_update: reads movement input and applies action velocity.
## Override in states that need different behavior (idle, walk, dead, interaction, charge_loop).
func physics_update(_delta: float) -> void:
	var player := get_player()
	player.read_move_input()
	player.apply_action_velocity(false)

## Default animation_finished: returns to idle or walk.
## Override in states that need custom behavior (dead, charge_build, charge_loop).
func animation_finished() -> void:
	transition_to_default_state()

func handle_ground_actions(delta: float) -> bool:
	var player := get_player()
	if player.is_input_blocked():
		player.reset_attack_hold()
		return false

	var attack_state: StringName = player.consume_attack_transition(delta)
	if not attack_state.is_empty():
		transition_to(attack_state)
		return true

	if player.is_jump_just_pressed():
		player.reset_attack_hold()
		transition_to(&"jump")
		return true

	return false

func transition_to_default_state() -> void:
	var player := get_player()

	player.read_move_input()
	if player.has_move_input():
		transition_to(&"walk")
		return

	transition_to(&"idle")

func _exit_attack_cleanup() -> void:
	var player := get_player()
	player.set_hitbox_enabled(false)
	player.reset_attack_damage_override()
