extends "res://tests/test_case.gd"

const Rig = preload("res://tests/fixtures/npc_processor_rig.gd")
const Appraisals = preload("res://tests/fixtures/npc_appraisal_fixture.gd")
## One appraisal's trust change toward the player at full magnitude (NpcIncidentBudget.MAX_CHANGE).
const HURT: float = -0.1

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
	return {"text": "I saw the player hurt a villager.", "sense": sense, "player_involved": true,
		"participants": [{"id": "player", "name": "the player", "role": "aggressor"}]}

## Seeing or feeling the player do harm: `remember` and the change of trust toward the player.
func _policy(remember: bool = true) -> NpcDecisionPolicy.Appraisal:
	return Appraisals.player_trust(HURT, remember, 0.8, 0.7)

var _serial: int = 0

func _speaker() -> SpeakingNpc:
	var npc := SpeakingNpc.new()
	npc.npc_data = NpcData.new()
	return npc

func _until(done: Callable) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	for _frame: int in range(300):
		if done.call():
			return
		await tree.process_frame

## The NPC ids of every appraisal request, in the order the provider received them.
func _npcs_asked(rig: Rig) -> Array[String]:
	var asked: Array[String] = []
	for call: Dictionary in rig.backend.calls("appraise"):
		asked.append(call.npc_id)
	return asked

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

func _commit(store: NpcMemoryStore, observation: NpcObservation,
		policy: NpcDecisionPolicy.Appraisal) -> bool:
	var inbox: NpcEvidenceInbox = store.minds.get_mind(observation.observer_id).evidence
	var claimed: NpcObservation = inbox.claim(observation.observation_id, 500.0)
	if claimed == null:
		return false
	if not store.commit_evidence(observation.observer_id, claimed, policy).is_empty():
		inbox.fail(observation.observation_id, "invalid_appraisal", 500.0)
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
	assert_eq(store.snapshot("test_observer").relationship.trust, HURT)
	assert_eq(store.snapshot("test_observer").observations[0].status, "classified")
	assert_false(_record(store, first), "A processed observation id is never accepted again")
	assert_false(_commit(store, first, _policy()))
	assert_eq(store.snapshot("test_observer").relationship.trust, HURT)
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
	assert_eq(store.snapshot("test_observer").relationship.trust, HURT)

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
	assert_eq(restored_state.relationship.trust, HURT)
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
	var rig := Rig.new()
	var processor: NpcEventProcessor = rig.processor
	rig.backend.set_default("appraise", Rig.distrust("player"))
	rig.backend.hold("appraise")
	processor.observe(_profile(), {}, _observation())
	await _until(func() -> bool: return rig.backend.call_count("appraise") == 1)
	assert_eq(rig.backend.call_count("appraise"), 1)
	assert_eq(processor.store.turn, 0)
	processor.observe(_profile(), {}, _observation("touch"))
	rig.backend.release("appraise")
	await processor.flush("test_observer")
	assert_eq(processor.store.turn, 2)
	var calls: Array[Dictionary] = rig.backend.calls("appraise")
	assert_eq(calls.size(), 2)
	assert_eq(calls[0].evidence[0].modality, "sight")
	assert_eq(calls[0].subjects, ["player"])
	assert_eq(calls[1].evidence[0].modality, "touch")
	assert_eq(calls[1].state.current.past_observations.size(), 1)
	assert_eq(calls[1].state.memories.size(), 1,
		"Observation decisions must be able to recognize a prior related experience")
	# Seeing and feeling one incident spends a single incident budget: -0.1, then the 0.05 left.
	assert_eq(processor.store.snapshot("test_observer").relationship.trust, -0.15)
	assert_eq(rig.backend.call_count("utterance"), 0, "No NPC is attached, so nothing may speak")
	assert_eq(rig.backend.call_count("react"), 0)
	await rig.dispose()

func test_provider_failure_preserves_short_term_observation_without_relationship_change() -> void:
	var rig := Rig.new()
	rig.backend.fail_all = true
	var failed: NpcObservation = _observation()
	rig.processor.observe(_profile(), {}, failed)
	await rig.processor.flush("test_observer")
	var state: Dictionary = rig.processor.store.snapshot("test_observer")
	assert_eq(state.observations[0].status, "pending", "The display entry stays unassessed context")
	var item: Dictionary = rig.processor.store.minds.get_mind("test_observer").evidence.item(
		failed.observation_id)
	assert_eq(item.status, "DEFERRED", "Failed evidence is kept for a later retry")
	assert_eq(item.last_error, "provider_unavailable")
	assert_eq(state.relationship, NpcRelationshipState.initial())
	assert_true(state.memories.is_empty())
	assert_eq(rig.processor.store.turn, 0)
	await rig.dispose()

