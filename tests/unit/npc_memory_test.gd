extends "res://tests/test_case.gd"

const Appraisals = preload("res://tests/fixtures/npc_appraisal_fixture.gd")
const SESSION: String = "player:1"

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
	return {"response": "Leave my forge.",
		"memory_writes": [{"type": type, "gist": "The player threatened my forge.",
			"source": "player_claim", "topics": ["forge"], "people": ["player"]}],
		"recalled_memory_ids": []}

func test_small_talk_remains_short_term_and_history_is_bounded() -> void:
	var store := NpcMemoryStore.new()
	store.ensure_npc(_profile())
	for index: int in range(20):
		assert_true(store.commit_exchange("test_npc", "Hello", _result(), _policy(false), [], [], SESSION))
	var state: Dictionary = store.snapshot("test_npc")
	assert_eq(state.memories.size(), 0)
	assert_eq(state.recent_dialogue.size(), 12)
	assert_eq(store.turn, 20)
	assert_true(state.relationship.trust >= -1.0)
	assert_true(state.relationship.fear <= 1.0)

func test_claim_admission_does_not_create_a_belief_without_jev_gate() -> void:
	var store := NpcMemoryStore.new()
	store.ensure_npc(_profile())
	store.commit_exchange("test_npc", "Threat", _result("semantic"), _policy(), [], [], SESSION)
	assert_eq(store.snapshot("test_npc").memories.size(), 0)
	var policy: Dictionary = _policy()
	policy.update_belief = true
	store.commit_exchange("test_npc", "Threat", _result("semantic"), policy, [], [], SESSION)
	var memory: Dictionary = store.snapshot("test_npc").memories[0]
	assert_eq(memory.source, "player_claim")
	assert_eq(memory.confidence, 0.6)
	assert_eq(memory.importance, 0.8)

func test_repeated_claim_does_not_duplicate_or_increase_confidence() -> void:
	var store := NpcMemoryStore.new()
	store.ensure_npc(_profile())
	for index: int in range(3):
		store.commit_exchange("test_npc", "Threat", _result(), _policy(), [], [], SESSION)
	var state: Dictionary = store.snapshot("test_npc")
	assert_eq(state.memories.size(), 1)
	assert_eq(state.memories[0].confidence, 0.6)

func test_npcs_are_isolated_and_renaming_does_not_change_identity() -> void:
	var store := NpcMemoryStore.new()
	var profile: NpcProfile = _profile()
	store.ensure_npc(profile)
	store.ensure_npc(_profile(&"other"))
	store.commit_exchange("test_npc", "Threat", _result(), _policy(), [], [], SESSION)
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
	memory.created_minute = 0.0
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
	store.commit_exchange("test_npc", "Hello", result, _policy(false), [{"id": "legacy:0"}], old_events,
		SESSION)
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
	result.erase("response")
	assert_false(store.commit_exchange("test_npc", "Hello", result, _policy(), [], [], SESSION))
	var policy: Dictionary = _policy()
	policy.importance = NAN
	assert_false(store.commit_exchange("test_npc", "Hello", _result(), policy, [], [], SESSION))
	assert_false(store.commit_exchange("test_npc", "Hello", _result(), _policy(), [], [], ""))
	assert_eq(store.to_save_data(), before)

func test_prospective_memories_are_resolved_by_game_code() -> void:
	var store := NpcMemoryStore.new()
	store.ensure_npc(_profile())
	store.commit_exchange("test_npc", "Promise", _result("prospective"), _policy(), [], [], SESSION)
	assert_false(store.snapshot("test_npc").memories[0].completed)
	assert_true(store.complete_intention("test_npc", "mem:1"))
	assert_true(store.snapshot("test_npc").memories[0].completed)

