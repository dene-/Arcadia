extends "res://tests/test_case.gd"

const Appraisals = preload("res://tests/fixtures/npc_appraisal_fixture.gd")
const OBSERVER: String = "elder"
const NOW: float = 1000.0

var _serial: int = 0

## A valid, dated, low-importance first-hand episode of incident "incident:1" perceived at minute 100.
func _episode(id: String, fields: Dictionary = {}) -> Dictionary:
	var memory: Dictionary = NpcMemory.create(id, "episodic", "I saw Mira get hurt (%s)." % id,
		"observed_event", 1)
	memory.importance = 0.3
	memory.confidence = 0.9
	memory.created_minute = 100.0
	memory.date_known = true
	memory.people = ["mira"]
	memory.observation_kind = "actor_hurt"
	memory.modality = "sight"
	memory.incident_id = "incident:1"
	memory.origin_id = "origin:" + id
	memory.evidence_ids = [id]
	memory.observed_minute = 100.0
	memory.chain = []
	memory.merge(fields, true)
	assert_true(NpcMemory.is_valid(memory), "Test memory %s must be valid" % id)
	return memory

func _hearsay(id: String, origin: String, chain: Array[String]) -> Dictionary:
	return _episode(id, {"source": "hearsay", "modality": "speech", "observation_kind": "rumor",
		"origin_id": origin, "chain": chain})

func _ids(memories: Array) -> Array[String]:
	var ids: Array[String] = []
	for memory: Dictionary in memories:
		ids.append(memory.id)
	return ids

func _consolidate(memories: Array, refs: Dictionary = {}, minute: float = NOW) -> int:
	return NpcMemoryConsolidator.consolidate(memories, refs, minute)

# Merging

func test_low_importance_episodes_of_one_incident_merge_keeping_all_evidence_and_the_weakest_certainty() -> void:
	var first: Dictionary = _episode("a")
	var second: Dictionary = _episode("b", {"confidence": 0.5, "importance": 0.4, "recall_count": 2})
	var third: Dictionary = _episode("c", {"confidence": 0.7, "emotional_intensity": 0.6})
	var memories: Array = [first, second, third]
	assert_eq(_consolidate(memories), 2)
	assert_eq(memories.size(), 1)
	var merged: Dictionary = memories[0]
	assert_eq(merged.id, "a")
	assert_eq(merged.evidence_ids, ["a", "b", "c"])
	assert_eq(float(merged.confidence), 0.5)
	assert_eq(float(merged.importance), 0.4)
	assert_eq(float(merged.emotional_intensity), 0.6)
	assert_eq(merged.recall_count, 2)
	assert_eq(merged.gist, first.gist, "The earliest episode keeps its wording")
	assert_eq(merged.origin_id, "", "First-hand episodes of different origins share no single origin")
	assert_true(NpcMemory.is_valid(merged))

func test_a_shared_origin_survives_the_merge() -> void:
	var memories: Array = [_episode("a", {"origin_id": "origin:same"}),
		_episode("b", {"origin_id": "origin:same"})]
	assert_eq(_consolidate(memories), 1)
	assert_eq(memories[0].origin_id, "origin:same")

func test_merging_keeps_unrelated_memories_in_place_and_is_repeatable() -> void:
	var other: Dictionary = _episode("x", {"incident_id": "incident:2"})
	var memories: Array = [_episode("a"), other, _episode("b"), _episode("y", {"incident_id": "incident:2"})]
	assert_eq(_consolidate(memories), 2)
	assert_eq(_ids(memories), ["a", "x"])
	assert_eq(memories[1].evidence_ids, ["x", "y"])
	assert_eq(_consolidate(memories), 0, "A consolidated archive is stable")

func test_memories_below_the_age_threshold_are_left_alone() -> void:
	var memories: Array = [_episode("a"), _episode("b")]
	assert_eq(_consolidate(memories, {}, 100.0 + NpcMemoryConsolidator.MIN_AGE_MINUTES - 1.0), 0)
	assert_eq(memories.size(), 2)
	assert_eq(_consolidate(memories, {}, 100.0 + NpcMemoryConsolidator.MIN_AGE_MINUTES), 1)