func test_cooldown_limits_reactions_without_impersonating_player_conversation() -> void:
	var rig := Rig.new()
	rig.backend.set_default("react", {"response": "Keep away!"})
	var npc := _speaker()
	rig.processor.observe(_profile(), {}, _observation(), npc)
	await rig.processor.flush("test_observer")
	rig.processor.observe(_profile(), {}, _observation("touch"), npc)
	await rig.processor.flush("test_observer")
	assert_eq(rig.backend.call_count("appraise"), 2)
	assert_eq(rig.backend.call_count("react"), 1)
	assert_eq(npc.spoken, ["Keep away!"])
	assert_true(rig.processor.store.snapshot("test_observer").recent_dialogue.is_empty())
	await rig.dispose()
	npc.free()

func test_late_reaction_cannot_speak_through_a_freed_npc() -> void:
	var rig := Rig.new()
	var processor: NpcEventProcessor = rig.processor
	rig.backend.set_default("appraise", Rig.distrust("player"))
	rig.backend.set_default("react", {"response": "Keep away!"})
	rig.backend.hold("react")
	var npc := _speaker()
	processor.observe(_profile(), {}, _observation(), npc)
	await _until(func() -> bool: return rig.backend.call_count("react") == 1)
	assert_eq(rig.backend.call_count("react"), 1)
	await processor.wait_for_assessment("test_observer")
	assert_eq(processor.store.snapshot("test_observer").relationship.trust, -0.1)
	processor.observe(_profile(), {}, _observation("touch"), npc)
	await processor.wait_for_assessment("test_observer")
	await _until(func() -> bool: return rig.backend.call_count("appraise") == 2)
	await processor.wait_for_assessment("test_observer")
	assert_eq(processor.store.snapshot("test_observer").relationship.trust, -0.15)
	npc.free()
	rig.backend.release("react")
	await processor.flush("test_observer")
	assert_true(processor.store.snapshot("test_observer").recent_dialogue.is_empty())
	assert_eq(processor.store.snapshot("test_observer").observations[0].diagnostics.speech_result,
		"source_gone")
	await rig.dispose()

func test_background_speech_generation_is_bounded_by_the_text_pool_without_blocking_assessment() -> void:
	var rig := Rig.new()
	var processor: NpcEventProcessor = rig.processor
	rig.backend.set_default("react", {"response": "Keep away!"})
	rig.backend.hold("react")
	var sources: Array[SpeakingNpc] = []
	for index: int in range(3):
		var npc := _speaker()
		sources.append(npc)
		var profile: NpcProfile = _profile()
		profile.npc_id = StringName("speaker_%s" % index)
		processor.observe(profile, {}, _observation("sight", String(profile.npc_id)), npc)
	# Background speech may not take the text permit reserved for interactive and safety work.
	var allowed: int = NpcDecisionService.LIMITS[NpcDecisionService.Pool.TEXT] \
		- NpcDecisionService.INTERACTIVE_RESERVE
	assert_true(allowed <= NpcEventProcessor.MAX_SPEECH_WORKERS)
	await _until(func() -> bool: return processor.store.turn == 3 \
		and rig.backend.call_count("react") == allowed)
	assert_eq(rig.backend.call_count("appraise"), 3)
	assert_eq(processor.store.turn, 3, "Held speech never holds up assessments")
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_eq(rig.backend.call_count("react"), allowed, "Only the unreserved permits are used")
	rig.backend.release("react")
	await _until(func() -> bool: return rig.backend.call_count("react") == 3)
	assert_eq(rig.backend.call_count("react"), 3, "The others start once a permit frees up")
	for index: int in range(3):
		await processor.flush("speaker_%s" % index)
		assert_eq(sources[index].spoken, ["Keep away!"])
	await rig.dispose()
	for source: BaseNpc in sources:
		source.free()

