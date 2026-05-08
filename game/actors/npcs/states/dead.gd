extends "res://game/actors/npcs/states/npc_state.gd"

func enter(_previous_state: Node, _data: Dictionary = {}) -> void:
	var npc := get_npc()
	npc.set_hitbox_enabled(false)
	npc.play_animation(&"die", true, 1.0)
	npc.apply_velocity(Vector2.ZERO)

func physics_update(_delta: float) -> void:
	get_npc().apply_velocity(Vector2.ZERO)

func animation_finished() -> void:
	get_npc().queue_free()