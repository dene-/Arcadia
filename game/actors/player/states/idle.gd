extends "res://game/actors/player/states/player_state.gd"

func enter(_previous_state: Node, _data: Dictionary = {}) -> void:
	var player := get_player()
	player.play_animation(&"idle", true, 1.0)
	player.apply_velocity(Vector2.ZERO)

func physics_update(delta: float) -> void:
	var player := get_player()
	player.read_move_input()
	if handle_ground_actions(delta):
		return
	if player.has_move_input():
		transition_to(&"walk")
		return
	player.play_animation(&"idle", false, 1.0)
	player.apply_velocity(Vector2.ZERO)