func test_merged_evidence_never_exceeds_the_bound() -> void:
	var memories: Array = []
	for index: int in range(NpcMemory.MAX_EVIDENCE_IDS + 4):
		memories.append(_episode("e%d" % index))
	assert_eq(_consolidate(memories), NpcMemory.MAX_EVIDENCE_IDS + 4 - 2)
	assert_eq(memories.size(), 2)
	assert_eq(memories[0].evidence_ids.size(), NpcMemory.MAX_EVIDENCE_IDS)
	assert_eq(memories[1].evidence_ids.size(), 4)
	for memory: Dictionary in memories:
		assert_true(NpcMemory.is_valid(memory))

# Independent accounts stay apart

func test_episodes_that_differ_in_source_modality_kind_incident_or_people_never_merge() -> void:
	var variants: Array[Dictionary] = [
		{"source": "hearsay", "modality": "speech"},
		{"modality": "hearing"},
		{"observation_kind": "combat"},
		{"incident_id": "incident:2"},
		{"people": ["player"]},
		{"chain": ["voss"]},
	]
	for variant: Dictionary in variants:
		var memories: Array = [_episode("a"), _episode("b", variant)]
		assert_eq(_consolidate(memories), 0, "Must stay apart: %s" % [variant])
		assert_eq(_ids(memories), ["a", "b"])

func test_hearsay_with_a_different_origin_or_chain_never_merges() -> void:
	var memories: Array = [_hearsay("a", "origin:1", ["voss"]), _hearsay("b", "origin:2", ["voss"])]
	assert_eq(_consolidate(memories), 0, "Different origins are independent accounts")
	memories = [_hearsay("a", "origin:1", ["voss"]), _hearsay("b", "origin:1", ["mira"])]
	assert_eq(_consolidate(memories), 0, "Different tellers are independent accounts")
	memories = [_hearsay("a", "origin:1", ["voss"]), _hearsay("b", "origin:1", ["voss"])]
	assert_eq(_consolidate(memories), 1, "The same account retold merges")
	assert_eq(memories[0].origin_id, "origin:1")
	assert_eq(memories[0].chain, ["voss"])

func test_a_report_and_a_sighting_of_the_same_incident_never_merge() -> void:
	var memories: Array = [_episode("a"), _hearsay("b", "origin:b", ["voss"])]
	assert_eq(_consolidate(memories), 0)

# Protected records

func test_protected_records_are_never_merged() -> void:
	var protected: Dictionary = {
		"authored": {"source": "authored"},
		"core death kind": {"observation_kind": "actor_died"},
		"body found": {"observation_kind": "body_found"},
		"body reported": {"observation_kind": "body_reported"},
		"undated": {"date_known": false, "created_minute": NpcMemory.UNKNOWN_MINUTE,
			"age_anchor_minute": 100.0, "age_at_anchor": 0.0},
		"important": {"importance": NpcMemoryConsolidator.PROTECTED_IMPORTANCE},
		"completed": {"completed": true},
		"prospective": {"type": "prospective"},
		"semantic": {"type": "semantic"},
		"no incident": {"incident_id": ""},
	}
	for label: String in protected:
		var fields: Dictionary = protected[label]
		var memories: Array = [_episode("a", fields), _episode("b", fields)]
		assert_eq(_consolidate(memories), 0, "%s must stay as it is" % label)
		assert_eq(_ids(memories), ["a", "b"])

func test_evidence_and_origins_cited_by_commitments_or_contested_beliefs_are_protected() -> void:
	for ref: String in ["b", "origin:b"]:
		var memories: Array = [_episode("a"), _episode("b"), _episode("c")]
		assert_eq(_consolidate(memories, {ref: true}), 1)
		assert_eq(_ids(memories), ["a", "b"], "Only the uncited episodes merge (%s)" % ref)
		assert_eq(memories[1].evidence_ids, ["b"])
		assert_eq(memories[0].evidence_ids, ["a", "c"])

# Through the store

func _store() -> NpcMemoryStore:
	var store := NpcMemoryStore.new()
	var profile := NpcProfile.new()
	profile.npc_id = StringName(OBSERVER)
	store.ensure_npc(profile)
	store.set_world_minute(500.0)
	return store

func _policy() -> NpcDecisionPolicy.Appraisal:
	return Appraisals.make(true, 0.3, 0.2)

