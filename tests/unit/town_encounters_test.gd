extends "res://tests/test_case.gd"

class SocialBackend extends DialogBackendClient:
	signal released
	var hold_stage: String = ""
	var fail_speech: bool = false
	func request_life(kind: String, _payload: Dictionary) -> Dictionary:
		if kind == hold_stage:
			await released
		match kind:
			"social":
				return {"policy": {"engage": true, "topic_index": 0,
					"tone": "CONCERNED", "another_exchange": false}}
			"listen":
				return {"policy": {"belief": 0.8, "remember": true,
					"importance": 0.7, "affinity": 0.0, "trust_player": -0.03}}
			"say":
				return {} if fail_speech else {"response": "I saw Den fighting nearby."}
		return {}

class AudibleEncounter extends TownEncounters:
	func _player_near(_speaker: BaseNpc) -> bool:
		return true

var _scene: Node2D
var _first: BaseNpc
var _second: BaseNpc
var _backend: SocialBackend
var _encounters: TownEncounters

func before_each() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	_scene = Node2D.new()
	tree.root.add_child(_scene)
	_first = _resident("social_a", Vector2(5000, 5000))
	_second = _resident("social_b", Vector2(5020, 5000))
	_backend = SocialBackend.new()
	_scene.add_child(_backend)
	_encounters = AudibleEncounter.new()
	_encounters.backend = _backend
	_encounters.state = TownLifeState.new()
	_encounters.store = NpcMemoryStore.new()
	for id: String in ["social_a", "social_b"]:
		_encounters.state.ensure_person(id, 4, ["social_a", "social_b"], ["square"])
	_encounters.state.advance(100)
	_encounters.state.rumors.observe("social_a", "Garrin",
		{"origin_id": "test:1", "text": "I saw Den fighting nearby.", "sense": "sight", "player_involved": true},
		{"remember": true, "importance": 0.8}, _encounters.state.minute)
	_scene.add_child(_encounters)

func _resident(id: String, position: Vector2) -> BaseNpc:
	var npc: BaseNpc = load("res://game/actors/npcs/base_npc.tscn").instantiate()
	npc.npc_data = npc.npc_data.duplicate(true)
	npc.npc_data.profile = npc.npc_data.profile.duplicate(true)
	npc.npc_data.profile.npc_id = StringName(id)
	npc.position = position
	_scene.add_child(npc)
	npc.daily_routine = NpcDailyRoutine.new()
	npc.daily_routine.activity = "socialize"
	return npc

func after_each() -> void:
	_scene.free()

func test_player_interruption_releases_both_actors_and_drops_late_assessment() -> void:
	_backend.hold_stage = "listen"
	await _scene.get_tree().physics_frame
	_encounters.consider(_first, _second)
	assert_true(_encounters.is_busy("social_a"))
	_second.enter_dialog()
	_encounters._process(0.01)
	assert_false(_encounters.is_busy("social_a"))
	assert_false(_first.daily_routine._held)
	_backend.released.emit()
	assert_true(_encounters.state.rumors.get_known("social_b", _encounters.state.minute).is_empty())
	assert_true(_encounters.store.snapshot("social_b").memories.all(
		func(memory: Dictionary) -> bool: return memory.source != "hearsay"))

func test_failed_audible_speech_does_not_transfer_information() -> void:
	_backend.fail_speech = true
	await _scene.get_tree().physics_frame
	_encounters.consider(_first, _second)
	assert_false(_encounters.is_busy("social_a"))
	assert_true(_encounters.state.rumors.get_known("social_b", _encounters.state.minute).is_empty())

func test_successful_speech_creates_attributed_memory_and_affects_next_player_context() -> void:
	await _scene.get_tree().physics_frame
	_encounters.consider(_first, _second)
	var snapshot: Dictionary = _encounters.store.snapshot("social_b")
	assert_eq(snapshot.memories.back().source, "hearsay")
	assert_eq(snapshot.relationship.trust, -0.03)
	assert_eq(_second.get_cognitive_context().town_rumors[0].source_id, "social_a")
	assert_true(_first.get_node("ReactionBubble").visible)
	_first.enter_dialog()
	_encounters._process(0.01)
	assert_false(_encounters.is_busy("social_b"))

func test_danger_cancels_social_holds_and_prevents_transferring_a_late_rumor() -> void:
	_backend.hold_stage = "listen"
	await _scene.get_tree().physics_frame
	_encounters.consider(_first, _second)
	assert_true(_encounters.is_busy("social_a"))
	_encounters.state.notice_perception("social_b", {"origin_id": "danger:1", "text": "I was hurt.",
		"sense": "touch", "directly_affected": true, "danger_possible": true}, "outdoors")
	_encounters.interrupt("social_b")
	assert_false(_encounters.is_busy("social_a"))
	assert_false(_first.daily_routine._held)
	assert_false(_second.daily_routine._held)
	_backend.released.emit()
	assert_true(_encounters.state.rumors.get_known("social_b", _encounters.state.minute).is_empty())
	_encounters.consider(_first, _second)
	assert_false(_encounters.is_busy("social_b"))

func test_social_decisions_retrieve_only_the_speakers_bounded_personal_memories() -> void:
	var profile: NpcProfile = _first.get_npc_profile()
	profile.core_memories = []
	profile.memories = []
	_second.get_npc_profile().profile_name = "Jon"
	for index: int in range(10):
		profile.memories.append("Jon once helped me with errand %d." % index)
	_second.get_npc_profile().memories = ["Jon has a private secret."]
	_encounters.store.ensure_npc(_second.get_npc_profile())
	var payload: Dictionary = _encounters._payload(_first, _second)
	assert_eq(payload.current.memories.size(), NpcMemoryRetriever.MAX_RECALLS)
	assert_false(JSON.stringify(payload.current.memories).contains("private secret"))
	assert_false(payload.current.memories[0].has("weak_details"))
