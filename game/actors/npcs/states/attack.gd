extends "res://game/actors/npcs/states/npc_state.gd"

func enter(_previous_state: Node, _data: Dictionary = {}) -> void:
	var npc := get_npc()
	npc.set_hitbox_enabled(true)
	npc.play_animation(&"attack", true, 1.0)
	npc.apply_action_velocity(true)

func exit() -> void:
	get_npc().set_hitbox_enabled(false)

func physics_update(_delta: float) -> void:
	get_npc().apply_action_velocity(true)