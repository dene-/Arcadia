extends "res://game/actors/npcs/states/npc_state.gd"

func enter(_previous_state: Node, _data: Dictionary = {}) -> void:
	var npc := get_npc()
	npc.set_hitbox_enabled(false)
	npc.play_animation(&"hurt", true, 1.0)
	npc.apply_action_velocity(true)

func physics_update(_delta: float) -> void:
	get_npc().apply_hurt_reaction(_delta)

func animation_finished() -> void:
	var npc := get_npc()
	if npc.is_pending_death():
		npc.die()
		return
	npc.clear_hit_reaction()
	transition_to_default_state()