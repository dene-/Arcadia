extends "res://tests/test_case.gd"

class InspectorNpc extends BaseNpc:
	func _ready() -> void:
		# Inspector tests do not start physics or the actor state machine.
		pass

var _npc: BaseNpc
var _store: NpcMemoryStore
var _saved_state: Dictionary

func before_each() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	_store = tree.root.get_node("DialogManager").get_memory_store()
	_saved_state = _store.to_save_data()
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
	_store.from_save_data(_saved_state)

func test_inspection_does_not_initialize_or_serialize_runtime_state() -> void:
	assert_eq(_npc.get("runtime_memory_npc_id"), "inspector_test_npc")
	assert_eq(_npc.get("runtime_memory_status"), "Not initialized yet.")
	assert_eq(_npc.get("runtime_memory_memories"), [])
	assert_eq(_store.to_save_data(), _saved_state)
	var count: int = 0
	for property: Dictionary in _npc.get_property_list():
		if String(property.name).begins_with("runtime_memory_"):
			count += 1
			assert_true(property.usage & PROPERTY_USAGE_EDITOR != 0)
			assert_true(property.usage & PROPERTY_USAGE_READ_ONLY != 0)
			assert_eq(property.usage & PROPERTY_USAGE_STORAGE, 0)
	assert_eq(count, 8)
	var packed := PackedScene.new()
	assert_eq(packed.pack(_npc), OK)
	var state: SceneState = packed.get_state()
	for index: int in range(state.get_node_property_count(0)):
		assert_false(String(state.get_node_property_name(0, index)).begins_with("runtime_memory_"))

func test_inspector_reads_live_commits_and_cannot_mutate_nested_memories() -> void:
	_store.ensure_npc(_npc.get_npc_profile())
	assert_eq(_npc.get("runtime_memory_memories").size(), 1)
	_store.record_event(_npc.get_npc_profile(), "I was injured.")
	assert_eq(_npc.get("runtime_memory_recent_events"), ["I was injured."])
	var policy: Dictionary = {"remember": true, "retrieve": false, "update_belief": false,
		"importance": 0.8, "emotional_intensity": 0.7, "response_mode": "DEFENSIVE",
		"relationship_delta": {"familiarity": 0.01, "trust": -0.08, "respect": 0.0,
			"affection": 0.0, "fear": 0.08, "suspicion": 0.0}}
	var result: Dictionary = {"response": "Leave.", "replies": ["Sorry.", "No.", "Goodbye."],
		"memory_writes": [{"type": "episodic", "gist": "The player threatened me.",
			"source": "player_claim", "topics": ["threat"]}], "recalled_memory_ids": []}
	assert_true(_store.commit_exchange("inspector_test_npc", "I will hurt you.", result,
		policy, [], []))
	assert_eq(_npc.get("runtime_memory_status"), "Live memory state.")
	assert_eq(_npc.get("runtime_memory_turn"), _store.turn)
	assert_eq(_npc.get("runtime_memory_recent_dialogue")[1].text, "Leave.")
	assert_eq(_npc.get("runtime_memory_relationship").trust, -0.08)
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
