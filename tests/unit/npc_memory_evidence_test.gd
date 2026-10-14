extends "res://tests/test_case.gd"

const CognitionScript = preload("res://game/actors/npcs/npc_cognition.gd")
const Appraisals = preload("res://tests/fixtures/npc_appraisal_fixture.gd")

const OBSERVER: String = "elder"
const DECEASED: String = "garrin_holt"

var _serial: int = 0

func _profile(id: String = OBSERVER) -> NpcProfile:
	var profile := NpcProfile.new()
	profile.npc_id = StringName(id)
	return profile

func _policy(remember: bool = true, trust: float = 0.0) -> NpcDecisionPolicy.Appraisal:
	return Appraisals.player_trust(trust, remember)

func _perceive(kind: String, sense: String, text: String, participants: Array,
		minute: float = 500.0, observer: String = OBSERVER, player_involved: bool = false) -> NpcObservation:
	_serial += 1
	var observation: NpcObservation = NpcObservation.from_perception(observer, "event:%d" % _serial,
		minute, &"outdoors", {"kind": kind, "sense": sense, "text": text, "topics": ["death"],
		"player_involved": player_involved, "participants": participants})
	assert_not_null(observation)
	return observation

func _death(text: String = "I saw Garrin die.", minute: float = 500.0) -> NpcObservation:
	return _perceive("actor_died", "sight", text,
		[{"id": DECEASED, "name": "Garrin Holt", "role": "deceased"}], minute)

func _report(text: String = "Voss told me Garrin is dead.", minute: float = 510.0) -> NpcObservation:
	return _perceive("body_reported", "hearing", text,
		[{"id": DECEASED, "name": "Garrin Holt", "role": "deceased"},
		{"id": "voss", "name": "Voss", "role": "reporter"}], minute)

func _hit() -> NpcObservation:
	return _perceive("actor_hurt", "sight", "I saw the player strike Mira.",
		[{"id": "player", "name": "the player", "role": "aggressor"}], 500.0, OBSERVER, true)

func _store() -> NpcMemoryStore:
	var store := NpcMemoryStore.new()
	store.ensure_npc(_profile())
	return store

func _inbox(store: NpcMemoryStore, observer: String = OBSERVER) -> NpcEvidenceInbox:
	return store.minds.get_mind(observer).evidence

func _claim(store: NpcMemoryStore, observation: NpcObservation) -> NpcObservation:
	assert_true(_inbox(store, observation.observer_id).enqueue(observation))
	var claimed: NpcObservation = _inbox(store, observation.observer_id).claim(
		observation.observation_id, 500.0)
	assert_not_null(claimed)
	return claimed

## Mirrors the processor: enqueue, claim, commit.
func _commit(store: NpcMemoryStore, observation: NpcObservation,
		policy: NpcDecisionPolicy.Appraisal = _policy()) -> String:
	return store.commit_evidence(observation.observer_id, _claim(store, observation), policy)

func _memories(store: NpcMemoryStore, observer: String = OBSERVER) -> Array:
	return store.snapshot(observer).memories

func _trust(store: NpcMemoryStore) -> float:
	return float(store.minds.get_mind(OBSERVER).relationships.get_relationship("player").trust)

func test_a_missing_store_state_is_its_own_reason_and_keeps_the_evidence_claimed() -> void:
	var store := NpcMemoryStore.new()
	var claimed: NpcObservation = _claim(store, _death())
	assert_eq(store.commit_evidence(OBSERVER, claimed, _policy()), "store_unavailable")
	assert_false(_inbox(store).has_receipt(claimed.observation_id), "Nothing was completed")
	assert_true(store.snapshot(OBSERVER).is_empty())
	store.ensure_npc(_profile())
	assert_eq(store.commit_evidence(OBSERVER, claimed, _policy()), "",
		"The same claim commits once the store exists")
	assert_eq(_memories(store).size(), 1)

func test_unclaimed_evidence_changes_nothing() -> void:
	var store := _store()
	var hit: NpcObservation = _hit()
	assert_true(_inbox(store).enqueue(hit))
	var before: Dictionary = store.snapshot(OBSERVER)
	var revision: int = store.revision(OBSERVER)
	assert_eq(store.commit_evidence(OBSERVER, hit, _policy(true, -0.08)), "not_claimed",
		"Pending evidence has not been claimed")
	assert_eq(store.commit_evidence(OBSERVER, _death(), _policy()), "not_claimed",
		"Evidence the inbox never saw cannot be committed")
	assert_true(_memories(store).is_empty())
	assert_eq(_trust(store), 0.0)
	assert_eq(store.snapshot(OBSERVER), before)
	assert_eq(store.revision(OBSERVER), revision)
	assert_false(_inbox(store).has_receipt(hit.observation_id))
	var claimed: NpcObservation = _inbox(store).claim(hit.observation_id, 500.0)
	assert_not_null(claimed, "The pending item stayed available")
	assert_eq(store.commit_evidence(OBSERVER, claimed, _policy(true, -0.08)), "")
	assert_eq(_trust(store), -0.08)

