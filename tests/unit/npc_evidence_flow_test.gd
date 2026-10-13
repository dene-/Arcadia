extends "res://tests/test_case.gd"

const ObservationTests = preload("res://tests/unit/npc_observation_test.gd")
const CognitionScript = preload("res://game/actors/npcs/npc_cognition.gd")

const OBSERVER: String = "witness"

var _serial: int = 0

func _policy() -> Dictionary:
	var policy: Dictionary = ObservationTests.new()._policy()
	policy.speak = false
	return policy

func _observation(perceived: Dictionary, observer: String = OBSERVER,
		minute: float = 500.0) -> NpcObservation:
	_serial += 1
	var data: Dictionary = {"text": "I saw something.", "sense": "sight", "player_involved": false}
	data.merge(perceived, true)
	return NpcObservation.from_perception(observer, "event:%d" % _serial, minute, &"outdoors", data)

func _death(minute: float = 500.0) -> NpcObservation:
	return _observation({"kind": "actor_died", "text": "I saw Garrin Holt die nearby.",
		"topics": ["combat", "death"], "participants": [
			{"id": "garrin_holt", "name": "Garrin Holt", "role": "hurt_person"},
			{"id": "voss", "name": "Voss", "role": "aggressor"}]}, OBSERVER, minute)

func _noise(minute: float = 501.0) -> NpcObservation:
	return _observation({"kind": "combat_noise", "sense": "hearing",
		"text": "I heard sounds of fighting nearby, but could not see what happened.",
		"topics": ["combat"]}, OBSERVER, minute)

func _report() -> NpcObservation:
	return _observation({"kind": "body_reported", "sense": "hearing",
		"text": "Voss told me they found Garrin Holt dead. The cause is unconfirmed.",
		"topics": ["death", "town"], "participants": [
			{"id": "garrin_holt", "name": "Garrin Holt", "role": "deceased"},
			{"id": "voss", "name": "Voss", "role": "reporter"}]})

func _profile(id: String = OBSERVER) -> NpcProfile:
	var profile := NpcProfile.new()
	profile.npc_id = StringName(id)
	return profile

func _processor(backend: DialogBackendClient) -> NpcEventProcessor:
	var processor := NpcEventProcessor.new()
	processor.persist = false
	processor.store = NpcMemoryStore.new()
	processor.backend = backend
	(Engine.get_main_loop() as SceneTree).root.add_child(processor)
	return processor

func _release(processor: NpcEventProcessor, backend: Node) -> void:
	processor.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame
	backend.free()

func test_noise_burst_is_coalesced_and_an_early_death_is_appraised_once() -> void:
	var backend := ObservationTests.FakeBackend.new()
	backend.policy = _policy()
	var processor: NpcEventProcessor = _processor(backend)
	var death: NpcObservation = _death()
	processor.observe(_profile(), {}, death)
	for index: int in range(100):
		processor.observe(_profile(), {}, _noise(501.0 + index * 0.1))
	await processor.flush(OBSERVER)
	var seen: Array[String] = []
	for payload: Dictionary in backend.payloads:
		assert_false(payload.event.observation_id in seen, "At most one appraisal per observation id")
		seen.append(payload.event.observation_id)
	assert_eq(backend.payloads.size(), 2, "One death plus one coalesced noise incident")
	assert_eq(backend.payloads[0].event.kind, "actor_died", "Protected evidence is appraised first")
	assert_eq(backend.payloads[0].event.observation_id, death.observation_id)
	var inbox: NpcEvidenceInbox = processor.store.minds.get_mind(OBSERVER).evidence
	assert_true(inbox.has_receipt(death.observation_id))
	assert_eq(inbox.ready_count(-INF), 0)
	assert_eq(processor.store.snapshot(OBSERVER).memories.size(), 2)
	await _release(processor, backend)

func test_second_enqueue_of_a_processed_id_changes_nothing() -> void:
	var backend := ObservationTests.FakeBackend.new()
	backend.policy = _policy()
	var processor: NpcEventProcessor = _processor(backend)
	var seen: NpcObservation = _observation({"player_involved": true,
		"text": "I saw the player hurt a villager."})
	processor.observe(_profile(), {}, seen)
	await processor.flush(OBSERVER)
	var trust: float = processor.store.snapshot(OBSERVER).relationship.trust
	assert_eq(trust, -0.08)
	processor.observe(_profile(), {}, seen)
	await processor.flush(OBSERVER)
	assert_eq(backend.payloads.size(), 1, "The replay must not reach the provider")
	assert_eq(processor.store.snapshot(OBSERVER).relationship.trust, trust)
	assert_eq(processor.store.snapshot(OBSERVER).memories.size(), 1)
	assert_eq(processor.store.snapshot(OBSERVER).observations.size(), 1)
	await _release(processor, backend)

func test_provider_failure_defers_evidence_wait_returns_and_retry_appraises_once() -> void:
	var backend := ObservationTests.FakeBackend.new()
	backend.policy = _policy()
	backend.fail = true
	var processor: NpcEventProcessor = _processor(backend)
	var evidence: NpcObservation = _death()
	processor.observe(_profile(), {}, evidence)
	await processor.wait_for_assessment(OBSERVER)
	var inbox: NpcEvidenceInbox = processor.store.minds.get_mind(OBSERVER).evidence
	assert_eq(inbox.item(evidence.observation_id).status, "DEFERRED")
	assert_eq(processor.store.snapshot(OBSERVER).memories.size(), 0)
	# A deferred item neither holds a conversation nor retries before its delay.
	await processor.wait_for_assessment(OBSERVER)
	processor.resume(_profile(), {})
	await processor.flush(OBSERVER)
	assert_eq(backend.payloads.size(), 1)
	backend.fail = false
	processor.store.set_world_minute(processor.store.world_minute + NpcEvidenceInbox.RETRY_DELAY_MINUTES)
	processor.resume(_profile(), {})
	await processor.flush(OBSERVER)
	assert_eq(backend.payloads.size(), 2)
	assert_true(inbox.has_receipt(evidence.observation_id))
	assert_eq(processor.store.snapshot(OBSERVER).memories.size(), 1, "Appraised exactly once")
	processor.resume(_profile(), {})
	await processor.flush(OBSERVER)
	assert_eq(backend.payloads.size(), 2)
	await _release(processor, backend)

