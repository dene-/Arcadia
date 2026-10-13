extends "res://tests/test_case.gd"

## Characterizes audited cognition defects. Each test pins today's behavior and is flipped by the named milestone.

func _profile() -> NpcProfile:
	var profile := NpcProfile.new()
	profile.npc_id = &"test_observer"
	return profile

func _event(text: String, sense: String = "sight") -> Dictionary:
	return {"text": text, "sense": sense, "player_involved": false}

func _policy() -> Dictionary:
	return {"remember": true, "retrieve": false, "update_belief": false, "speak": false,
		"importance": 0.8, "emotional_intensity": 0.7, "response_mode": "NEUTRAL",
		"relationship_delta": {"familiarity": 0.0, "trust": 0.0, "respect": 0.0,
			"affection": 0.0, "fear": 0.0, "suspicion": 0.0}}

# Flipped by M2: death evidence must not be evicted while it is still pending.
func test_characterize_pending_death_evidence_is_evicted_by_newer_observations() -> void:
	var store := NpcMemoryStore.new()
	store.record_observation(_profile(), _event("I found Garrin dead."))
	for index: int in range(8):
		store.record_observation(_profile(), _event("I saw a villager walk past (%d)." % index))
	var observations: Array = store.snapshot("test_observer").observations
	assert_eq(observations.size(), 8)
	var texts: Array = observations.map(func(item: Dictionary) -> String: return item.text)
	assert_false("I found Garrin dead." in texts, "The pending death observation should be evicted today")
	assert_eq(store.pending_observations("test_observer").size(), 8)

# Flipped by M2: a reported death must be remembered as hearsay about the deceased, not as combat noise.
func test_characterize_reported_body_is_remembered_as_sounds_of_fighting_without_the_deceased() -> void:
	var store := NpcMemoryStore.new()
	var event: Dictionary = {"kind": "body_reported",
		"text": "Voss told me they found Garrin Holt dead. The cause is unconfirmed.",
		"sense": "hearing", "player_involved": false, "danger_possible": false,
		"directly_affected": false, "topics": ["death", "town"],
		"participants": [{"id": "garrin_holt", "name": "Garrin Holt", "role": "deceased",
			"relationship": "neighbor"}]}
	store.record_observation(_profile(), event)
	assert_true(store.commit_observation("test_observer", 1, _policy()))
	var memories: Array = store.snapshot("test_observer").memories
	assert_eq(memories.size(), 1)
	assert_eq(memories[0].sensory_cues, ["sounds of fighting"])
	assert_false("garrin_holt" in memories[0].people, "The deceased is not recorded as a participant today")

# Flipped by M2: a failed classification should remain retryable work instead of being dropped.
func test_characterize_classifier_failure_drops_pending_work_permanently() -> void:
	var store := NpcMemoryStore.new()
	store.record_observation(_profile(), _event("I saw smoke over the mill."))
	assert_eq(store.pending_observations("test_observer").size(), 1)
	assert_false(store.commit_observation("test_observer", 1, {}))
	assert_eq(store.snapshot("test_observer").observations[0].status, "unavailable")
	assert_true(store.pending_observations("test_observer").is_empty(), "No retry work remains today")

# Flipped by M5: burial must pass through recovery and carrying stages.
func test_characterize_fallen_body_can_be_buried_without_recovery_stages() -> void:
	var deaths := TownDeaths.new()
	deaths.record("garrin_holt", "outdoors", Vector2(12, 34), 480.0)
	assert_eq(deaths.records.garrin_holt.stage, "fallen")
	deaths.transition("garrin_holt", "buried", 500.0)
	assert_eq(deaths.records.garrin_holt.stage, "buried")
	assert_eq(deaths.records.garrin_holt.since, 500.0)