func test_save_round_trip_is_independent_and_invalid_load_is_atomic() -> void:
	var store := NpcMemoryStore.new()
	store.ensure_npc(_profile())
	store.commit_exchange("test_npc", "Threat", _result(), _policy(), [], [], SESSION)
	var data: Variant = JSON.parse_string(JSON.stringify(store.to_save_data()))
	assert_false(data.npcs.test_npc.has("relationship"))
	var restored := NpcMemoryStore.new()
	assert_true(restored.minds.from_data(JSON.parse_string(JSON.stringify(store.minds.to_data()))))
	assert_true(restored.from_save_data(data))
	assert_eq(restored.snapshot("test_npc").memories[0].gist, "The player threatened my forge.")
	assert_eq(restored.snapshot("test_npc").relationship, store.snapshot("test_npc").relationship)
	assert_eq(restored.snapshot("test_npc").relationship.trust, -0.08)
	data.npcs.test_npc.memories[0].confidence = 10
	var before: Dictionary = restored.to_save_data()
	assert_false(restored.from_save_data(data))
	assert_eq(restored.to_save_data(), before)
	assert_eq(store.snapshot("test_npc").memories[0].confidence, 0.6)

func test_save_shape_requires_version_two_without_relationship() -> void:
	var store := NpcMemoryStore.new()
	store.ensure_npc(_profile())
	var data: Dictionary = store.to_save_data()
	assert_eq(data.version, 2)
	var restored := NpcMemoryStore.new()
	for key: String in ["recent_dialogue", "memories", "recent_events", "observations",
			"next_observation_id", "heard_origins"]:
		var broken: Dictionary = data.duplicate(true)
		broken.npcs.test_npc.erase(key)
		assert_false(restored.from_save_data(broken), key)
	var legacy: Dictionary = data.duplicate(true)
	legacy.npcs.test_npc.relationship = NpcRelationshipState.initial()
	assert_false(restored.from_save_data(legacy))
	legacy = data.duplicate(true)
	legacy.version = 1
	assert_false(restored.from_save_data(legacy))

func test_dialogue_history_carries_its_session_and_prompts_see_its_age() -> void:
	var store := NpcMemoryStore.new()
	store.ensure_npc(_profile())
	store.set_world_minute(600.0)
	assert_true(store.commit_exchange("test_npc", "Hello", _result(), _policy(false), [], [], "player:1"))
	store.set_world_minute(640.0)
	assert_true(store.commit_exchange("test_npc", "Again", _result(), _policy(false), [], [], "player:2"))
	var history: Array = store.snapshot("test_npc").recent_dialogue
	assert_eq([history[0].speaker, history[0].session_id, history[0].minute, history[0].delivered],
		["player", "player:1", 600.0, true])
	assert_eq([history[3].speaker, history[3].session_id, history[3].minute], ["npc", "player:2", 640.0])
	var legacy: Dictionary = {"speaker": "npc", "text": "Old words.", "session_id": "legacy",
		"minute": -1.0, "delivered": true}
	var view: Array[Dictionary] = NpcMemoryStore.history_for_prompt(history + [legacy], 650.0,
		"player:2", 640.0)
	assert_eq([view[0].session, view[0].age_game_minutes], ["earlier", 50.0])
	assert_eq([view[2].session, view[2].age_game_minutes], ["current", 10.0])
	assert_eq([view[4].session, view[4].age_game_minutes], ["legacy", "unknown"])
	assert_false(view[0].has("minute"))
	var data: Dictionary = store.to_save_data()
	var restored := NpcMemoryStore.new()
	assert_true(restored.minds.from_data(store.minds.to_data()))
	assert_true(restored.from_save_data(data.duplicate(true)))
	for key: String in ["session_id", "minute", "delivered"]:
		var broken: Dictionary = data.duplicate(true)
		broken.npcs.test_npc.recent_dialogue[0].erase(key)
		assert_false(restored.from_save_data(broken), key)

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
	store.commit_exchange("test_npc", "I will burn down your forge.", result, _policy(), [], [], SESSION)
	var loaded := NpcMemoryStore.new()
	assert_true(loaded.from_save_data(JSON.parse_string(JSON.stringify(store.to_save_data()))))
	var memory: Dictionary = loaded.snapshot("test_npc").memories[0]
	assert_eq(memory.evidence, "I will burn down your forge.")
	var recall: Dictionary = NpcMemoryRetriever.new().recall(memory, NpcCognitionProfile.new(), 10000)
	assert_false(recall.has("evidence"))

