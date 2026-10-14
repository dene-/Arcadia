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
	func show_spoken_reaction(text: String, _owner: String = "") -> bool:
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

var _serial: int = 0

func _observation(sense: String = "sight", observer: String = "test_observer") -> NpcObservation:
	_serial += 1
	return NpcObservation.from_perception(observer, "event:%d" % _serial, 500.0, &"outdoors",
		_event(sense))

## Mirrors the processor's inbox handshake: display entry, claim, commit (which completes).
func _record(store: NpcMemoryStore, observation: NpcObservation, minute: float = 500.0) -> bool:
	var inbox: NpcEvidenceInbox = store.minds.get_mind(observation.observer_id).evidence
	if not inbox.enqueue(observation):
		return false
	store.record_observation(_profile(), observation.to_event(), minute)
	return true

func _commit(store: NpcMemoryStore, observation: NpcObservation, policy: Dictionary) -> bool:
	var inbox: NpcEvidenceInbox = store.minds.get_mind(observation.observer_id).evidence
	var claimed: NpcObservation = inbox.claim(observation.observation_id, 500.0)
	if claimed == null:
		return false
	if not store.commit_evidence(observation.observer_id, claimed, policy).is_empty():
		inbox.fail(observation.observation_id, "invalid_policy", 500.0)
		return false
	return true

func test_observations_are_short_term_then_optionally_durable_and_applied_once() -> void:
	var store := NpcMemoryStore.new()
	var first: NpcObservation = _observation()
	assert_true(_record(store, first))
	assert_eq(store.snapshot("test_observer").observations.size(), 1)
	assert_eq(store.snapshot("test_observer").observations[0].observation_id, first.observation_id)
	assert_eq(store.snapshot("test_observer").memories.size(), 0)
	assert_true(_commit(store, first, _policy(false)))
	assert_eq(store.snapshot("test_observer").memories.size(), 0)
	assert_eq(store.snapshot("test_observer").relationship.trust, -0.08)
	assert_eq(store.snapshot("test_observer").observations[0].status, "classified")
	assert_false(_record(store, first), "A processed observation id is never accepted again")
	assert_false(_commit(store, first, _policy()))
	assert_eq(store.snapshot("test_observer").relationship.trust, -0.08)
	var second: NpcObservation = _observation()
	assert_true(_record(store, second))
	assert_true(_commit(store, second, _policy()))
	assert_eq(store.snapshot("test_observer").memories[0].source, "observed_event")
	assert_eq(store.snapshot("test_observer").memories[0].gist, _event().text)
	assert_eq(store.snapshot("test_observer").recent_dialogue.size(), 0)

func test_hearing_does_not_change_player_relationship_and_evicted_display_entries_still_commit() -> void:
	var store := NpcMemoryStore.new()
	var heard: NpcObservation = _observation("hearing")
	assert_true(_record(store, heard))
	assert_true(_commit(store, heard, _policy()))
	assert_eq(store.snapshot("test_observer").relationship, NpcRelationshipState.initial())
	var evicted: NpcObservation = _observation()
	assert_true(_record(store, evicted))
	for index: int in range(10):
		assert_true(_record(store, _observation()))
	assert_eq(store.snapshot("test_observer").observations.size(), 8)
	assert_true(_commit(store, evicted, _policy()),
		"Evidence lives in the inbox, so working-memory eviction cannot lose it")
	assert_eq(store.snapshot("test_observer").relationship.trust, -0.08)

