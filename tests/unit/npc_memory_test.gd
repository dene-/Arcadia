extends "res://tests/test_case.gd"

func _profile(id: StringName = &"test_npc") -> NpcProfile:
	var profile := NpcProfile.new()
	profile.npc_id = id
	profile.profile_name = "Test NPC"
	return profile

func _policy(remember: bool = true) -> Dictionary:
	return {"remember": remember, "retrieve": true, "update_belief": false,
		"importance": 0.8, "emotional_intensity": 0.7, "response_mode": "DEFENSIVE",
		"relationship_delta": {"familiarity": 0.01, "trust": -0.08,
			"respect": 0.0, "affection": 0.0, "fear": 0.08, "suspicion": 0.0}}

func _result(type: String = "episodic") -> Dictionary:
	return {"response": "Leave my forge.", "replies": ["Sorry.", "No.", "Goodbye."],
		"memory_writes": [{"type": type, "gist": "The player threatened my forge.",
			"source": "player_claim", "topics": ["forge"], "people": ["player"]}],
		"recalled_memory_ids": []}

func test_small_talk_remains_short_term_and_history_is_bounded() -> void:
	var store := NpcMemoryStore.new()
	store.ensure_npc(_profile())
	for index: int in range(20):
		assert_true(store.commit_exchange("test_npc", "Hello", _result(), _policy(false), [], []))
	var state: Dictionary = store.snapshot("test_npc")
	assert_eq(state.memories.size(), 0)
	assert_eq(state.recent_dialogue.size(), 12)
	assert_eq(store.turn, 20)
	assert_true(state.relationship.trust >= -1.0)
	assert_true(state.relationship.fear <= 1.0)

func test_claim_admission_does_not_create_a_belief_without_jev_gate() -> void:
	var store := NpcMemoryStore.new()
	store.ensure_npc(_profile())
	store.commit_exchange("test_npc", "Threat", _result("semantic"), _policy(), [], [])
	assert_eq(store.snapshot("test_npc").memories.size(), 0)
	var policy: Dictionary = _policy()
	policy.update_belief = true
	store.commit_exchange("test_npc", "Threat", _result("semantic"), policy, [], [])
	var memory: Dictionary = store.snapshot("test_npc").memories[0]
	assert_eq(memory.source, "player_claim")
	assert_eq(memory.confidence, 0.6)
	assert_eq(memory.importance, 0.8)

func test_repeated_claim_does_not_duplicate_or_increase_confidence() -> void:
	var store := NpcMemoryStore.new()
	store.ensure_npc(_profile())
	for index: int in range(3):
		store.commit_exchange("test_npc", "Threat", _result(), _policy(), [], [])
	var state: Dictionary = store.snapshot("test_npc")
	assert_eq(state.memories.size(), 1)
	assert_eq(state.memories[0].confidence, 0.6)

func test_npcs_are_isolated_and_renaming_does_not_change_identity() -> void:
	var store := NpcMemoryStore.new()
	var profile: NpcProfile = _profile()
	store.ensure_npc(profile)
	store.ensure_npc(_profile(&"other"))
	store.commit_exchange("test_npc", "Threat", _result(), _policy(), [], [])
	profile.profile_name = "Renamed"
	store.ensure_npc(profile)
	assert_eq(store.snapshot("test_npc").memories.size(), 1)
	assert_eq(store.snapshot("other").memories.size(), 0)
	assert_eq(store.snapshot("other").relationship.trust, 0.0)

func test_recall_filters_details_without_damaging_the_archive() -> void:
	var memory: Dictionary = NpcMemory.create("old", "episodic", "A childhood lesson.", "authored", -1000)
	memory.important_details = ["The hammer was heavy."]
	memory.weak_details = ["A secret precise detail."]
	memory.topics = ["hammer"]
	var original: Dictionary = memory.duplicate(true)
	var view: Dictionary = NpcMemoryRetriever.new().recall(memory, NpcCognitionProfile.new(), 1000)
	assert_false(JSON.stringify(view).contains("secret precise detail"))
	assert_false(view.has("created_turn"))
	assert_eq(memory, original)

