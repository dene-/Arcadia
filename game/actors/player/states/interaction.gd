extends "res://game/actors/player/states/player_state.gd"

func enter(_previous_state: Node, _data: Dictionary = {}) -> void:
	var player := get_player()
	player.reset_attack_hold()
	player.set_hitbox_enabled(false)
	player.play_animation(&"idle", true, 1.0)
	player.apply_velocity(Vector2.ZERO)

func physics_update(_delta: float) -> void:
	var player := get_player()
	player.play_animation(&"idle", false, 1.0)
	player.apply_velocity(Vector2.ZERO)