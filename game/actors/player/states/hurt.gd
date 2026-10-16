extends "res://game/actors/player/states/player_state.gd"

## The stagger ends before the hurt animation does; the player keeps blinking and untouchable.
var _elapsed: float = 0.0

func enter(_previous_state: Node, _data: Dictionary = {}) -> void:
	var player := get_player()
	_elapsed = 0.0
	player.set_hitbox_enabled(false)
	player.play_animation(&"hurt", true, 1.0)

func physics_update(delta: float) -> void:
	var player := get_player()
	player.apply_hurt_reaction(delta)
	_elapsed += delta
	if _elapsed >= player.hurt_stun_time():
		transition_to_default_state()
