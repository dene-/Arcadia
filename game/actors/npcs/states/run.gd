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

	if npc.has_enemy_target():
		var chase_velocity := npc.get_enemy_chase_velocity(delta)
		if chase_velocity == Vector2.ZERO:
			transition_to(&"idle")
			return
		npc.play_animation(&"run", false, 1.25)
		npc.apply_velocity(chase_velocity)
		# Use the position we actually reached; a moving target may leave range again
		# before the next tick, producing endless side-by-side chasing otherwise.
		if npc.try_start_enemy_attack():
			transition_to(&"attack")
		return

	if npc.has_reached_patrol_target():
		transition_to(&"idle")
		return
	npc.play_animation(&"run", false, 1.25)
	npc.apply_velocity(npc.get_routine_velocity(delta, true))
