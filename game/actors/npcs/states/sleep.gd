extends "res://game/actors/npcs/states/npc_state.gd"

func enter(_previous_state: Node, _data: Dictionary = {}) -> void:
	get_npc().show_sleep_pose(true)

func exit() -> void:
	get_npc().show_sleep_pose(false)

func physics_update(_delta: float) -> void:
	get_npc().apply_velocity(Vector2.ZERO)

func animation_finished() -> void:
	pass
