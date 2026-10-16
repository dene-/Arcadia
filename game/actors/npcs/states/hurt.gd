extends "res://game/actors/npcs/states/npc_state.gd"

var _elapsed: float = 0.0

func enter(_previous_state: Node, _data: Dictionary = {}) -> void:
	var npc := get_npc()
	_elapsed = 0.0
	npc.set_hitbox_enabled(false)
	npc.play_animation(&"hurt", true, 1.0)
	npc.apply_action_velocity(true)

func physics_update(delta: float) -> void:
	var npc := get_npc()
	npc.apply_hurt_reaction(delta)
	_elapsed += delta
	if _elapsed >= npc.hurt_stun_time():
		_recover()

func animation_finished() -> void:
	_recover()

func _recover() -> void:
	var npc := get_npc()
	if npc.is_pending_death():
		npc.die()
		return
	npc.clear_hit_reaction()
	transition_to_default_state()