func _hurt(text: String) -> NpcObservation:
	_serial += 1
	var observation: NpcObservation = NpcObservation.from_perception(OBSERVER, "event:%d" % _serial,
		500.0, &"outdoors", {"kind": "actor_hurt", "sense": "sight", "text": text,
		"player_involved": false,
		"participants": [{"id": "mira", "name": "Mira", "role": "hurt_person"}]})
	assert_not_null(observation)
	observation.incident_id = "incident:brawl"
	return observation

func _commit(store: NpcMemoryStore, observation: NpcObservation) -> void:
	var inbox: NpcEvidenceInbox = store.minds.get_mind(OBSERVER).evidence
	assert_true(inbox.enqueue(observation))
	assert_not_null(inbox.claim(observation.observation_id, 500.0))
	assert_eq(store.commit_evidence(OBSERVER, observation, _policy()), "")

func _archive(store: NpcMemoryStore) -> Array:
	return store.snapshot(OBSERVER).memories

func _brawl(store: NpcMemoryStore, count: int) -> Array[NpcObservation]:
	var observations: Array[NpcObservation] = []
	for index: int in count:
		var observation: NpcObservation = _hurt("Mira was struck, blow %d." % index)
		_commit(store, observation)
		observations.append(observation)
	assert_eq(_archive(store).size(), count, "Different wording admits separate memories")
	return observations

func test_maintenance_merges_an_old_incident_and_reports_it() -> void:
	var store: NpcMemoryStore = _store()
	var observations: Array[NpcObservation] = _brawl(store, 4)
	var revision: int = store.revision(OBSERVER)
	var result: Dictionary = store.maintain({}, 520.0)
	assert_eq(result.memories_merged, 0, "Still inside the working window")
	assert_eq(store.revision(OBSERVER), revision)
	result = store.maintain({}, NOW)
	assert_eq(result.memories_merged, 3)
	var archive: Array = _archive(store)
	assert_eq(archive.size(), 1)
	for observation: NpcObservation in observations:
		assert_true(observation.observation_id in archive[0].evidence_ids)
	assert_true(store.revision(OBSERVER) > revision)
	assert_eq(store.maintain({}, NOW).memories_merged, 0)

func test_maintenance_protects_commitment_cited_and_contested_evidence() -> void:
	var store: NpcMemoryStore = _store()
	var observations: Array[NpcObservation] = _brawl(store, 4)
	var mind: NpcMindState = store.minds.get_mind(OBSERVER)
	var cited: Array[String] = [observations[1].observation_id]
	assert_ne(mind.commitments.create("visit_grave", ["mira"] as Array[String], cited, 600.0), "")
	var disputed: NpcObservation = observations[2]
	assert_true(mind.knowledge.record_report("mira", "status", "dead", "voss", disputed.origin_id,
		disputed.observation_id, 501.0, 0.8))
	assert_true(mind.knowledge.record_report("mira", "status", "alive", "garrin", "origin:other",
		"ev:other", 502.0, 0.8))
	assert_eq(store.maintain({}, NOW).memories_merged, 1)
	var archive: Array = _archive(store)
	assert_eq(archive.size(), 3)
	var merged: Dictionary = archive[0]
	assert_eq(merged.evidence_ids, [observations[0].observation_id, observations[3].observation_id])
	assert_eq(archive[1].evidence_ids, cited)
	assert_eq(archive[2].evidence_ids, [disputed.observation_id])

func test_a_consolidated_archive_survives_a_save_round_trip() -> void:
	var store: NpcMemoryStore = _store()
	_brawl(store, 3)
	store.maintain({}, NOW)
	var restored := NpcMemoryStore.new()
	assert_true(restored.from_save_data(JSON.parse_string(JSON.stringify(store.to_save_data()))))
	assert_eq(_archive(restored), JSON.parse_string(JSON.stringify(_archive(store))))

# Rumor loop

func _event(origin: String) -> Dictionary:
	return {"origin_id": origin, "text": "I saw Den hurt Garrin.", "sense": "sight", "player_involved": true}

func _rumor_policy() -> Dictionary:
	return {"remember": true, "importance": 0.8, "belief": 0.7,
		"dispositions": {"player": {"trust": -0.03}}}

