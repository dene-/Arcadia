extends "res://tests/test_case.gd"

const FakeService = preload("res://tests/fixtures/npc_fake_decision_service.gd")

class InspectorNpc extends BaseNpc:
	func _ready() -> void:
		# Inspector tests do not start physics or the actor state machine.
		pass

var _npc: BaseNpc
var _store: NpcMemoryStore
var _saved_state: Dictionary
var _saved_minds: Dictionary

func before_each() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	_store = tree.root.get_node("DialogManager").get_memory_store()
	_saved_state = _store.to_save_data()
	_saved_minds = _store.minds.to_data()
	var scene: PackedScene = load("res://game/actors/npcs/base_npc.tscn")
	_npc = scene.instantiate()
	var data: NpcData = _npc.npc_data.duplicate()
	_npc.set_script(InspectorNpc)
	_npc.npc_data = data
	var profile := NpcProfile.new()
	profile.npc_id = &"inspector_test_npc"
	var core := NpcCoreMemory.new()
	core.memory_id = &"childhood"
	core.gist = "I learned to mend tools as a child."
	profile.core_memories = [core]
	_npc.npc_data.profile = profile
	_npc.process_mode = Node.PROCESS_MODE_DISABLED
	tree.root.add_child(_npc)

func after_each() -> void:
	_npc.free()
	_store.minds.from_data(_saved_minds)
	_store.from_save_data(_saved_state)

func test_inspection_does_not_initialize_or_serialize_runtime_state() -> void:
	assert_eq(_npc.get("runtime_memory_npc_id"), "inspector_test_npc")
	assert_eq(_npc.get("runtime_memory_status"), "Not initialized yet.")
	assert_eq(_npc.get("runtime_memory_memories"), [])
	assert_eq(_npc.get("runtime_cognition_relationships"), {})
	assert_eq(_npc.get("runtime_cognition_trace"), [])
	assert_eq(_store.to_save_data(), _saved_state)
	assert_false(_store.minds.has_mind("inspector_test_npc"), "Inspection never creates a mind")
	var counts: Dictionary = {"runtime_memory_": 0, "runtime_cognition_": 0}
	var groups: Array[String] = []
	for property: Dictionary in _npc.get_property_list():
		if property.usage & PROPERTY_USAGE_GROUP != 0:
			groups.append(property.name)
		for prefix: String in counts:
			if String(property.name).begins_with(prefix):
				counts[prefix] += 1
				assert_true(property.usage & PROPERTY_USAGE_EDITOR != 0)
				assert_true(property.usage & PROPERTY_USAGE_READ_ONLY != 0)
				assert_eq(property.usage & PROPERTY_USAGE_STORAGE, 0)
	assert_eq(counts, {"runtime_memory_": 7, "runtime_cognition_": 13})
	assert_true("Cognition" in groups)
	var packed := PackedScene.new()
	assert_eq(packed.pack(_npc), OK)
	var state: SceneState = packed.get_state()
	for index: int in range(state.get_node_property_count(0)):
		assert_false(String(state.get_node_property_name(0, index)).begins_with("runtime_"))

func test_inspector_reads_live_commits_and_cannot_mutate_nested_memories() -> void:
	_store.ensure_npc(_npc.get_npc_profile())
	assert_eq(_npc.get("runtime_memory_memories").size(), 1)
	_store.record_event(_npc.get_npc_profile(), "I was injured.")
	assert_eq(_npc.get("runtime_memory_recent_events"), ["I was injured."])
	var speech: NpcDecisionPolicy.PlayerSpeech = FakeService.player_speech()
	var result: Dictionary = {"response": "Leave.",
		"memory_writes": [{"type": "episodic", "gist": "The player threatened me.",
			"source": "player_claim", "topics": ["threat"]}], "recalled_memory_ids": []}
	assert_true(_store.commit_exchange("inspector_test_npc", "I will hurt you.", result,
		speech, [], [], "player:1"))
	assert_eq(_npc.get("runtime_memory_status"), "Live memory state.")
	assert_eq(_npc.get("runtime_memory_turn"), _store.turn)
	assert_eq(_npc.get("runtime_memory_recent_dialogue")[1].text, "Leave.")
	assert_eq(_npc.get("runtime_cognition_relationships").player.trust, -0.08)
	assert_eq(_npc.get("runtime_cognition_relationships").player,
		_store.minds.get_mind("inspector_test_npc").relationships.get_relationship("player"))
	var visible: Array = _npc.get("runtime_memory_memories")
	assert_eq(visible.size(), 2)
	assert_eq(visible[1].source, "player_claim")
	visible[1].topics.append("corrupted")
	visible[0].gist = "Changed in the inspector"
	visible.clear()
	var fresh: Array = _npc.get("runtime_memory_memories")
	assert_eq(fresh.size(), 2)
	assert_eq(fresh[0].gist, "I learned to mend tools as a child.")
	assert_eq(fresh[1].topics, ["threat"])

