extends "res://tests/test_case.gd"

const Appraisals = preload("res://tests/fixtures/npc_appraisal_fixture.gd")

## Pins corrected cognition behavior. The M5 test below still characterizes today's burial flow.

func _profile() -> NpcProfile:
	var profile := NpcProfile.new()
	profile.npc_id = &"test_observer"
	return profile

func _observation(origin: String, text: String, perceived: Dictionary = {}) -> NpcObservation:
	var data: Dictionary = {"text": text, "sense": "sight", "player_involved": false}
	data.merge(perceived, true)
	return NpcObservation.from_perception("test_observer", origin, 500.0, &"outdoors", data)

func _policy() -> NpcDecisionPolicy.Appraisal:
	return Appraisals.make(true, 0.8, 0.7)

func test_death_evidence_stays_pending_in_the_inbox_under_newer_observations_and_is_appraised() -> void:
	var store := NpcMemoryStore.new()
	var inbox: NpcEvidenceInbox = store.minds.get_mind("test_observer").evidence
	var death: NpcObservation = _observation("event:death", "I found Garrin dead.",
		{"kind": "actor_died", "participants": [{"id": "garrin_holt", "name": "Garrin Holt",
			"role": "hurt_person"}]})
	assert_true(inbox.enqueue(death))
	store.record_observation(_profile(), death.to_event(), 500.0)
	for index: int in range(12):
		var walker: NpcObservation = _observation("event:walk:%d" % index,
			"I saw a villager walk past (%d)." % index)
		inbox.enqueue(walker)
		store.record_observation(_profile(), walker.to_event(), 501.0 + index)
	var texts: Array = store.snapshot("test_observer").observations.map(
		func(item: Dictionary) -> String: return item.text)
	assert_false("I found Garrin dead." in texts, "Only the display window forgets the death")
	assert_true(inbox.contains_pending(death.observation_id), "The inbox still holds the death")
	var claimed: NpcObservation = inbox.next_ready(520.0)
	assert_eq(claimed.observation_id, death.observation_id, "Protected death evidence is appraised first")
	inbox.claim(claimed.observation_id, 520.0)
	assert_eq(store.commit_evidence("test_observer", claimed, _policy()), "")
	assert_true(inbox.has_receipt(death.observation_id))
	assert_eq(store.snapshot("test_observer").memories.size(), 1)
	assert_eq(store.snapshot("test_observer").memories[0].gist, "I found Garrin dead.")

func test_reported_body_is_remembered_as_hearsay_about_the_deceased_and_reporter() -> void:
	var store := NpcMemoryStore.new()
	var event: Dictionary = {"kind": "body_reported",
		"text": "Voss told me they found Garrin Holt dead. The cause is unconfirmed.",
		"sense": "hearing", "player_involved": false, "danger_possible": false,
		"directly_affected": false, "topics": ["death", "town"],
		"participants": [{"id": "garrin_holt", "name": "Garrin Holt", "role": "deceased",
			"relationship": "neighbor"},
			{"id": "voss", "name": "Voss", "role": "reporter"}]}
	store.ensure_npc(_profile())
	var inbox: NpcEvidenceInbox = store.minds.get_mind("test_observer").evidence
	var observation: NpcObservation = NpcObservation.from_perception("test_observer",
		"event:report", 500.0, &"outdoors", event)
	inbox.enqueue(observation)
	inbox.claim(observation.observation_id, 500.0)
	var policy: NpcDecisionPolicy.Appraisal = _policy()
	policy.dispositions["player"] = {"trust": 0.1}
	var before: float = store.minds.get_mind("test_observer").relationships.get_relationship("player").trust
	assert_eq(store.commit_evidence("test_observer", observation, policy), "")
	var memories: Array = store.snapshot("test_observer").memories
	assert_eq(memories.size(), 1)
	assert_eq(memories[0].source, "hearsay")
	assert_true("garrin_holt" in memories[0].people)
	assert_true("voss" in memories[0].people)
	assert_false("sounds of fighting" in memories[0].sensory_cues, "A report is not combat noise")
	assert_eq(memories[0].topics, ["death", "town"])
	assert_eq(store.minds.get_mind("test_observer").relationships.get_relationship("player").trust,
		before, "A report heard from a resident never moves the player's trust")

func test_provider_failure_defers_evidence_and_a_later_attempt_appraises_it_once() -> void:
	var store := NpcMemoryStore.new()
	store.ensure_npc(_profile())
	var inbox: NpcEvidenceInbox = store.minds.get_mind("test_observer").evidence
	var observation: NpcObservation = _observation("event:smoke", "I saw smoke over the mill.")
	inbox.enqueue(observation)
	inbox.claim(observation.observation_id, 500.0)
	assert_eq(store.commit_evidence("test_observer", observation, null), "invalid_appraisal")
	assert_eq(inbox.item(observation.observation_id).status, "CLAIMED",
		"A rejected commit leaves the claim for the caller to fail")
	assert_true(inbox.fail(observation.observation_id, "provider_unavailable", 500.0))
	assert_eq(inbox.item(observation.observation_id).status, "DEFERRED", "The evidence stays as retry work")
	assert_eq(inbox.ready_count(2499.0), 0, "Not eligible before the first retry step (2 s)")
	assert_eq(inbox.ready_count(2500.0), 1)
	var retry: NpcObservation = inbox.claim(observation.observation_id, 2500.0)
	assert_eq(store.commit_evidence("test_observer", retry, _policy()), "")
	assert_true(inbox.has_receipt(retry.observation_id), "Committing completed the claim")
	assert_eq(store.snapshot("test_observer").memories.size(), 1, "Appraised exactly once")
	assert_false(inbox.enqueue(observation), "A replay of the processed id is refused")
	assert_eq(inbox.ready_count(600.0), 0)

func test_burial_requires_discovery_acknowledgment_and_pickup() -> void:
	var deaths := TownDeaths.new()
	deaths.record("garrin_holt", "outdoors", Vector2(12, 34), 480.0)
	var fallen: Dictionary = deaths.snapshot("garrin_holt")
	assert_eq(fallen.stage, "fallen")
	assert_ne(deaths.bury("garrin_holt", "vale_guard", 500.0), TownDeaths.OK_RESULT, "Not even discovered")
	assert_eq(deaths.snapshot("garrin_holt"), fallen)
	assert_eq(deaths.discover("garrin_holt", "witness", 490.0), TownDeaths.OK_RESULT)
	var discovered: Dictionary = deaths.snapshot("garrin_holt")
	assert_ne(deaths.bury("garrin_holt", "vale_guard", 500.0), TownDeaths.OK_RESULT, "Not acknowledged")
	assert_eq(deaths.snapshot("garrin_holt"), discovered)
	assert_eq(deaths.acknowledge_report("garrin_holt", "vale_guard", "witness", 495.0), TownDeaths.OK_RESULT)
	assert_eq(deaths.begin_recovery("garrin_holt", "vale_guard", 496.0), TownDeaths.OK_RESULT)
	var recovering: Dictionary = deaths.snapshot("garrin_holt")
	assert_ne(deaths.bury("garrin_holt", "vale_guard", 500.0), TownDeaths.OK_RESULT, "Not picked up")
	assert_eq(deaths.snapshot("garrin_holt"), recovering)