func _listener() -> NpcProfile:
	var profile := NpcProfile.new()
	profile.npc_id = &"listener"
	return profile

func _told(rumors: TownRumors, origin: String, minute: float, speaker: String = "a") -> Dictionary:
	var account: Dictionary = {}
	for known: Dictionary in rumors.get_known(speaker, minute):
		if known.origin_id == origin:
			account = known
	return rumors.hear("listener", speaker, speaker.capitalize(), account, _rumor_policy(), minute)

func _reload(memory: NpcMemoryStore) -> NpcMemoryStore:
	var loaded := NpcMemoryStore.new()
	assert_true(loaded.minds.from_data(JSON.parse_string(JSON.stringify(memory.minds.to_data()))))
	assert_true(loaded.from_save_data(JSON.parse_string(JSON.stringify(memory.to_save_data()))))
	return loaded

func test_a_forgotten_rumor_cannot_be_admitted_again_while_anyone_can_still_retell_it() -> void:
	var rumors := TownRumors.new()
	rumors.observe("a", "Mirelle", _event("event:1"), _rumor_policy(), 500)
	var heard: Dictionary = _told(rumors, "event:1", 501)
	var memory := NpcMemoryStore.new()
	memory.record_hearsay(_listener(), heard, _rumor_policy())
	assert_eq(memory.snapshot("listener").memories.size(), 1)
	assert_eq(memory.minds.get_mind("listener").relationships.get_relationship("player").trust, -0.03)
	# Other speakers fill the listener's 32 slots until its own account is pushed out; "a" still
	# holds the original and can retell it.
	for index: int in TownRumors.MAX_KNOWN:
		var origin: String = "event:other:%d" % index
		rumors.observe("b", "Bram", _event(origin), _rumor_policy(), 502.0 + index)
		assert_false(_told(rumors, origin, 540.0, "b").is_empty())
	assert_false(rumors.knows("listener", "event:1", 560.0))
	assert_true(rumors.knows("a", "event:1", 560.0))
	assert_true(rumors.live_origins(560.0).has("event:1"))
	# The archive forgets the story (decay or consolidation); the receipts must not.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(memory.to_save_data()))
	saved.npcs.listener.memories.clear()
	var forgetful := NpcMemoryStore.new()
	assert_true(forgetful.minds.from_data(JSON.parse_string(JSON.stringify(memory.minds.to_data()))))
	assert_true(forgetful.from_save_data(saved))
	assert_true(forgetful.snapshot("listener").memories.is_empty())
	var result: Dictionary = forgetful.maintain(rumors.live_origins(560.0), 560.0)
	assert_eq(result.receipts_pruned, 0)
	var loaded: NpcMemoryStore = _reload(forgetful)
	var rumors_loaded := TownRumors.new()
	assert_true(rumors_loaded.from_data(JSON.parse_string(JSON.stringify(rumors.to_data()))))
	var again: Dictionary = _told(rumors_loaded, "event:1", 560.0)
	assert_false(again.is_empty(), "The speaker can retell it to a listener who lost its own account")
	loaded.record_hearsay(_listener(), again, _rumor_policy())
	assert_true(loaded.snapshot("listener").memories.is_empty(), "No second memory")
	assert_eq(loaded.minds.get_mind("listener").relationships.get_relationship("player").trust, -0.03, "No second trust change")

func test_an_origin_nobody_can_retell_is_forgotten_and_cannot_return() -> void:
	var rumors := TownRumors.new()
	rumors.observe("a", "Mirelle", _event("event:1"), _rumor_policy(), 500)
	var memory := NpcMemoryStore.new()
	memory.record_hearsay(_listener(), _told(rumors, "event:1", 501), _rumor_policy())
	var expired: float = 500.0 + 10080.0 + 1.0
	assert_true(rumors.live_origins(expired).is_empty())
	var result: Dictionary = memory.maintain(rumors.live_origins(expired), expired)
	assert_eq(result.origins_pruned, 1)
	assert_eq(result.receipts_pruned, 1)
	assert_eq(memory.snapshot("listener").memories.size(), 1, "Forgetting receipts never forgets the story")
	assert_true(_told(rumors, "event:1", expired).is_empty(), "No account is left to retell")
