extends "res://tests/test_case.gd"

var _scene: Node2D
var _first: BaseNpc
var _second: BaseNpc

func before_each() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	_scene = Node2D.new()
	tree.root.add_child(_scene)
	_first = _resident("voice_a", Vector2(5000, 5000))
	_second = _resident("voice_b", Vector2(5024, 5000))

func _resident(id: String, point: Vector2) -> BaseNpc:
	var npc: BaseNpc = load("res://game/actors/npcs/base_npc.tscn").instantiate()
	npc.npc_data = npc.npc_data.duplicate(true)
	npc.npc_data.profile = npc.npc_data.profile.duplicate(true)
	npc.npc_data.profile.npc_id = StringName(id)
	npc.position = point
	_scene.add_child(npc)
	return npc

func after_each() -> void:
	_scene.free()

func test_recent_audible_lines_are_bounded_and_rooms_do_not_share_them() -> void:
	await _scene.get_tree().physics_frame
	var history := NpcAmbientHistory.new()
	for index: int in range(9):
		history.record(_first, "Line %d" % index, [_first, _second])
	assert_eq(history.recent("voice_b").size(), 6)
	assert_eq(history.recent("voice_b").back().text, "Line 8")
	_second.world_space = &"home:voice_b"
	history.record(_first, "This was said outside.", [_second])
	assert_eq(history.recent("voice_b").back().text, "Line 8")
	history._heard.voice_b[0].heard_at -= 46000
	assert_eq(history.recent("voice_b").size(), 5)

func test_hearing_combat_cannot_identify_participants_or_cross_room_boundaries() -> void:
	_first.npc_data.vision_radius = 0
	var event: Dictionary = NpcPerception.observe(_first, _second, _second, false)
	assert_eq(event.sense, "hearing")
	assert_true(event.participants.is_empty())
	_second.world_space = &"home:voice_b"
	assert_true(NpcPerception.observe(_first, _second, _second, false).is_empty())

func test_long_echoes_are_suppressed_but_short_exclamations_are_allowed() -> void:
	var current: Dictionary = {"recent_ambient": [{"text": "Someone get help!"}, {"text": "Hey!"}]}
	assert_true(NpcEventProcessor._repeats_recent_speech(current, " Someone get help! "))
	assert_false(NpcEventProcessor._repeats_recent_speech(current, "Hey!"))
	assert_false(NpcEventProcessor._repeats_recent_speech(current, "Mirelle, are you hurt?"))

func test_sleep_blocks_vision_and_noise_wakes_the_resident() -> void:
	_first.state_machine.transition_to(&"sleep", {}, true)
	assert_false(NpcPerception.can_see(_first, _second))
	assert_false(_first.can_speak_reaction())
	_first.wake_from_noise()
	assert_false(_first.is_sleeping())
	assert_true(_first.get_cognitive_context().recently_awakened)

func test_visible_neighbors_supply_the_observers_own_relationship_to_reactions() -> void:
	_first.add_to_group(&"town_residents")
	_second.add_to_group(&"town_residents")
	_first.life_context.known_townspeople = [{"id": "voice_b", "relationship": {"affection": 0.8}}]
	await _scene.get_tree().physics_frame
	var event: Dictionary = NpcPerception.observe(_first, _second, null, false)
	assert_eq(event.participants.size(), 1)
	assert_eq(event.participants[0].role, "hurt_person")
	assert_eq(event.participants[0].relationship.affection, 0.8)