func test_observation_saves_round_trip_and_incomplete_saves_are_rejected() -> void:
	var store := NpcMemoryStore.new()
	var observation: NpcObservation = _observation()
	_record(store, observation)
	_commit(store, observation, _policy())
	var saved: Dictionary = store.to_save_data()
	var restored := NpcMemoryStore.new()
	var persisted: Dictionary = JSON.parse_string(JSON.stringify(saved))
	assert_true(restored.minds.from_data(JSON.parse_string(JSON.stringify(store.minds.to_data()))))
	assert_true(restored.from_save_data(persisted))
	var restored_state: Dictionary = restored.snapshot("test_observer")
	assert_eq(restored_state.relationship.trust, -0.08)
	restored_state.erase("relationship")
	assert_eq(restored_state, persisted.npcs.test_observer)
	saved.npcs.test_observer.observations[0].status = "invalid"
	assert_false(restored.from_save_data(saved))
	saved.npcs.test_observer.observations[0].status = "unavailable"
	assert_false(restored.from_save_data(saved), "Unavailable is no longer a display status")
	saved.npcs.test_observer.observations[0].status = "classified"
	saved.npcs.test_observer.observations[0].modality = "TELEPATHY"
	assert_false(restored.from_save_data(saved))
	saved.npcs.test_observer.observations[0].modality = "SIGHT"
	saved.npcs.test_observer.erase("observations")
	saved.npcs.test_observer.erase("next_observation_id")
	assert_false(restored.from_save_data(saved))
	assert_eq(restored.snapshot("test_observer").memories.size(), 1)
	assert_eq(restored.snapshot("test_observer").observations.size(), 1)

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
	processor.observe(_profile(), {}, _observation())
	await tree.process_frame
	assert_eq(backend.payloads.size(), 1)
	assert_eq(processor.store.turn, 0)
	processor.observe(_profile(), {}, _observation("touch"))
	backend.hold = false
	backend.release.emit()
	await processor.flush("test_observer")
	assert_eq(processor.store.turn, 2)
	assert_eq(backend.payloads.size(), 2)
	assert_eq(backend.payloads[1].context.current.past_observations.size(), 1)
	assert_eq(backend.payloads[1].context.memories.size(), 1,
		"Observation decisions must be able to recognize a prior related experience")
	# Seeing and feeling one incident spends a single incident budget.
	assert_eq(processor.store.snapshot("test_observer").relationship.trust, -0.15)
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
	var failed: NpcObservation = _observation()
	processor.observe(_profile(), {}, failed)
	await processor.flush("test_observer")
	var state: Dictionary = processor.store.snapshot("test_observer")
	assert_eq(state.observations[0].status, "pending", "The display entry stays unassessed context")
	var item: Dictionary = processor.store.minds.get_mind("test_observer").evidence.item(
		failed.observation_id)
	assert_eq(item.status, "DEFERRED", "Failed evidence is kept for a later retry")
	assert_eq(state.relationship, NpcRelationshipState.initial())
	assert_true(state.memories.is_empty())
	assert_eq(processor.store.turn, 0)
	processor.queue_free()
	await tree.process_frame
	backend.free()

func test_cooldown_limits_reactions_without_impersonating_player_conversation() -> void:
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
	processor.observe(_profile(), {}, _observation(), npc)
	await processor.flush("test_observer")
	processor.observe(_profile(), {}, _observation("touch"), npc)
	await processor.flush("test_observer")
	assert_eq(backend.reaction_calls, 1)
	assert_eq(npc.spoken, ["Keep away!"])
	assert_true(processor.store.snapshot("test_observer").recent_dialogue.is_empty())
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
	processor.observe(_profile(), {}, _observation(), npc)
	for _frame: int in range(10):
		if backend.reaction_calls > 0:
			break
		await tree.process_frame
	assert_eq(backend.reaction_calls, 1)
	await processor.wait_for_assessment("test_observer")
	assert_eq(processor.store.snapshot("test_observer").relationship.trust, -0.08)
	processor.observe(_profile(), {}, _observation("touch"), npc)
	await tree.process_frame
	await processor.wait_for_assessment("test_observer")
	assert_eq(processor.store.snapshot("test_observer").relationship.trust, -0.15)
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
		processor.observe(profile, {}, _observation("sight", String(profile.npc_id)), npc)
	await tree.process_frame
	assert_eq(backend.payloads.size(), 3)
	assert_eq(backend.reaction_calls, 2)
	assert_eq(processor.store.turn, 3)
	assert_eq(processor.store.snapshot("speaker_2").observations[0].diagnostics.speech_result, "selected")
	backend.release_reaction.emit()
	await tree.process_frame
	assert_eq(backend.reaction_calls, 3)
	backend.release_reaction.emit()
	for index: int in range(3):
		await processor.flush("speaker_%s" % index)
		assert_eq(sources[index].spoken, ["Keep away!"])
	processor.queue_free()
	await tree.process_frame
	for source: BaseNpc in sources:
		source.free()
	backend.free()

