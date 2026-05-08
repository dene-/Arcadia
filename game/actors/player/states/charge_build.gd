extends "res://game/actors/player/states/player_state.gd"

func enter(_previous_state: Node, _data: Dictionary = {}) -> void:
	var player := get_player()
	player.reset_attack_hold()
	player.play_animation(&"charge_build", true, 1.0)
	player.apply_action_velocity(false)

func animation_finished() -> void:
	var player := get_player()
	if player.is_attack_held():
		transition_to(&"charge_loop")
		return
	transition_to(&"charge_attack")
