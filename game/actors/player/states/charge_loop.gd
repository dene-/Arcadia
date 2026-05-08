extends "res://game/actors/player/states/player_state.gd"

func enter(_previous_state: Node, _data: Dictionary = {}) -> void:
	var player := get_player()
	player.play_animation(&"charge_loop", true, 1.0)
	player.apply_action_velocity(false)

func physics_update(_delta: float) -> void:
	var player := get_player()
	player.read_move_input()
	if not player.is_attack_held():
		transition_to(&"charge_attack")
		return
	player.apply_action_velocity(false)
