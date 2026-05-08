extends "res://game/actors/npcs/states/npc_state.gd"

func enter(_previous_state: Node, _data: Dictionary = {}) -> void:
	get_npc().play_animation(&"walk", true, 1.0)

func physics_update(delta: float) -> void:
	var npc := get_npc()
	var enemy_transition := npc.update_enemy_ai(delta)
	if enemy_transition == &"attack" or enemy_transition == &"run":
		transition_to(enemy_transition)
		return

	var direction := npc.get_move_direction_to_target()
	if direction == Vector2.ZERO or npc.has_reached_patrol_target():
		transition_to(&"idle")
		return
	npc.play_animation(&"walk", false, 1.0)
	npc.apply_velocity(direction * npc.current_walk_speed())
