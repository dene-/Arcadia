extends "res://tests/test_case.gd"

const FakeDecisionService := preload("res://tests/fixtures/npc_fake_decision_service.gd")

class AudibleEncounter extends TownEncounters:
	func _player_near(_speaker: BaseNpc) -> bool:
		return true

class IdleExecutor extends RefCounted:
	func begin_task_travel(_npc: Object, _npc_id: String, _space: StringName, _point: Vector2,
			_label: String, _owner_task_id: String) -> bool:
		return true
	func cancel_task_travel(_npc_id: String, _owner_task_id: String) -> bool:
		return true
	func task_travel_state(_npc_id: String, _owner_task_id: String) -> StringName:
		return &"none"
	func bed_for(_npc_id: String) -> Variant:
		return null

var _scene: Node2D
var _first: BaseNpc
var _second: BaseNpc
var _backend: FakeDecisionService
var _decisions: NpcDecisionService
var _encounters: TownEncounters
var _tuning := NpcBehaviorTuning.new()
var _executor := IdleExecutor.new()
var _brains: Dictionary = {}

func before_each() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	_scene = Node2D.new()
	tree.root.add_child(_scene)
	_first = _resident("social_a", Vector2(5000, 5000))
	_second = _resident("social_b", Vector2(5020, 5000))
	_backend = FakeDecisionService.new()
	_scene.add_child(_backend)
	_decisions = NpcDecisionService.new()
	_decisions.transport = _backend
	_scene.add_child(_decisions)
	_encounters = AudibleEncounter.new()
	_encounters.decisions = _decisions
	_encounters.state = TownLifeState.new()
	_encounters.store = NpcMemoryStore.new()
	_encounters.tuning = _tuning
	_encounters.brains = func(id: String) -> NpcBrain: return _brains.get(id)
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
	var brain := NpcBrain.new()
	npc.add_child(brain)
	brain.setup(id, NpcMindState.new(id), npc, _executor, _tuning, 4)
	_brains[id] = brain
	return npc

func _caution_duty() -> NpcSafetyTask:
	return NpcSafetyTask.create({"response": "CAUTION", "origin_id": "noise:1", "until_minute": 1000.0,
		"label": "here", "refuge_space": "", "refuge_point": []}, _tuning)

func _claims(id: String) -> Dictionary:
	return (_brains[id] as NpcBrain).debug_snapshot().claims

func _assert_released(id: String) -> void:
	assert_eq(_claims(id).locomotion, "")
	assert_eq(_claims(id).conversation, "")
	assert_true((_brains[id] as NpcBrain).current_activity().is_empty())

func after_each() -> void:
	_scene.free()
	_brains.clear()

func _fail_speech() -> void:
	_backend.set_default("dialogue/say", {"outcome": "UNAVAILABLE"})

func test_session_holds_both_residents_until_it_ends() -> void:
	_backend.hold("listen")
	await _scene.get_tree().physics_frame
	_encounters.consider(_first, _second)
	for id: String in ["social_a", "social_b"]:
		var task: Dictionary = (_brains[id] as NpcBrain).current_activity()
		assert_eq(task.get("kind"), "social")
		assert_eq(_claims(id).locomotion, task.task_id)
		assert_eq(_claims(id).conversation, task.task_id)
		assert_eq(_encounters.session_phase(id), TownEncounters.PHASE_CONVERSE)
	_fail_speech()
	_backend.release_all()
	assert_false(_encounters.is_busy("social_a"))
	_assert_released("social_a")
	_assert_released("social_b")

func test_invitation_takes_no_claims_and_a_crossing_invitation_is_dropped() -> void:
	_backend.hold("social")
	await _scene.get_tree().physics_frame
	_encounters.consider(_first, _second)
	_encounters.consider(_second, _first)
	for id: String in ["social_a", "social_b"]:
		assert_eq(_encounters.session_phase(id), TownEncounters.PHASE_INVITE)
		_assert_released(id)
	_fail_speech()
	_backend.release("social")
	assert_eq(_encounters.diagnostics("social_a").outcome, "speech_cancelled_or_unavailable")
	assert_false(_encounters.is_busy("social_a"))
	assert_false(_encounters.is_busy("social_b"))
	_assert_released("social_a")
	_assert_released("social_b")

func test_invitation_is_dropped_when_a_resident_becomes_unavailable() -> void:
	_backend.hold("social")
	await _scene.get_tree().physics_frame
	_encounters.consider(_first, _second)
	var duty := _caution_duty()
	assert_true((_brains["social_b"] as NpcBrain).request_task(duty))
	_encounters._process(0.01)
	assert_false(_encounters.is_busy("social_a"))
	assert_eq(_decisions.active_count(NpcDecisionService.Pool.JUDGMENT), 0)
	_backend.release_all()
	_assert_released("social_a")
	assert_eq(_claims("social_b").locomotion, duty.task_id)
	assert_eq(_claims("social_b").conversation, "")