func test_invalid_inputs_report_their_reason_without_changes() -> void:
	var store := _store()
	var claimed: NpcObservation = _claim(store, _death())
	assert_eq(store.commit_evidence(OBSERVER, null, _policy()), "invalid_observation")
	var bad: NpcDecisionPolicy.Appraisal = _policy()
	bad.importance = 4.0
	assert_eq(store.commit_evidence(OBSERVER, claimed, bad), "invalid_appraisal")
	assert_eq(store.commit_evidence(OBSERVER, claimed, null), "invalid_appraisal")
	assert_false(_inbox(store).has_receipt(claimed.observation_id))
	assert_true(_memories(store).is_empty())
	assert_eq(store.commit_evidence(OBSERVER, claimed, _policy()), "")

func test_committing_the_same_observation_twice_is_a_noop_returning_empty() -> void:
	var store := _store()
	var hit: NpcObservation = _hit()
	var claimed: NpcObservation = _claim(store, hit)
	assert_eq(store.commit_evidence(OBSERVER, claimed, _policy(true, -0.08)), "")
	var after_first: Dictionary = store.snapshot(OBSERVER)
	var revision: int = store.revision(OBSERVER)
	var turn: int = store.turn
	assert_eq(store.commit_evidence(OBSERVER, claimed, _policy(true, -0.08)), "")
	assert_eq(store.commit_evidence(OBSERVER, hit, _policy(true, -0.08)), "")
	assert_eq(store.snapshot(OBSERVER), after_first)
	assert_eq(_memories(store).size(), 1)
	assert_eq(_trust(store), -0.08)
	assert_eq(store.revision(OBSERVER), revision)
	assert_eq(store.turn, turn)

func test_a_committed_observation_stays_a_noop_after_a_save_round_trip() -> void:
	var store := _store()
	var hit: NpcObservation = _hit()
	assert_eq(_commit(store, hit, _policy(true, -0.08)), "")
	var restored := NpcMemoryStore.new()
	assert_true(restored.minds.from_data(JSON.parse_string(JSON.stringify(store.minds.to_data()))))
	assert_true(restored.from_save_data(JSON.parse_string(JSON.stringify(store.to_save_data()))))
	var before: Dictionary = restored.snapshot(OBSERVER)
	assert_eq(restored.commit_evidence(OBSERVER, hit, _policy(true, -0.08)), "")
	assert_eq(restored.snapshot(OBSERVER), before)
	assert_eq(_trust(restored), -0.08)

func test_hearing_a_report_and_seeing_the_death_stay_two_memories() -> void:
	var store := _store()
	var report: NpcObservation = _report()
	var seen: NpcObservation = _death()
	assert_eq(_commit(store, report), "")
	assert_eq(_commit(store, seen), "")
	var memories: Array = _memories(store)
	assert_eq(memories.size(), 2)
	var heard: Dictionary = memories.filter(func(m: Dictionary) -> bool: return m.modality == "speech")[0]
	var saw: Dictionary = memories.filter(func(m: Dictionary) -> bool: return m.modality == "sight")[0]
	assert_eq(heard.source, "hearsay")
	assert_eq(saw.source, "observed_event")
	assert_true(DECEASED in heard.people)
	assert_true(DECEASED in saw.people)
	assert_eq(heard.evidence_ids, [report.observation_id])
	assert_eq(saw.evidence_ids, [seen.observation_id])
	assert_ne(heard.origin_id, saw.origin_id)

func test_identical_wording_from_hearing_and_sight_is_still_two_memories() -> void:
	var store := _store()
	var wording: String = "Garrin Holt is dead."
	assert_eq(_commit(store, _report(wording)), "")
	assert_eq(_commit(store, _death(wording)), "")
	var memories: Array = _memories(store)
	assert_eq(memories.size(), 2)
	assert_ne(memories[0].source, memories[1].source)
	assert_ne(memories[0].modality, memories[1].modality)

func test_a_second_sighting_of_the_same_incident_adds_evidence_not_a_memory() -> void:
	var store := _store()
	var first: NpcObservation = _death("Garrin lay dead by the well.")
	var second: NpcObservation = _death("Garrin lay dead by the well.")
	first.incident_id = "death:garrin"
	second.incident_id = "death:garrin"
	assert_eq(_commit(store, first), "")
	assert_eq(_commit(store, second), "")
	var memories: Array = _memories(store)
	assert_eq(memories.size(), 1)
	assert_eq(memories[0].evidence_ids, [first.observation_id, second.observation_id])

func test_new_memories_carry_incident_origin_evidence_and_the_perceived_minute() -> void:
	var store := _store()
	store.set_world_minute(600.0)
	var seen: NpcObservation = _death("I saw Garrin die.", 500.0)
	seen.incident_id = "assault:7"
	assert_eq(_commit(store, seen), "")
	var memory: Dictionary = _memories(store)[0]
	assert_eq(memory.observation_kind, "actor_died")
	assert_eq(memory.modality, "sight")
	assert_eq(memory.incident_id, "assault:7")
	assert_eq(memory.origin_id, seen.origin_id)
	assert_eq(memory.evidence_ids, [seen.observation_id])
	assert_eq(memory.chain, [])
	assert_eq(float(memory.observed_minute), 500.0, "The perceived time, not the commit time")
	assert_eq(float(memory.created_minute), 500.0)
	assert_true(memory.date_known)
	assert_eq(NpcMemory.retention_age(memory, 600.0), 100.0 / NpcMemory.MINUTES_PER_RETENTION_UNIT,
		"The memory ages from when it was perceived")