func test_age_rehearsal_emotion_and_sensory_cues_change_recall() -> void:
	var retriever := NpcMemoryRetriever.new()
	var cognition := NpcCognitionProfile.new()
	var memory: Dictionary = NpcMemory.create("one", "episodic", "A fire.", "authored", 0)
	var fresh: Dictionary = retriever.recall(memory, cognition, 0)
	var old: Dictionary = retriever.recall(memory, cognition, 10000)
	assert_true(fresh.recall_quality > old.recall_quality)
	memory.recall_count = 10
	memory.emotional_intensity = 1.0
	var reinforced: Dictionary = retriever.recall(memory, cognition, 10000, 1.0)
	assert_true(reinforced.recall_quality > old.recall_quality)

func test_retrieval_requires_cues_and_is_bounded_and_deterministic() -> void:
	var memories: Array = []
	for index: int in range(20):
		var memory: Dictionary = NpcMemory.create("m%02d" % index, "episodic", "Repairing a dagger.", "authored", 0)
		memory.topics = ["dagger"]
		memories.append(memory)
	var retriever := NpcMemoryRetriever.new()
	var cognition := NpcCognitionProfile.new()
	assert_eq(retriever.retrieve(memories, "Hello", {}, cognition, 0).size(), 0)
	var result: Array = retriever.retrieve(memories, "Where is my dagger?", {}, cognition, 0)
	assert_eq(result.size(), 6)
	assert_eq(result[0].id, "m00")
	assert_eq(result, retriever.retrieve(memories, "Where is my dagger?", {}, cognition, 0))

func test_sensory_cue_retrieves_an_unmentioned_memory() -> void:
	var memory: Dictionary = NpcMemory.create("fire", "episodic", "A fire long ago.", "authored", 0)
	memory.sensory_cues = ["burning lamp oil"]
	var result: Array = NpcMemoryRetriever.new().retrieve([memory], "Hello",
		{"sensory_cues": ["burning lamp oil"]}, NpcCognitionProfile.new(), 0)
	assert_eq(result.size(), 1)

func test_only_available_used_memories_are_reinforced_and_events_consumed_once() -> void:
	var store := NpcMemoryStore.new()
	var profile: NpcProfile = _profile()
	profile.memories = ["Old memory", "Hidden memory"]
	store.ensure_npc(profile)
	store.record_event(profile, "I was injured.")
	var old_events: Array = store.snapshot("test_npc").recent_events
	store.record_event(profile, "Someone arrived.")
	var result: Dictionary = _result()
	result.recalled_memory_ids = ["legacy:0", "legacy:1"]
	store.commit_exchange("test_npc", "Hello", result, _policy(false), [{"id": "legacy:0"}], old_events)
	var state: Dictionary = store.snapshot("test_npc")
	assert_eq(state.memories[0].recall_count, 1)
	assert_eq(state.memories[1].recall_count, 0)
	assert_eq(state.recent_events, ["Someone arrived."])
	assert_eq(profile.memories, PackedStringArray(["Old memory", "Hidden memory"]))

func test_invalid_exchange_does_not_mutate_state() -> void:
	var store := NpcMemoryStore.new()
	store.ensure_npc(_profile())
	var before: Dictionary = store.to_save_data()
	var result: Dictionary = _result()
	result.replies = ["One"]
	assert_false(store.commit_exchange("test_npc", "Hello", result, _policy(), [], []))
	var policy: Dictionary = _policy()
	policy.importance = NAN
	assert_false(store.commit_exchange("test_npc", "Hello", _result(), policy, [], []))
	assert_eq(store.to_save_data(), before)

func test_prospective_memories_are_resolved_by_game_code() -> void:
	var store := NpcMemoryStore.new()
	store.ensure_npc(_profile())
	store.commit_exchange("test_npc", "Promise", _result("prospective"), _policy(), [], [])
	assert_false(store.snapshot("test_npc").memories[0].completed)
	assert_true(store.complete_intention("test_npc", "mem:1"))
	assert_true(store.snapshot("test_npc").memories[0].completed)