func test_reactions_survive_routine_updates_but_not_new_perception_injury_or_move() -> void:
	for change: String in ["perception", "injury", "space", "routine"]:
		var rig := Rig.new()
		var processor: NpcEventProcessor = rig.processor
		rig.backend.set_default("react", {"response": "Keep away!"})
		rig.backend.hold("react")
		var npc := _speaker()
		processor.observe(_profile(), {}, _observation(), npc)
		await _until(func() -> bool: return rig.backend.call_count("react") == 1)
		assert_eq(rig.backend.call_count("react"), 1)
		match change:
			"perception":
				processor.observe(_profile(), {}, _observation("touch"), npc)
				await _until(func() -> bool: return rig.backend.call_count("appraise") == 2)
				await processor.wait_for_assessment("test_observer")
			"injury":
				npc.health -= 1
			"space":
				npc.world_space = &"home:test"
			"routine":
				npc.life_revision += 1
		rig.backend.release("react")
		await processor.flush("test_observer")
		if change == "routine":
			assert_eq(npc.spoken, ["Keep away!"])
			assert_eq(processor.store.snapshot("test_observer").observations[0].diagnostics.speech_result,
				"displayed")
		else:
			assert_true(npc.spoken.is_empty(), change + " should invalidate the old response")
			assert_eq(processor.store.snapshot("test_observer").observations[0].diagnostics.speech_result,
				"context_changed")
		await rig.dispose()
		npc.free()

func test_speech_needs_a_confident_permitted_intent_and_never_calls_react_otherwise() -> void:
	var cases: Dictionary = {
		"silence_judged": {"speak": 0.0},
		"silence_intent": {"intent": "silence"},
		"below_threshold": {"speak": 0.2},
	}
	for label: String in cases:
		var rig := Rig.new()
		rig.backend.set_default("react", {"response": "Keep away!"})
		rig.backend.set_default("utterance", cases[label])
		var npc := _speaker()
		rig.processor.observe(_profile(), {}, _observation(), npc)
		await rig.processor.flush("test_observer")
		assert_eq(rig.backend.call_count("utterance"), 1, label)
		assert_eq(rig.backend.call_count("react"), 0, label + ": no text is generated for silence")
		assert_true(npc.spoken.is_empty(), label)
		assert_eq(rig.processor.store.snapshot("test_observer").observations[0].diagnostics.speech_result,
			"not_selected", label)
		await rig.dispose()
		npc.free()

func test_utterance_offers_only_intents_the_evidence_permits_plus_silence() -> void:
	var appraisal: NpcDecisionPolicy.Appraisal = Appraisals.make()
	assert_eq(NpcEventProcessor.permitted_intents(_observation(), appraisal), ["remark"] as Array[String])
	assert_eq(NpcEventProcessor.permitted_intents(_observation("touch"), appraisal),
		["remark", "protest"] as Array[String])
	var danger: NpcObservation = NpcObservation.from_perception("test_observer", "event:danger", 500.0,
		&"outdoors", {"kind": "actor_hurt", "text": "I saw a villager fall.", "sense": "sight"})
	assert_eq(NpcEventProcessor.permitted_intents(danger, appraisal),
		["remark", "warn", "call_for_help"] as Array[String])
	var death: NpcObservation = NpcObservation.from_perception("test_observer", "event:death", 500.0,
		&"outdoors", {"kind": "actor_died", "text": "I saw Garrin die.", "sense": "sight"})
	assert_eq(NpcEventProcessor.permitted_intents(death, appraisal),
		["remark", "warn", "call_for_help", "grieve"] as Array[String])
	appraisal.immediate_danger = true
	assert_eq(NpcEventProcessor.permitted_intents(_observation(), appraisal),
		["remark", "warn", "call_for_help"] as Array[String])
	var rig := Rig.new()
	var npc := _speaker()
	rig.backend.set_default("react", {"response": "Keep away!"})
	rig.processor.observe(_profile(), {}, _observation("touch"), npc)
	await rig.processor.flush("test_observer")
	assert_eq(rig.backend.calls("utterance")[0].intents, ["remark", "protest", "silence"])
	assert_eq(rig.backend.calls("react")[0].intent, "remark")
	await rig.dispose()
	npc.free()