func test_cognition_group_reads_mind_and_brain_without_mutation() -> void:
	var id: String = "inspector_test_npc"
	var mind: NpcMindState = _store.minds.get_mind(id)
	assert_true(mind.relationships.seed_relationship("test_guard", {"trust": 0.4}))
	assert_ne(mind.commitments.create("check_relative", ["test_guard"], ["sighting:1"], 480.0), "")
	assert_true(mind.knowledge.record_sighting("test_guard", "outdoors", Vector2(5, 6), 480.0,
		"sighting:1"))
	assert_true(mind.evidence.enqueue(NpcObservation.from_perception(id, "world:1", 480.0,
		&"outdoors", {"kind": "stranger_seen", "sense": "sight", "text": "A stranger passed."})))
	var brain: NpcBrain = _brain(mind)
	assert_true(brain.request_conversation("session:1"))
	assert_true(brain.trace.record(480.0, NpcDecisionTrace.GOAL, {"reason": "plan_kept",
		"selected": "work", "scores": {"work": {"total": 0.7}, "rest": {"total": 0.2}}}))
	assert_true(brain.trace.record(481.0, NpcDecisionTrace.REQUEST, {"request_id": "r1",
		"request_kind": "goal", "latency_ms": 12, "outcome": "applied"}))
	assert_true(brain.trace.record(482.0, NpcDecisionTrace.SAVE_FAILURE, {"reason": "save_error:7"}))
	_npc.alert_response.phase = "orient"
	assert_eq(_npc.get("runtime_cognition_goal_scores").selected, "work")
	assert_eq(_npc.get("runtime_cognition_goal_scores").scores.rest.total, 0.2)
	assert_eq(_npc.get("runtime_cognition_current_task"), {})
	assert_eq(_npc.get("runtime_cognition_claims").values().size(), 1)
	assert_eq(_npc.get("runtime_cognition_perceived_threats"),
		[{"source": "alert_reflex", "phase": "orient"}])
	var knowledge: Array = _npc.get("runtime_cognition_knowledge_sources")
	assert_eq(knowledge.size(), 1)
	assert_eq([knowledge[0].subject, knowledge[0].predicate, knowledge[0].source_id],
		["test_guard", "location", NpcKnowledge.SELF_SOURCE])
	assert_true(_npc.get("runtime_cognition_condition").bands.has("hunger"))
	assert_eq(_npc.get("runtime_cognition_relationships").test_guard,
		mind.relationships.get_relationship("test_guard"))
	assert_eq(_npc.get("runtime_cognition_commitments").size(), 1)
	assert_eq(_npc.get("runtime_cognition_pending_evidence").by_status, {"PENDING": 1})
	assert_eq(_npc.get("runtime_cognition_request_outcomes").size(), 1)
	assert_eq(_npc.get("runtime_cognition_request_outcomes")[0].outcome, "applied")
	assert_eq(_npc.get("runtime_cognition_last_save_failure").reason, "save_error:7")
	assert_eq(_npc.get("runtime_cognition_trace").size(), 3)
	var relationships: Dictionary = _npc.get("runtime_cognition_relationships")
	relationships.test_guard.trust = -1.0
	var trace: Array = _npc.get("runtime_cognition_trace")
	trace.clear()
	assert_eq(_npc.get("runtime_cognition_relationships").test_guard.trust, 0.4)
	assert_eq(mind.relationships.get_relationship("test_guard").trust, 0.4)
	assert_eq(_npc.get("runtime_cognition_trace").size(), 3)
	assert_eq(brain.trace.entries().size(), 3)

func test_cognition_snapshot_rebuilds_only_when_state_changes() -> void:
	var mind: NpcMindState = _store.minds.get_mind("inspector_test_npc")
	var brain: NpcBrain = _brain(mind)
	assert_eq(_npc.get("runtime_cognition_trace"), [])
	var cached: Dictionary = _npc._cognition_cache
	_npc.get("runtime_cognition_relationships")
	_npc.get("runtime_cognition_goal_scores")
	assert_true(is_same(_npc._cognition_cache, cached), "Unchanged state reuses the snapshot")
	assert_true(mind.relationships.seed_relationship("test_guard", {"trust": 0.3}))
	assert_eq(_npc.get("runtime_cognition_relationships").test_guard.trust, 0.3)
	assert_false(is_same(_npc._cognition_cache, cached), "A relationship change rebuilds")
	cached = _npc._cognition_cache
	assert_true(brain.trace.record(490.0, NpcDecisionTrace.GOAL, {"reason": "plan_kept",
		"selected": "rest"}))
	assert_eq(_npc.get("runtime_cognition_goal_scores").selected, "rest")
	assert_false(is_same(_npc._cognition_cache, cached), "A new trace entry rebuilds")
	cached = _npc._cognition_cache
	assert_true(brain.request_conversation("session:2"))
	assert_eq(_npc.get("runtime_cognition_claims").size(), 1)
	assert_false(is_same(_npc._cognition_cache, cached), "A claim change rebuilds")

func _brain(mind: NpcMindState) -> NpcBrain:
	var brain := NpcBrain.new()
	brain.name = NpcBrain.NODE_NAME
	_npc.add_child(brain)
	brain.setup(mind.npc_id, mind, _npc, null, NpcBehaviorTuning.new(), 3)
	return brain