func test_save_round_trip_is_independent_and_invalid_load_is_atomic() -> void:
	var store := NpcMemoryStore.new()
	store.ensure_npc(_profile())
	store.commit_exchange("test_npc", "Threat", _result(), _policy(), [], [])
	var data: Variant = JSON.parse_string(JSON.stringify(store.to_save_data()))
	var restored := NpcMemoryStore.new()
	assert_true(restored.from_save_data(data))
	assert_eq(restored.snapshot("test_npc").memories[0].gist, "The player threatened my forge.")
	data.npcs.test_npc.memories[0].confidence = 10
	var before: Dictionary = restored.to_save_data()
	assert_false(restored.from_save_data(data))
	assert_eq(restored.to_save_data(), before)
	assert_eq(store.snapshot("test_npc").memories[0].confidence, 0.6)

func test_corrupt_save_is_preserved_and_valid_file_round_trips() -> void:
	var path: String = "/tmp/arcadia-memory-test-%d.json" % Time.get_ticks_usec()
	var store := NpcMemoryStore.new()
	store.ensure_npc(_profile())
	assert_eq(store.save_file(path), OK)
	var restored := NpcMemoryStore.new()
	assert_eq(restored.load_file(path), OK)
	assert_false(restored.snapshot("test_npc").is_empty())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("corrupt fixture")
	file.close()
	assert_eq(restored.load_file(path), ERR_FILE_CORRUPT)
	assert_eq(restored.save_file(path), ERR_FILE_CORRUPT)
	assert_eq(FileAccess.get_file_as_string(path), "corrupt fixture")
	DirAccess.remove_absolute(path)

func test_all_authored_profiles_have_unique_ids_and_valid_memories() -> void:
	var ids: Array[StringName] = []
	for profession: String in ["alchemist", "blacksmith", "butcher", "carpenter", "cooker", "dyer", "furrier", "jeweller", "tailor"]:
		var profile: NpcProfile = load("res://game/resources/actors/humans/%s_npc_profile.tres" % profession)
		assert_false(profile.npc_id.is_empty())
		assert_false(profile.npc_id in ids)
		ids.append(profile.npc_id)
		assert_eq(profile.knowledge_packs.size(), 2)
		for memory: NpcCoreMemory in profile.core_memories:
			assert_true(NpcMemory.is_valid(memory.to_memory()))
		assert_false(profile.to_backend_profile().has("core_memories"))

func test_name_recall_filters_names_from_gist_and_details() -> void:
	var memory: Dictionary = NpcMemory.create("old", "episodic", "Edrin brought a dagger.", "authored", 0)
	memory.people = ["Edrin"]
	memory.important_details = ["Edrin wore a red coat."]
	memory.importance = 1.0
	memory.emotional_intensity = 1.0
	var cognition := NpcCognitionProfile.new()
	cognition.name_recall = 0.0
	var view: Dictionary = NpcMemoryRetriever.new().recall(memory, cognition, 0)
	assert_false(JSON.stringify(view).contains("Edrin"))
	assert_true(memory.gist.contains("Edrin"))

func test_grounding_evidence_is_saved_but_not_exposed_as_perfect_recall() -> void:
	var store := NpcMemoryStore.new()
	store.ensure_npc(_profile())
	var result: Dictionary = _result()
	result.memory_writes[0].evidence = "I will burn down your forge."
	store.commit_exchange("test_npc", "I will burn down your forge.", result, _policy(), [], [])
	var loaded := NpcMemoryStore.new()
	assert_true(loaded.from_save_data(JSON.parse_string(JSON.stringify(store.to_save_data()))))
	var memory: Dictionary = loaded.snapshot("test_npc").memories[0]
	assert_eq(memory.evidence, "I will burn down your forge.")
	var recall: Dictionary = NpcMemoryRetriever.new().recall(memory, NpcCognitionProfile.new(), 10000)
	assert_false(recall.has("evidence"))