func test_payload_event_carries_evidence_without_runtime_or_display_fields() -> void:
	var backend := ObservationTests.FakeBackend.new()
	backend.policy = _policy()
	var processor: NpcEventProcessor = _processor(backend)
	processor.observe(_profile(), {}, _death())
	await processor.flush(OBSERVER)
	var event: Dictionary = backend.payloads[0].event
	for key: String in ["text", "sense", "player_involved", "speech_allowed", "observation_id", "kind"]:
		assert_true(event.has(key), key)
	for key: String in ["id", "created_at", "status", "decision"]:
		assert_false(event.has(key), key)
	assert_false(event.speech_allowed, "No live NPC is attached, so nothing may speak")
	await _release(processor, backend)

func test_a_seen_death_is_known_as_observed_with_sightings_and_no_provider() -> void:
	var knowledge := NpcKnowledge.new()
	var death: NpcObservation = _death()
	CognitionScript.learn(knowledge, death, {"garrin_holt": Vector2(10, 20), "voss": Vector2(30, 40)})
	var status: Array[Dictionary] = knowledge.current("garrin_holt", "status")
	assert_eq(status.size(), 1)
	assert_eq(status[0].value, "dead")
	assert_eq(status[0].status, "OBSERVED")
	assert_eq(status[0].source_id, NpcKnowledge.SELF_SOURCE)
	assert_eq(knowledge.known_locations("garrin_holt")[0].value.x, 10.0)
	assert_eq(knowledge.known_locations("voss")[0].value.y, 40.0)

func test_heard_evidence_never_locates_anyone_and_the_observer_is_not_a_sighting() -> void:
	var knowledge := NpcKnowledge.new()
	var noise: NpcObservation = _observation({"kind": "combat_noise", "sense": "hearing",
		"text": "I heard sounds of fighting.", "participants": [
			{"id": "garrin_holt", "name": "Garrin Holt", "role": "hurt_person"}]})
	CognitionScript.learn(knowledge, noise, {"garrin_holt": Vector2(1, 2)})
	assert_false(knowledge.knows("garrin_holt", "location"))
	assert_false(knowledge.knows("garrin_holt", "status"))
	var touched: NpcObservation = _observation({"kind": "actor_hurt", "sense": "touch",
		"text": "I was hurt by Voss.", "participants": [
			{"id": OBSERVER, "name": "Me", "role": "hurt_person"},
			{"id": "voss", "name": "Voss", "role": "aggressor"}]})
	CognitionScript.learn(knowledge, touched, {OBSERVER: Vector2(5, 5), "voss": Vector2(9, 9)})
	assert_false(knowledge.knows(OBSERVER, "location"), "Residents are not told where they are")
	assert_eq(knowledge.known_locations("voss").size(), 1)
	assert_false(knowledge.knows("garrin_holt", "status"), "A wound is not a death")

func test_a_spoken_report_is_reported_knowledge_without_a_location() -> void:
	var knowledge := NpcKnowledge.new()
	var report: NpcObservation = _report()
	CognitionScript.learn(knowledge, report, {"garrin_holt": Vector2(10, 20)})
	var status: Array[Dictionary] = knowledge.current("garrin_holt", "status")
	assert_eq(status.size(), 1)
	assert_eq(status[0].status, "REPORTED")
	assert_eq(status[0].source_id, "voss")
	assert_false(knowledge.knows("garrin_holt", "location"), "Hearsay never places the body")
	var found: NpcObservation = _observation({"kind": "body_found", "text": "I found Garrin's body.",
		"participants": [{"id": "garrin_holt", "name": "Garrin Holt", "role": "deceased"}]})
	CognitionScript.learn(knowledge, found, {"garrin_holt": Vector2(10, 20)})
	assert_eq(knowledge.current("garrin_holt", "status")[0].status, "OBSERVED")
	assert_eq(knowledge.known_locations("garrin_holt").size(), 1)

func test_burial_is_observed_when_seen_and_reported_when_told() -> void:
	var seen := NpcKnowledge.new()
	CognitionScript.learn(seen, _observation({"kind": "body_buried", "text": "I saw Garrin buried.",
		"participants": [{"id": "garrin_holt", "name": "Garrin Holt", "role": "deceased"}]}), {})
	assert_eq(seen.current("garrin_holt", "burial")[0].status, "OBSERVED")
	assert_eq(seen.current("garrin_holt", "burial")[0].value, "buried")

func test_an_observer_who_perceived_nothing_knows_nothing_about_the_victim() -> void:
	var save := NpcWorldSave.new()
	var present: NpcKnowledge = save.minds.get_mind("present").knowledge
	var absent: NpcKnowledge = save.minds.get_mind("absent").knowledge
	CognitionScript.learn(present, _observation({"kind": "actor_died", "text": "I saw Garrin die.",
		"participants": [{"id": "garrin_holt", "name": "Garrin Holt", "role": "hurt_person"}]},
		"present"), {"garrin_holt": Vector2(10, 20)})
	assert_true(present.knows("garrin_holt", "location"))
	assert_false(absent.knows("garrin_holt", "location"))
	assert_false(absent.knows("garrin_holt", "status"))
