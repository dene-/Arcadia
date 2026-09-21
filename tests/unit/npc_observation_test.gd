extends "res://tests/test_case.gd"

class FakeBackend extends DialogBackendClient:
	signal release
	signal release_reaction
	var hold: bool = false
	var hold_reaction: bool = false
	var fail: bool = false
	var reaction_calls: int = 0
	var payloads: Array[Dictionary] = []
	var policy: Dictionary
	func request_observation(payload: Dictionary) -> Dictionary:
		payloads.append(payload.duplicate(true))
		if hold:
			await release
		return {} if fail else {"policy": policy, "answers": {}}
	func request_reaction(_payload: Dictionary) -> Dictionary:
		reaction_calls += 1
		if hold_reaction:
			await release_reaction
		return {"response": "Keep away!"}

class SpeakingNpc extends BaseNpc:
	func get_cognitive_context() -> Dictionary:
		return {"activity": "idle"}
	var spoken: Array[String] = []
	func show_spoken_reaction(text: String) -> bool:
		spoken.append(text)
		return true

func _profile() -> NpcProfile:
	var profile := NpcProfile.new()
	profile.npc_id = &"test_observer"
	return profile

func _event(sense: String = "sight") -> Dictionary:
	return {"text": "I saw the player hurt a villager.", "sense": sense, "player_involved": true}

func _policy(remember: bool = true) -> Dictionary:
	return {"remember": remember, "retrieve": false, "update_belief": false, "speak": false,
		"importance": 0.8, "emotional_intensity": 0.7, "response_mode": "NEUTRAL",
		"relationship_delta": {"familiarity": 0.01, "trust": -0.08, "respect": 0.0,
			"affection": 0.0, "fear": 0.08, "suspicion": 0.0}}

func test_observations_are_short_term_then_optionally_durable_and_applied_once() -> void:
	var store := NpcMemoryStore.new()
	store.record_observation(_profile(), _event())
	assert_eq(store.snapshot("test_observer").observations.size(), 1)
	assert_eq(store.snapshot("test_observer").memories.size(), 0)
	assert_true(store.commit_observation("test_observer", 1, _policy(false)))
	assert_eq(store.snapshot("test_observer").memories.size(), 0)
	assert_eq(store.snapshot("test_observer").relationship.trust, -0.08)
	assert_false(store.commit_observation("test_observer", 1, _policy()))
	assert_eq(store.snapshot("test_observer").relationship.trust, -0.08)
	store.record_observation(_profile(), _event())
	assert_true(store.commit_observation("test_observer", 2, _policy()))
	assert_eq(store.snapshot("test_observer").memories[0].source, "observed_event")
	assert_eq(store.snapshot("test_observer").memories[0].gist, _event().text)
	assert_eq(store.snapshot("test_observer").recent_dialogue.size(), 0)

func test_hearing_does_not_change_player_relationship_and_evicted_events_cannot_commit() -> void:
	var store := NpcMemoryStore.new()
	store.record_observation(_profile(), _event("hearing"))
	store.commit_observation("test_observer", 1, _policy())
	assert_eq(store.snapshot("test_observer").relationship, NpcRelationshipState.initial())
	for index: int in range(10):
		store.record_observation(_profile(), _event())
	assert_eq(store.snapshot("test_observer").observations.size(), 8)
	assert_false(store.commit_observation("test_observer", 2, _policy()))

func test_observation_saves_round_trip_and_older_saves_gain_empty_observations() -> void:
	var store := NpcMemoryStore.new()
	store.record_observation(_profile(), _event())
	store.commit_observation("test_observer", 1, _policy())
	var saved: Dictionary = store.to_save_data()
	var restored := NpcMemoryStore.new()
	var persisted: Dictionary = JSON.parse_string(JSON.stringify(saved))
	assert_true(restored.from_save_data(persisted))
	assert_eq(restored.snapshot("test_observer"), persisted.npcs.test_observer)
	saved.npcs.test_observer.observations[0].status = "invalid"
	assert_false(restored.from_save_data(saved))
	saved.npcs.test_observer.erase("observations")
	saved.npcs.test_observer.erase("next_observation_id")
	assert_true(restored.from_save_data(saved))
	assert_eq(restored.snapshot("test_observer").memories.size(), 1)
	assert_true(restored.snapshot("test_observer").observations.is_empty())