func test_speech_expires_in_simulation_minutes_not_real_time() -> void:
	var rig := Rig.new()
	rig.backend.set_default("react", {"response": "Keep away!"})
	var stale := _speaker()
	rig.processor.store.set_world_minute(500.0 + NpcEventProcessor.REACTION_MAX_AGE_MINUTES + 1.0)
	rig.processor.observe(_profile(), {}, _observation(), stale)
	await rig.processor.flush("test_observer")
	assert_eq(rig.backend.call_count("utterance"), 0, "Old evidence never provokes speech")
	assert_true(stale.spoken.is_empty())
	assert_eq(rig.processor.store.snapshot("test_observer").observations[0].diagnostics.speech_result,
		"not_selected")
	# Fresh evidence speaks; time advancing while the line is generated expires it.
	rig.processor.store.set_world_minute(500.0 + NpcEventProcessor.REACTION_MAX_AGE_MINUTES)
	rig.backend.hold("react")
	var fresh := _speaker()
	var profile: NpcProfile = _profile()
	profile.npc_id = &"fresh_observer"
	rig.processor.observe(profile, {}, _observation("sight", "fresh_observer"), fresh)
	await _until(func() -> bool: return rig.backend.call_count("react") == 1)
	assert_eq(rig.backend.call_count("react"), 1, "Thirty minutes old is still fresh")
	rig.processor.store.set_world_minute(500.0 + NpcEventProcessor.REACTION_MAX_AGE_MINUTES + 1.0)
	rig.backend.release("react")
	await rig.processor.flush("fresh_observer")
	assert_true(fresh.spoken.is_empty())
	assert_eq(rig.processor.store.snapshot("fresh_observer").observations[0].diagnostics.speech_result,
		"expired_during_generation")
	await rig.dispose()
	stale.free()
	fresh.free()

func test_each_npc_turn_appraises_one_batch_then_yields_to_the_other_npcs() -> void:
	var rig := Rig.new()
	var processor: NpcEventProcessor = rig.processor
	rig.backend.hold("appraise")
	var ids: Array[String] = ["alpha", "beta", "gamma"]
	for id: String in ids:
		var profile: NpcProfile = _profile()
		profile.npc_id = StringName(id)
		for index: int in range(2):
			processor.observe(profile, {}, _observation("sight", id), null)
	# MAX_WORKERS turns run at once; the third NPC waits for its turn although alpha has more work.
	await _until(func() -> bool: return rig.backend.call_count("appraise") == NpcEventProcessor.MAX_WORKERS)
	assert_eq(rig.backend.call_count("appraise"), NpcEventProcessor.MAX_WORKERS)
	assert_eq(_npcs_asked(rig), ["alpha", "beta"])
	rig.backend.release("appraise")
	await processor.flush("alpha")
	await processor.flush("beta")
	await processor.flush("gamma")
	assert_eq(rig.backend.call_count("appraise"), 6, "Every observation is appraised exactly once")
	var asked: Array[String] = _npcs_asked(rig)
	# Round robin: no NPC is served twice in a row while another one still waits.
	assert_eq(asked.slice(0, 3), ["alpha", "beta", "gamma"], "Gamma is not starved by alpha's backlog")
	for id: String in ids:
		assert_eq(processor.store.minds.get_mind(id).evidence.ready_count(-INF), 0)
		assert_eq(processor.store.minds.get_mind(id).evidence.receipt_count(), 2)
	await rig.dispose()

