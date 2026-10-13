extends "res://tests/test_case.gd"

## Pins corrected cognition behavior. The M5 test below still characterizes today's burial flow.

func _profile() -> NpcProfile:
	var profile := NpcProfile.new()
	profile.npc_id = &"test_observer"
	return profile

func _observation(origin: String, text: String, perceived: Dictionary = {}) -> NpcObservation:
	var data: Dictionary = {"text": text, "sense": "sight", "player_involved": false}
	data.merge(perceived, true)
	return NpcObservation.from_perception("test_observer", origin, 500.0, &"outdoors", data)

func _policy() -> Dictionary:
	return {"remember": true, "retrieve": false, "update_belief": false, "speak": false,
		"importance": 0.8, "emotional_intensity": 0.7, "response_mode": "NEUTRAL",
		"relationship_delta": {"familiarity": 0.0, "trust": 0.0, "respect": 0.0,
			"affection": 0.0, "fear": 0.0, "suspicion": 0.0}}

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
	assert_true(store.commit_evidence("test_observer", claimed, _policy()))
	assert_true(inbox.complete(claimed.observation_id))
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
	var policy: Dictionary = _policy()
	policy.relationship_delta.trust = 0.1
	var before: float = store.minds.get_mind("test_observer").relationships.get_relationship("player").trust
	assert_true(store.commit_evidence("test_observer", observation, policy))
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
	assert_false(store.commit_evidence("test_observer", observation, {}))
	assert_true(inbox.fail(observation.observation_id, "provider_unavailable", 500.0))
	assert_eq(inbox.item(observation.observation_id).status, "DEFERRED", "The evidence stays as retry work")
	assert_eq(inbox.ready_count(500.5), 0, "Not eligible before the retry delay")
	assert_eq(inbox.ready_count(502.0), 1)
	var retry: NpcObservation = inbox.claim(observation.observation_id, 502.0)
	assert_true(store.commit_evidence("test_observer", retry, _policy()))
	assert_true(inbox.complete(retry.observation_id))
	assert_eq(store.snapshot("test_observer").memories.size(), 1, "Appraised exactly once")
	assert_false(inbox.enqueue(observation), "A replay of the processed id is refused")
	assert_eq(inbox.ready_count(600.0), 0)

# Flipped by M5: burial must pass through recovery and carrying stages.
func test_characterize_fallen_body_can_be_buried_without_recovery_stages() -> void:
	var deaths := TownDeaths.new()
	deaths.record("garrin_holt", "outdoors", Vector2(12, 34), 480.0)
	assert_eq(deaths.records.garrin_holt.stage, "fallen")
	deaths.transition("garrin_holt", "buried", 500.0)
	assert_eq(deaths.records.garrin_holt.stage, "buried")
	assert_eq(deaths.records.garrin_holt.since, 500.0)
