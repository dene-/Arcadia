extends "res://game/actors/player/states/player_state.gd"

func enter(_previous_state: Node, _data: Dictionary = {}) -> void:
	var player := get_player()
	player.reset_attack_damage_override()
	player.set_hitbox_enabled(true)
	player.play_animation(&"attack", true, 1.0)
	player.apply_action_velocity(false)

func exit() -> void:
	_exit_attack_cleanup()

## A press remembered during the swing chains the next one; still holding turns it into a charge.
func animation_finished() -> void:
	var player := get_player()
	if not player.consume_attack_transition().is_empty():
		machine.transition_to(&"attack", {}, true)
	elif player.is_attack_held():
		transition_to(&"charge_build")
	else:
		transition_to_default_state()