func test_failed_appraisal_follows_the_retry_ladder_then_backs_off_until_the_provider_recovers() -> void:
	var rig := Rig.new()
	var processor: NpcEventProcessor = rig.processor
	rig.backend.fail_all = true
	var evidence: NpcObservation = _observation()
	processor.observe(_profile(), {}, evidence)
	await processor.flush("test_observer")
	var inbox: NpcEvidenceInbox = processor.store.minds.get_mind("test_observer").evidence
	var attempts: int = 1
	assert_eq(rig.backend.call_count("appraise"), 1)
	# Nothing happens before the step elapses.
	for step: int in NpcEvidenceInbox.RETRY_LADDER_MSEC:
		assert_eq(inbox.item(evidence.observation_id).attempts, attempts)
		rig.now_msec += step - 1
		processor.resume(_profile(), {})
		await processor.flush("test_observer")
		assert_eq(rig.backend.call_count("appraise"), attempts, "Too early to retry after %d ms" % step)
		rig.now_msec += 1
		processor.resume(_profile(), {})
		await processor.flush("test_observer")
		attempts += 1
		assert_eq(rig.backend.call_count("appraise"), attempts, "Retried after %d ms" % step)
	# Past the ladder, retries wait a full minute.
	rig.now_msec += NpcEvidenceInbox.RETRY_BACKOFF_MSEC - 1
	processor.resume(_profile(), {})
	await processor.flush("test_observer")
	assert_eq(rig.backend.call_count("appraise"), attempts)
	rig.now_msec += 1
	processor.resume(_profile(), {})
	await processor.flush("test_observer")
	attempts += 1
	assert_eq(rig.backend.call_count("appraise"), attempts)
	assert_eq(inbox.item(evidence.observation_id).status, "DEFERRED")
	# A healthy provider answering for anyone wakes the backoff of everyone's deferred evidence.
	var other: NpcProfile = _profile()
	other.npc_id = &"other_observer"
	rig.backend.fail_all = false
	processor.observe(other, {}, _observation("sight", "other_observer"))
	await processor.flush("other_observer")
	assert_eq(rig.backend.call_count("appraise"), attempts + 1)
	processor.resume(_profile(), {})
	await processor.flush("test_observer")
	assert_eq(rig.backend.call_count("appraise"), attempts + 2, "Woken without waiting out the backoff")
	assert_true(inbox.has_receipt(evidence.observation_id))
	assert_eq(processor.store.snapshot("test_observer").memories.size(), 1, "Appraised exactly once")
	await rig.dispose()

func test_dialogue_waits_at_most_two_seconds_for_a_pending_assessment() -> void:
	assert_eq(NpcEventProcessor.ASSESSMENT_WAIT_MSEC, 2000)
	var rig := Rig.new()
	var processor: NpcEventProcessor = rig.processor
	rig.backend.hold("appraise")
	var stuck: NpcObservation = _observation()
	processor.observe(_profile(), {}, stuck)
	await _until(func() -> bool: return rig.backend.call_count("appraise") == 1)
	var started: int = Time.get_ticks_msec()
	await processor.wait_for_assessment("test_observer")
	var waited: int = Time.get_ticks_msec() - started
	assert_true(waited >= NpcEventProcessor.ASSESSMENT_WAIT_MSEC, "Waited %d ms" % waited)
	assert_true(waited < NpcEventProcessor.ASSESSMENT_WAIT_MSEC + 1000, "Waited %d ms" % waited)
	var state: Dictionary = processor.store.snapshot("test_observer")
	assert_eq(state.observations[0].status, "pending", "Unassessed evidence stays context")
	var context: Dictionary = NpcCognitiveContext.build(state, {"world_minute": 501.0})
	assert_eq(context.current_concerns.size(), 1)
	rig.backend.release("appraise")
	await processor.flush("test_observer")
	assert_true(processor.store.minds.get_mind("test_observer").evidence.has_receipt(stuck.observation_id))
	await rig.dispose()

func test_cancelling_an_npc_commits_nothing_and_keeps_the_evidence_for_a_later_resume() -> void:
	var rig := Rig.new()
	var processor: NpcEventProcessor = rig.processor
	rig.backend.set_default("appraise", Rig.distrust("player"))
	rig.backend.hold("appraise")
	var evidence: NpcObservation = _observation()
	processor.observe(_profile(), {}, evidence)
	await _until(func() -> bool: return rig.backend.call_count("appraise") == 1)
	processor.cancel("test_observer")
	await processor.flush("test_observer")
	var inbox: NpcEvidenceInbox = processor.store.minds.get_mind("test_observer").evidence
	var state: Dictionary = processor.store.snapshot("test_observer")
	assert_true(state.memories.is_empty())
	assert_eq(state.relationship, NpcRelationshipState.initial())
	assert_eq(processor.store.turn, 0)
	assert_false(inbox.has_receipt(evidence.observation_id))
	assert_eq(inbox.item(evidence.observation_id).status, "PENDING", "Released without an attempt")
	assert_eq(inbox.item(evidence.observation_id).attempts, 0)
	assert_false(processor.is_busy("test_observer"))
	rig.backend.release("appraise")
	processor.resume(_profile(), {})
	await processor.flush("test_observer")
	assert_true(inbox.has_receipt(evidence.observation_id))
	assert_eq(processor.store.snapshot("test_observer").relationship.trust, -0.1)
	await rig.dispose()

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
