extends "res://game/actors/player/states/player_state.gd"

func enter(_previous_state: Node, _data: Dictionary = {}) -> void:
	var player := get_player()
	player.play_animation(&"walk", true, player.current_walk_animation_speed())

func physics_update(delta: float) -> void:
	var player := get_player()
	player.read_move_input()
	if handle_ground_actions(delta):
		return
	if not player.has_move_input():
		transition_to(&"idle")
		return
	player.set_facing_from_move_input()
	player.play_animation(&"walk", false, player.current_walk_animation_speed())
	player.apply_velocity(player.move_input * player.current_move_speed())
