extends "res://tests/test_case.gd"

const StateMachineResource = preload("res://game/actors/states/state_machine.gd")
const TestStateResource = preload("res://tests/fixtures/test_state.gd")

var _transitions: Array[Dictionary] = []
var _nodes: Array[Node] = []

func before_each() -> void:
	_transitions.clear()

func after_each() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()

func test_initialize_uses_first_child_when_initial_state_is_empty() -> void:
	var machine := _make_machine()
	var idle := _make_state("Idle")
	var walk := _make_state("Walk")
	machine.add_child(idle)
	machine.add_child(walk)

	machine.initialize(_make_actor())

	assert_eq(machine.get_current_state_name(), &"idle")
	assert_eq(machine.current_state, idle)
	assert_eq(idle.enter_count, 1)
	assert_eq(walk.enter_count, 0)

func test_initialize_uses_configured_initial_state() -> void:
	var machine := _make_machine()
	var idle := _make_state("Idle")
	var walk := _make_state("Walk")
	machine.initial_state = &"walk"
	machine.add_child(idle)
	machine.add_child(walk)

	machine.initialize(_make_actor())

	assert_eq(machine.get_current_state_name(), &"walk")
	assert_eq(machine.current_state, walk)
	assert_eq(walk.enter_count, 1)

func test_transition_emits_current_and_previous_state_names() -> void:
	var machine := _make_initialized_machine()
	machine.transitioned.connect(_record_transition)

	machine.transition_to(&"walk", {"speed": 2})

	assert_eq(_transitions.size(), 1)
	assert_eq(_transitions[0]["current"], &"walk")
	assert_eq(_transitions[0]["previous"], &"idle")

func test_duplicate_transition_to_current_state_is_noop() -> void:
	var machine := _make_initialized_machine()
	var idle := machine.current_state

	machine.transition_to(&"idle")

	assert_eq(idle.enter_count, 1)
	assert_eq(idle.exit_count, 0)
	assert_eq(machine.get_current_state_name(), &"idle")

func test_forced_transition_to_current_state_restarts_state() -> void:
	var machine := _make_initialized_machine()
	var idle := machine.current_state

	machine.transition_to(&"idle", {"restart": true}, true)

	assert_eq(idle.exit_count, 1)
	assert_eq(idle.enter_count, 2)
	assert_eq(idle.last_previous_state, idle)
	assert_eq(idle.last_enter_data["restart"], true)

func test_transition_exits_previous_and_enters_next_state_with_data() -> void:
	var machine := _make_initialized_machine()
	var idle := machine.current_state
	var walk := machine.get_node("Walk")

	machine.transition_to(&"walk", {"direction": Vector2.RIGHT})

	assert_eq(idle.exit_count, 1)
	assert_eq(walk.enter_count, 1)
	assert_eq(walk.last_previous_state, idle)
	assert_eq(walk.last_enter_data["direction"], Vector2.RIGHT)

func test_physics_update_and_animation_finished_delegate_to_current_state() -> void:
	var machine := _make_initialized_machine()
	var idle := machine.current_state

	machine.physics_update(0.25)
	machine.animation_finished()

	assert_eq(idle.physics_update_count, 1)
	assert_eq(idle.last_physics_delta, 0.25)
	assert_eq(idle.animation_finished_count, 1)

func _make_initialized_machine() -> StateMachine:
	var machine := _make_machine()
	machine.add_child(_make_state("Idle"))
	machine.add_child(_make_state("Walk"))
	machine.initialize(_make_actor())
	return machine

func _make_machine() -> StateMachine:
	var machine := StateMachineResource.new()
	_nodes.append(machine)
	return machine

func _make_actor() -> Node:
	var actor := Node.new()
	_nodes.append(actor)
	return actor

func _make_state(state_name: String) -> Node:
	var state := TestStateResource.new()
	state.name = state_name
	return state

func _record_transition(current_state: StringName, previous_state: StringName) -> void:
	_transitions.append({
		"current": current_state,
		"previous": previous_state,
	})