func test_refusing_participant_releases_the_other_immediately() -> void:
	await _scene.get_tree().physics_frame
	var duty := _caution_duty()
	assert_true((_brains["social_b"] as NpcBrain).request_task(duty))
	_encounters.consider(_first, _second)
	assert_false(_encounters.is_busy("social_a"))
	_assert_released("social_a")
	assert_eq(_claims("social_b").locomotion, duty.task_id)

func test_safety_task_ends_session_and_late_release_keeps_its_claims() -> void:
	_backend.hold("listen")
	await _scene.get_tree().physics_frame
	_encounters.consider(_first, _second)
	var safety := NpcSafetyTask.create({"response": "SHELTER", "origin_id": "danger:1",
		"until_minute": 1000.0, "label": "here", "refuge_space": "", "refuge_point": []}, _tuning)
	assert_true((_brains["social_b"] as NpcBrain).request_task(safety))
	assert_false(_encounters.is_busy("social_a"))
	assert_false(_encounters.is_busy("social_b"))
	_assert_released("social_a")
	assert_eq(_decisions.active_count(NpcDecisionService.Pool.JUDGMENT), 0)
	_backend.release_all()
	assert_eq(_claims("social_b").locomotion, safety.task_id)
	assert_eq(_claims("social_b").conversation, safety.task_id)
	assert_eq((_brains["social_b"] as NpcBrain).current_activity().task_id, safety.task_id)

func test_player_interruption_releases_both_actors_and_drops_late_assessment() -> void:
	_backend.hold("listen")
	await _scene.get_tree().physics_frame
	_encounters.consider(_first, _second)
	assert_true(_encounters.is_busy("social_a"))
	_second.enter_dialog()
	_encounters._process(0.01)
	assert_false(_encounters.is_busy("social_a"))
	_assert_released("social_a")
	_assert_released("social_b")
	assert_eq(_decisions.active_count(NpcDecisionService.Pool.JUDGMENT), 0)
	_backend.release_all()
	assert_true(_encounters.state.rumors.get_known("social_b", _encounters.state.minute).is_empty())
	assert_true(_encounters.store.snapshot("social_b").memories.all(
		func(memory: Dictionary) -> bool: return memory.source != "hearsay"))

func test_failed_audible_speech_does_not_transfer_information() -> void:
	_fail_speech()
	await _scene.get_tree().physics_frame
	_encounters.consider(_first, _second)
	assert_false(_encounters.is_busy("social_a"))
	assert_true(_encounters.state.rumors.get_known("social_b", _encounters.state.minute).is_empty())

func test_successful_speech_creates_attributed_memory_and_affects_next_player_context() -> void:
	_backend.set_default("dialogue/say", {"response": "I saw Den fighting nearby."})
	_backend.queue_response("listen", {"disposition:player:trust:direction": "NEGATIVE",
		"disposition:player:trust:magnitude": 4.0})
	await _scene.get_tree().physics_frame
	_encounters.consider(_first, _second)
	assert_eq(_backend.calls("social")[0].topics, ["test:1"])
	assert_eq(_backend.calls("social")[0].tones, TownEncounters.TONES)
	assert_eq(_backend.calls("listen")[0].subjects, ["social_a", "player"])
	assert_eq(_backend.calls("utterance")[0].intents, ["share", TownEncounters.SILENCE])
	assert_eq(_backend.calls("dialogue/say")[0].intent, "share")
	var snapshot: Dictionary = _encounters.store.snapshot("social_b")
	assert_eq(snapshot.memories.back().source, "hearsay")
	# The strongest listening judgment moves trust by one incident's maximum change, not more.
	var trust: float = _encounters.store.minds.get_mind("social_b").relationships.get_relationship("player").trust
	assert_true(absf(trust + NpcIncidentBudget.MAX_CHANGE) < 0.0001, "trust %s" % trust)
	assert_eq(_second.get_cognitive_context().town_rumors[0].source_id, "social_a")
	assert_true(_first.get_node("ReactionBubble").visible)
	_first.enter_dialog()
	_encounters._process(0.01)
	assert_false(_encounters.is_busy("social_b"))

func test_danger_cancels_social_holds_and_prevents_transferring_a_late_rumor() -> void:
	_backend.hold("listen")
	await _scene.get_tree().physics_frame
	_encounters.consider(_first, _second)
	assert_true(_encounters.is_busy("social_a"))
	_encounters.state.notice_perception("social_b", {"origin_id": "danger:1", "text": "I was hurt.",
		"sense": "touch", "directly_affected": true, "danger_possible": true}, "outdoors")
	_encounters.interrupt("social_b")
	assert_false(_encounters.is_busy("social_a"))
	_assert_released("social_a")
	_assert_released("social_b")
	_backend.release_all()
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
	var payload: Dictionary = _encounters._state(_first, _second)
	assert_eq(payload.current.memories.size(), NpcMemoryRetriever.MAX_RECALLS)
	assert_false(JSON.stringify(payload.current.memories).contains("private secret"))
	assert_false(payload.current.memories[0].has("weak_details"))