func test_background_processing_commits_without_conversation_and_keeps_new_arrivals() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var processor := NpcEventProcessor.new()
	processor.persist = false
	processor.store = NpcMemoryStore.new()
	var backend := FakeBackend.new()
	backend.policy = _policy()
	backend.hold = true
	processor.backend = backend
	tree.root.add_child(processor)
	processor.observe(_profile(), {}, _event())
	await tree.process_frame
	assert_eq(backend.payloads.size(), 1)
	assert_eq(processor.store.turn, 0)
	processor.observe(_profile(), {}, _event("touch"))
	backend.hold = false
	backend.release.emit()
	await processor.flush("test_observer")
	assert_eq(processor.store.turn, 2)
	assert_eq(backend.payloads.size(), 2)
	assert_eq(backend.payloads[1].context.current.past_observations.size(), 1)
	assert_eq(processor.store.snapshot("test_observer").relationship.trust, -0.16)
	assert_eq(backend.reaction_calls, 0)
	processor.queue_free()
	await tree.process_frame
	backend.free()

func test_classifier_failure_preserves_short_term_observation_without_relationship_change() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var processor := NpcEventProcessor.new()
	processor.persist = false
	processor.store = NpcMemoryStore.new()
	var backend := FakeBackend.new()
	backend.fail = true
	processor.backend = backend
	tree.root.add_child(processor)
	processor.observe(_profile(), {}, _event())
	await processor.flush("test_observer")
	var state: Dictionary = processor.store.snapshot("test_observer")
	assert_eq(state.observations[0].status, "unavailable")
	assert_eq(state.relationship, NpcRelationshipState.initial())
	assert_true(state.memories.is_empty())
	assert_eq(processor.store.turn, 0)
	processor.queue_free()
	await tree.process_frame
	backend.free()

func test_cooldown_limits_reactions_and_only_spoken_lines_enter_history() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var processor := NpcEventProcessor.new()
	processor.persist = false
	processor.store = NpcMemoryStore.new()
	var backend := FakeBackend.new()
	backend.policy = _policy()
	backend.policy.speak = true
	processor.backend = backend
	tree.root.add_child(processor)
	var npc := SpeakingNpc.new()
	npc.npc_data = NpcData.new()
	processor.observe(_profile(), {}, _event(), npc)
	await processor.flush("test_observer")
	processor.observe(_profile(), {}, _event("touch"), npc)
	await processor.flush("test_observer")
	assert_eq(backend.reaction_calls, 1)
	assert_eq(npc.spoken, ["Keep away!"])
	assert_eq(processor.store.snapshot("test_observer").recent_dialogue.size(), 1)
	processor.queue_free()
	await tree.process_frame
	backend.free()
	npc.free()

func test_late_reaction_cannot_speak_through_a_freed_npc() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var processor := NpcEventProcessor.new()
	processor.persist = false
	processor.store = NpcMemoryStore.new()
	var backend := FakeBackend.new()
	backend.policy = _policy()
	backend.policy.speak = true
	backend.hold_reaction = true
	processor.backend = backend
	tree.root.add_child(processor)
	var npc := SpeakingNpc.new()
	npc.npc_data = NpcData.new()
	processor.observe(_profile(), {}, _event(), npc)
	await tree.process_frame
	assert_eq(backend.reaction_calls, 1)
	await processor.wait_for_assessment("test_observer")
	assert_eq(processor.store.snapshot("test_observer").relationship.trust, -0.08)
	processor.observe(_profile(), {}, _event("touch"), npc)
	await tree.process_frame
	await processor.wait_for_assessment("test_observer")
	assert_eq(processor.store.snapshot("test_observer").relationship.trust, -0.16)
	assert_eq(backend.payloads.size(), 2)
	npc.free()
	backend.release_reaction.emit()
	await processor.flush("test_observer")
	assert_true(processor.store.snapshot("test_observer").recent_dialogue.is_empty())
	processor.queue_free()
	await tree.process_frame
	backend.free()

func test_speech_generation_has_a_global_limit_without_blocking_assessment() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var processor := NpcEventProcessor.new()
	processor.persist = false
	processor.store = NpcMemoryStore.new()
	var backend := FakeBackend.new()
	backend.policy = _policy()
	backend.policy.speak = true
	backend.hold_reaction = true
	processor.backend = backend
	tree.root.add_child(processor)
	var sources: Array[BaseNpc] = []
	for index: int in range(3):
		var npc := SpeakingNpc.new()
		npc.npc_data = NpcData.new()
		sources.append(npc)
		var profile: NpcProfile = _profile()
		profile.npc_id = StringName("speaker_%s" % index)
		processor.observe(profile, {}, _event(), npc)
	await tree.process_frame
	assert_eq(backend.payloads.size(), 3)
	assert_eq(backend.reaction_calls, 2)
	assert_eq(processor.store.turn, 3)
	assert_eq(processor.store.snapshot("speaker_2").observations[0].diagnostics.speech_result, "speech_capacity")
	backend.release_reaction.emit()
	for index: int in range(3):
		await processor.flush("speaker_%s" % index)
	processor.queue_free()
	await tree.process_frame
	for source: BaseNpc in sources:
		source.free()
	backend.free()
