extends "res://game/actors/npcs/states/npc_state.gd"

## The swing is telegraphed: the hit box turns on only once the wind-up has elapsed.
var _windup_remaining: float = 0.0

func enter(_previous_state: Node, _data: Dictionary = {}) -> void:
	var npc := get_npc()
	_windup_remaining = npc.attack_windup_time()
	npc.set_hitbox_enabled(_windup_remaining <= 0.0)
	npc.play_animation(&"attack", true, 1.0)
	npc.apply_action_velocity(true)

func exit() -> void:
	get_npc().set_hitbox_enabled(false)

func physics_update(delta: float) -> void:
	var npc := get_npc()
	npc.apply_action_velocity(true)
	if _windup_remaining <= 0.0:
		return
	_windup_remaining -= delta
	if _windup_remaining <= 0.0:
		npc.set_hitbox_enabled(true)
