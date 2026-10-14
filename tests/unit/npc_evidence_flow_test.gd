extends "res://tests/test_case.gd"

const Rig = preload("res://tests/fixtures/npc_processor_rig.gd")
const CognitionScript = preload("res://game/actors/npcs/npc_cognition.gd")

const OBSERVER: String = "witness"

var _serial: int = 0

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

func test_noise_burst_is_coalesced_and_an_early_death_is_appraised_once() -> void:
	var rig := Rig.new()
	var processor: NpcEventProcessor = rig.processor
	var death: NpcObservation = _death()
	processor.observe(_profile(), {}, death)
	for index: int in range(100):
		processor.observe(_profile(), {}, _noise(501.0 + index * 0.1))
	await processor.flush(OBSERVER)
	var seen: Array[String] = []
	var calls: Array[Dictionary] = rig.backend.calls("appraise")
	for call: Dictionary in calls:
		assert_eq(call.evidence.size(), 1)
		assert_false(call.evidence[0].id in seen, "At most one appraisal per observation id")
		seen.append(call.evidence[0].id)
	assert_eq(calls.size(), 2, "One death plus one coalesced noise incident")
	assert_eq(calls[0].evidence[0].id, death.observation_id, "Protected evidence is appraised first")
	assert_eq(calls[0].evidence[0].modality, "sight")
	assert_eq(calls[1].evidence[0].modality, "noise")
	var inbox: NpcEvidenceInbox = processor.store.minds.get_mind(OBSERVER).evidence
	assert_true(inbox.has_receipt(death.observation_id))
	assert_eq(inbox.ready_count(-INF), 0)
	assert_eq(processor.store.snapshot(OBSERVER).memories.size(), 2)
	await rig.dispose()

func test_second_enqueue_of_a_processed_id_changes_nothing() -> void:
	var rig := Rig.new()
	rig.backend.set_default("appraise", Rig.distrust("player"))
	var processor: NpcEventProcessor = rig.processor
	var seen: NpcObservation = _observation({"player_involved": true,
		"text": "I saw the player hurt a villager.", "participants": [
			{"id": "player", "name": "the player", "role": "aggressor"}]})
	processor.observe(_profile(), {}, seen)
	await processor.flush(OBSERVER)
	var trust: float = processor.store.snapshot(OBSERVER).relationship.trust
	assert_eq(trust, -0.1)
	processor.observe(_profile(), {}, seen)
	await processor.flush(OBSERVER)
	assert_eq(rig.backend.call_count("appraise"), 1, "The replay must not reach the provider")
	assert_eq(processor.store.snapshot(OBSERVER).relationship.trust, trust)
	assert_eq(processor.store.snapshot(OBSERVER).memories.size(), 1)
	assert_eq(processor.store.snapshot(OBSERVER).observations.size(), 1)
	await rig.dispose()

func test_provider_failure_defers_evidence_wait_returns_and_retry_appraises_once() -> void:
	var rig := Rig.new()
	rig.backend.fail_all = true
	var processor: NpcEventProcessor = rig.processor
	var evidence: NpcObservation = _death()
	processor.observe(_profile(), {}, evidence)
	await processor.wait_for_assessment(OBSERVER)
	await processor.flush(OBSERVER)
	var inbox: NpcEvidenceInbox = processor.store.minds.get_mind(OBSERVER).evidence
	assert_eq(inbox.item(evidence.observation_id).status, "DEFERRED")
	assert_eq(processor.store.snapshot(OBSERVER).memories.size(), 0)
	# A deferred item neither holds a conversation nor retries before its delay.
	var started: int = Time.get_ticks_msec()
	await processor.wait_for_assessment(OBSERVER)
	assert_true(Time.get_ticks_msec() - started < NpcEventProcessor.ASSESSMENT_WAIT_MSEC)
	rig.now_msec += NpcEvidenceInbox.RETRY_LADDER_MSEC[0] - 1
	processor.resume(_profile(), {})
	await processor.flush(OBSERVER)
	assert_eq(rig.backend.call_count("appraise"), 1)
	rig.backend.fail_all = false
	rig.now_msec += 1
	processor.resume(_profile(), {})
	await processor.flush(OBSERVER)
	assert_eq(rig.backend.call_count("appraise"), 2)
	assert_true(inbox.has_receipt(evidence.observation_id))
	assert_eq(processor.store.snapshot(OBSERVER).memories.size(), 1, "Appraised exactly once")
	processor.resume(_profile(), {})
	await processor.flush(OBSERVER)
	assert_eq(rig.backend.call_count("appraise"), 2)
	await rig.dispose()

func test_appraisal_request_carries_evidence_without_runtime_or_display_fields() -> void:
	var rig := Rig.new()
	var processor: NpcEventProcessor = rig.processor
	processor.observe(_profile(), {}, _death())
	await processor.flush(OBSERVER)
	var evidence: Dictionary = rig.backend.calls("appraise")[0].evidence[0]
	assert_eq(evidence.keys(), ["id", "text", "modality", "source_id", "participant_ids"])
	assert_eq(evidence.participant_ids, ["garrin_holt", "voss"])
	assert_eq(rig.backend.calls("appraise")[0].subjects, ["garrin_holt", "voss"],
		"Direct evidence names the people whose dispositions it may change")
	assert_eq(rig.backend.call_count("utterance"), 0, "No live NPC is attached, so nothing may speak")
	await rig.dispose()

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
