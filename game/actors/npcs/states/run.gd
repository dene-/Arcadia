extends "res://game/actors/npcs/states/npc_state.gd"

func enter(_previous_state: Node, _data: Dictionary = {}) -> void:
	get_npc().play_animation(&"run", true, 1.25)

func physics_update(delta: float) -> void:
	var npc := get_npc()
	var enemy_transition := npc.update_enemy_ai(delta)
	if enemy_transition == &"attack":
		transition_to(&"attack")
		return
	if enemy_transition == &"idle":
		transition_to(&"idle")
		return

	if npc.npc_data.ai_enabled:
		var chase_direction := npc.get_enemy_chase_direction()
		if chase_direction == Vector2.ZERO:
			transition_to(&"idle")
			return
		npc.play_animation(&"run", false, 1.25)
		npc.apply_velocity(chase_direction * npc.current_run_speed())
		return

	var direction := npc.get_move_direction_to_target()
	if direction == Vector2.ZERO or npc.has_reached_patrol_target():
		transition_to(&"idle")
		return
	npc.play_animation(&"run", false, 1.25)
	npc.apply_velocity(direction * npc.current_run_speed())
