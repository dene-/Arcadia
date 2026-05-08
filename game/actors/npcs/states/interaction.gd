extends "res://game/actors/npcs/states/npc_state.gd"

func enter(_previous_state: Node, _data: Dictionary = {}) -> void:
	var npc := get_npc()
	npc.set_hitbox_enabled(false)
	npc.clear_hit_reaction()
	npc.play_animation(&"idle", true, 1.0)
	npc.apply_velocity(Vector2.ZERO)

func physics_update(_delta: float) -> void:
	var npc := get_npc()
	npc.play_animation(&"idle", false, 1.0)
	npc.apply_velocity(Vector2.ZERO)