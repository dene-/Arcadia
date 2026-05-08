extends "res://game/actors/player/states/player_state.gd"

func enter(_previous_state: Node, _data: Dictionary = {}) -> void:
	var player := get_player()
	player.reset_attack_hold()
	player.reset_attack_damage_override()
	player.set_hitbox_enabled(true)
	player.play_animation(&"attack", true, 1.0)
	player.apply_action_velocity(false)

func exit() -> void:
	_exit_attack_cleanup()
