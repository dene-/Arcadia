class_name StateMachine
extends Node

## Lightweight reusable state machine that delegates behavior to child State nodes.

signal transitioned(current_state: StringName, previous_state: StringName)

## State name to enter when the machine is initialized.
@export var initial_state: StringName = &""

var actor: Node
var current_state: Node

var _current_state_name: StringName = &""
var _states: Dictionary = {}

func initialize(next_actor: Node) -> void:
	actor = next_actor
	_states.clear()
	current_state = null
	_current_state_name = &""

	for child: Node in get_children():
		var state := child

		state.machine = self
		state.actor = actor
		_states[state.get_state_name()] = state

		if initial_state.is_empty():
			initial_state = state.get_state_name()

	assert(not initial_state.is_empty(), "StateMachine requires an initial state.")
	assert(_states.has(initial_state), "Missing initial state: %s" % initial_state)
	transition_to(initial_state, {}, true)

func transition_to(next_state: StringName, data: Dictionary = {}, force_restart: bool = false) -> void:
	assert(_states.has(next_state), "Unknown state: %s" % next_state)

	if not force_restart and current_state != null and next_state == _current_state_name:
		return

	var previous_state: Node = current_state
	var previous_state_name: StringName = _current_state_name

	if current_state != null:
		current_state.exit()

	current_state = _states[next_state]
	_current_state_name = next_state
	current_state.enter(previous_state, data)
	transitioned.emit(_current_state_name, previous_state_name)

func physics_update(delta: float) -> void:
	if current_state == null:
		return

	current_state.physics_update(delta)

func animation_finished() -> void:
	if current_state == null:
		return

	current_state.animation_finished()

func is_in_state(state_name: StringName) -> bool:
	return _current_state_name == state_name

func get_current_state_name() -> StringName:
	return _current_state_name
