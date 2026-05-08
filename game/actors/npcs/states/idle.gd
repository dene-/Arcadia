extends "res://game/actors/npcs/states/npc_state.gd"

func enter(_previous_state: Node, _data: Dictionary = {}) -> void:
	var npc := get_npc()
	npc.state_time_remaining = npc.choose_idle_duration()
	npc.play_animation(&"idle", true, 1.0)
	npc.apply_velocity(Vector2.ZERO)

func physics_update(delta: float) -> void:
	var npc := get_npc()
	var enemy_transition := npc.update_enemy_ai(delta)
	if not enemy_transition.is_empty() and enemy_transition != &"idle":
		transition_to(enemy_transition)
		return

	npc.play_animation(&"idle", false, 1.0)
	npc.apply_velocity(Vector2.ZERO)
	npc.state_time_remaining -= delta
	if npc.state_time_remaining > 0.0:
		return
	if not npc.choose_next_patrol_target():
		npc.state_time_remaining = npc.choose_idle_duration()
		return
	transition_to(npc.choose_roam_state())