func test_reactions_survive_routine_updates_but_not_new_perception_injury_or_move() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	for change: String in ["perception", "injury", "space", "routine"]:
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
		processor.observe(_profile(), {}, _observation(), npc)
		for _frame: int in range(5):
			await tree.process_frame
			if backend.reaction_calls > 0:
				break
		assert_eq(backend.reaction_calls, 1)
		match change:
			"perception":
				processor.observe(_profile(), {}, _observation("touch"), npc)
				await tree.process_frame
				await processor.wait_for_assessment("test_observer")
			"injury":
				npc.health -= 1
			"space":
				npc.world_space = &"home:test"
			"routine":
				npc.life_revision += 1
		backend.release_reaction.emit()
		await processor.flush("test_observer")
		if change == "routine":
			assert_eq(npc.spoken, ["Keep away!"])
			assert_eq(processor.store.snapshot("test_observer").observations[0].diagnostics.speech_result,
				"displayed")
		else:
			assert_true(npc.spoken.is_empty(), change + " should invalidate the old response")
			assert_eq(processor.store.snapshot("test_observer").observations[0].diagnostics.speech_result,
				"context_changed")
		processor.queue_free()
		await tree.process_frame
		backend.free()
		npc.free()

func test_working_memory_expires_in_game_time_without_erasing_diagnostics_or_archive() -> void:
	var store := NpcMemoryStore.new()
	var early_log: NpcObservation = _observation()
	_record(store, early_log, 500.0)
	_commit(store, early_log, _policy(false))
	var touched: NpcObservation = _observation("touch")
	_record(store, touched, 501.0)
	_commit(store, touched, _policy())
	var state: Dictionary = store.snapshot("test_observer")
	var early: Dictionary = NpcCognitiveContext.build(state, {"world_minute": 510.0})
	assert_eq(early.past_observations.size(), 2)
	assert_eq(early.past_observations[0].age_game_minutes, 10.0)
	assert_false(early.past_observations[0].has("age_seconds"))
	var later: Dictionary = NpcCognitiveContext.build(state, {"world_minute": 700.0})
	assert_true(later.past_observations.is_empty())
	assert_true(later.current_concerns.is_empty())
	assert_eq(store.snapshot("test_observer").observations.size(), 2)
	assert_eq(store.snapshot("test_observer").memories.size(), 1)
	var injured: Dictionary = NpcCognitiveContext.build(state,
		{"world_minute": 700.0, "physical_state": "injured"})
	assert_eq(injured.current_concerns.size(), 1)
	assert_eq(injured.current_concerns[0].sense, "touch")
	assert_false(injured.current_concerns[0].recent)

func test_game_time_observations_do_not_age_while_the_game_is_closed() -> void:
	var store := NpcMemoryStore.new()
	_record(store, _observation(), 500.0)
	var saved: Dictionary = store.to_save_data()
	saved.npcs.test_observer.observations[0].created_at -= 86400
	var restored := NpcMemoryStore.new()
	assert_true(restored.from_save_data(saved))
	var context: Dictionary = NpcCognitiveContext.build(restored.snapshot("test_observer"),
		{"world_minute": 501.0})
	assert_eq(context.current_concerns.size(), 1)
	assert_eq(context.current_concerns[0].age_game_minutes, 1.0)
	# Legacy records lacking game time still load and expire using their old timestamp.
	saved.npcs.test_observer.observations[0].erase("world_minute")
	assert_true(restored.from_save_data(saved))
	context = NpcCognitiveContext.build(restored.snapshot("test_observer"), {"world_minute": 501.0})
	assert_true(context.past_observations.is_empty())
	saved.npcs.test_observer.observations[0].world_minute = -1
	assert_false(restored.from_save_data(saved))
