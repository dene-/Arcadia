extends "res://game/actors/player/states/player_state.gd"

func enter(_previous_state: Node, _data: Dictionary = {}) -> void:
	var player := get_player()
	player.reset_attack_hold()
	player.set_hitbox_enabled(false)
	player.play_animation(&"hurt", true, 1.0)
	player.apply_action_velocity(false)