func test_a_report_remembers_who_told_it() -> void:
	var store := _store()
	store.set_world_minute(700.0)
	var report: NpcObservation = _report("Voss told me Garrin is dead.", 640.0)
	assert_eq(_commit(store, report), "")
	var memory: Dictionary = _memories(store)[0]
	assert_eq(memory.chain, ["voss"])
	assert_eq(memory.modality, "speech")
	assert_eq(memory.observation_kind, "body_reported")
	assert_eq(float(memory.observed_minute), 640.0)

func test_evidence_fields_survive_a_save_round_trip() -> void:
	var store := _store()
	store.set_world_minute(600.0)
	var report: NpcObservation = _report()
	report.incident_id = "death:garrin"
	assert_eq(_commit(store, report), "")
	var restored := NpcMemoryStore.new()
	assert_true(restored.from_save_data(JSON.parse_string(JSON.stringify(store.to_save_data()))))
	assert_eq(_memories(restored), JSON.parse_string(JSON.stringify(_memories(store))))

func test_grief_adds_no_sensory_cues_to_memories_or_context() -> void:
	var store := NpcMemoryStore.new()
	var partner: String = "holt_partner"
	store.ensure_npc(_profile(partner))
	var mind: NpcMindState = store.minds.get_mind(partner)
	var people: Dictionary = {
		partner: {"name": "Holt Partner", "job": "farmer", "household": "holt", "kin": {DECEASED: "spouse"}},
		DECEASED: {"name": "Garrin Holt", "job": "farmer", "household": "holt", "kin": {}}}
	mind.knowledge.bootstrap_public(partner, people, {}, [] as Array[String])
	var found: NpcObservation = _perceive("body_found", "sight", "I found Garrin dead.",
		[{"id": DECEASED, "name": "Garrin Holt", "role": "deceased"}], 500.0, partner)
	CognitionScript.perceive(mind, found, {})
	assert_eq(mind.condition.get("concerns", []).size(), 1, "The relative grieves")
	assert_eq(_commit(store, found), "")
	for memory: Dictionary in _memories(store, partner):
		assert_eq(memory.sensory_cues, [])
	var current: Dictionary = {"world_minute": 600.0,
		"family_members": [{"id": DECEASED, "name": "Garrin Holt", "relationship": "spouse"}]}
	current.merge(NpcCognitiveContext.mind_context(mind))
	var context: Dictionary = NpcCognitiveContext.build(store.snapshot(partner), current)
	assert_true(context.current_concerns.any(
		func(concern: Dictionary) -> bool: return concern.kind == "bereavement"))
	assert_false(_has_cues(context), "Grief invents no sights, sounds or smells: %s" % [context])

## Whether any nested dictionary carries a non-empty cue list.
func _has_cues(value: Variant) -> bool:
	if value is Dictionary:
		for key: Variant in value:
			if key in ["sensory_cues", "cues"] and value[key] is Array and not (value[key] as Array).is_empty():
				return true
			if _has_cues(value[key]):
				return true
	elif value is Array:
		for item: Variant in value:
			if _has_cues(item):
				return true
	return false

func test_undated_legacy_memory_stays_undated_across_save_and_load() -> void:
	var store := NpcMemoryStore.new()
	var profile: NpcProfile = _profile()
	profile.memories = ["My grandfather taught me to read the weather."]
	store.ensure_npc(profile)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(store.to_save_data()))
	var legacy: Dictionary = saved.npcs[OBSERVER].memories[0]
	legacy.erase("created_minute")
	legacy.erase("date_known")
	legacy.erase("age_anchor_minute")
	legacy.erase("age_at_anchor")
	legacy.created_turn = 501
	var first := NpcMemoryStore.new()
	assert_true(first.from_save_data(saved, 4320.0))
	var memory: Dictionary = _memories(first)[0]
	assert_false(memory.date_known)
	assert_eq(float(memory.created_minute), NpcMemory.UNKNOWN_MINUTE)
	assert_eq(NpcMemory.retention_age(memory, 4320.0), 0.0, "501 exchanges are not elapsed time")
	var second := NpcMemoryStore.new()
	assert_true(second.from_save_data(JSON.parse_string(JSON.stringify(first.to_save_data())), 9000.0))
	var reloaded: Dictionary = _memories(second)[0]
	assert_false(reloaded.date_known)
	assert_eq(float(reloaded.created_minute), NpcMemory.UNKNOWN_MINUTE)
	assert_eq(reloaded.age_anchor_minute, memory.age_anchor_minute, "Loading does not re-anchor")
	assert_eq(NpcMemory.retention_age(reloaded, 4380.0), 2.0)