func test_memory_aging_uses_world_time_not_other_residents_activity() -> void:
	var save := NpcWorldSave.new()
	var profile: NpcProfile = _profile()
	save.memory.ensure_npc(profile)
	save.memory.commit_exchange("test_npc", "Threat", _result(), _policy(), [], [], SESSION)
	var memory: Dictionary = save.memory.snapshot("test_npc").memories[0]
	var retriever := NpcMemoryRetriever.new()
	var cognition := NpcCognitionProfile.new()
	var before: Dictionary = retriever.recall(memory, cognition, save.memory.world_minute)
	for index: int in range(100):
		var noise: NpcObservation = NpcObservation.from_perception("other", "noise:%d" % index, 10.0,
			&"outdoors", {"text": "I heard a noise.", "sense": "hearing", "player_involved": false})
		save.memory.record_observation(_profile(&"other"), noise.to_event(), 10.0)
		var inbox: NpcEvidenceInbox = save.memory.minds.get_mind("other").evidence
		assert_true(inbox.enqueue(noise))
		var claimed: NpcObservation = inbox.claim(noise.observation_id, 10.0)
		assert_eq(save.memory.commit_evidence("other", claimed, Appraisals.make(false)), "")
	assert_eq(retriever.recall(memory, cognition, save.memory.world_minute), before)
	save.life.advance(1440)
	var later: Dictionary = retriever.recall(memory, cognition, save.memory.world_minute)
	assert_true(later.recall_quality < before.recall_quality)
	var restored := NpcWorldSave.new()
	assert_true(restored.from_data(JSON.parse_string(JSON.stringify(save.to_data()))))
	assert_eq(restored.memory.world_minute, save.life.minute)
	assert_eq(retriever.recall(restored.memory.snapshot("test_npc").memories[0], cognition,
		restored.memory.world_minute), later)

func test_legacy_migration_marks_undated_memories_without_counting_exchanges_as_age() -> void:
	var save := NpcWorldSave.new()
	save.memory.ensure_npc(_profile())
	save.memory.commit_exchange("test_npc", "Threat", _result(), _policy(), [], [], SESSION)
	var data: Dictionary = save.to_data()
	data.memory.turn = 501
	data.memory.erase("world_minute")
	data.memory.npcs.test_npc.memories[0].erase("created_minute")
	data.memory.npcs.test_npc.memories[0].erase("date_known")
	data.world.life.minute = 4320.0
	var restored := NpcWorldSave.new()
	assert_true(restored.from_data(data))
	var memory: Dictionary = restored.memory.snapshot("test_npc").memories[0]
	assert_eq(memory.created_minute, NpcMemory.UNKNOWN_MINUTE)
	assert_false(memory.date_known)
	assert_eq(memory.age_anchor_minute, 4320.0)
	assert_eq(NpcMemory.retention_age(memory, restored.memory.world_minute), 0.0,
		"500 exchanges are not elapsed time")
	restored.life.advance(60)
	assert_eq(NpcMemory.retention_age(memory, restored.memory.world_minute), 2.0)
	var again := NpcWorldSave.new()
	assert_true(again.from_data(restored.to_data()))
	assert_eq(again.memory.snapshot("test_npc").memories[0], memory,
		"Repeated loads must not re-anchor old memories")

func test_authored_memories_and_rehearsal_are_independent_of_global_turn_count() -> void:
	var store := NpcMemoryStore.new()
	store.advance_time(9000)
	var profile: NpcProfile = _profile()
	profile.memories = ["A lesson about a forge."]
	store.ensure_npc(profile)
	var memory: Dictionary = store.snapshot("test_npc").memories[0]
	assert_eq(NpcMemory.retention_age(memory, store.world_minute), 0.0)
	var result: Dictionary = _result()
	result.recalled_memory_ids = ["legacy:0"]
	store.set_world_minute(1200.0)
	store.commit_exchange("test_npc", "Forge", result, _policy(false), [{"id": "legacy:0"}], [], SESSION)
	assert_eq(store.snapshot("test_npc").memories[0].last_recalled_minute, 1200.0)
	var invalid: Dictionary = store.to_save_data()
	invalid.npcs.test_npc.memories[0].created_minute = NAN
	assert_false(store.from_save_data(invalid))
