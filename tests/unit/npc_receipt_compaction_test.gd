extends "res://tests/test_case.gd"

const Appraisals = preload("res://tests/fixtures/npc_appraisal_fixture.gd")
const OBSERVER: String = "elder"

var _serial: int = 0

func _round_trip(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))

func _observation(id: String, origin: String) -> NpcObservation:
	var observation := NpcObservation.new()
	observation.observation_id = id
	observation.origin_id = origin
	observation.observer_id = OBSERVER
	observation.kind = &"sighting"
	observation.modality = NpcObservation.Modality.SIGHT
	observation.observed_minute = 100.0
	observation.space_id = &"outdoors"
	observation.text = "Observation " + id
	return observation

func _complete(inbox: NpcEvidenceInbox, id: String, origin: String) -> void:
	assert_true(inbox.enqueue(_observation(id, origin)))
	assert_not_null(inbox.claim(id, 100.0))
	assert_true(inbox.complete(id))

# Evidence inbox

func test_inbox_compaction_prunes_only_receipts_nothing_references() -> void:
	var inbox := NpcEvidenceInbox.new()
	_complete(inbox, "r1", "o1")
	_complete(inbox, "r2", "o2")
	_complete(inbox, "r3", "o3")
	assert_eq(inbox.receipt_origin("r2"), "o2")
	var version: int = inbox.version
	assert_eq(inbox.compact({"r1": true, "o2": true}), 1)
	assert_true(inbox.has_receipt("r1"), "Referenced by its own id")
	assert_true(inbox.has_receipt("r2"), "Referenced by its origin")
	assert_false(inbox.has_receipt("r3"))
	assert_eq(inbox.receipt_origin("r3"), "")
	assert_eq(inbox.receipt_count(), 2)
	assert_true(inbox.version > version)
	version = inbox.version
	assert_eq(inbox.compact({"r1": true, "o2": true}), 0)
	assert_eq(inbox.version, version, "A compaction that prunes nothing changes nothing")

func test_inbox_compaction_keeps_receipts_whose_origin_is_unknown() -> void:
	var inbox := NpcEvidenceInbox.new()
	_complete(inbox, "r1", "o1")
	var legacy: Dictionary = _round_trip(inbox.to_data())
	legacy.erase("receipt_origins")
	var loaded := NpcEvidenceInbox.new()
	assert_true(NpcEvidenceInbox.is_valid_data(legacy))
	assert_true(loaded.from_data(legacy))
	assert_eq(loaded.compact({}), 0)
	assert_true(loaded.has_receipt("r1"))

func test_a_pruned_inbox_keeps_its_survivors_across_a_save() -> void:
	var inbox := NpcEvidenceInbox.new()
	_complete(inbox, "r1", "o1")
	_complete(inbox, "r2", "o2")
	inbox.compact({"o1": true})
	var loaded := NpcEvidenceInbox.new()
	assert_true(loaded.from_data(_round_trip(inbox.to_data())))
	assert_true(loaded.has_receipt("r1"))
	assert_eq(loaded.receipt_origin("r1"), "o1")
	assert_false(loaded.has_receipt("r2"))
	assert_false(loaded.enqueue(_observation("r1", "o1")), "A kept receipt still blocks the replay")
	assert_eq(loaded.compact({}), 1)
	assert_eq(loaded.receipt_count(), 0)

func test_inbox_compaction_makes_room_at_the_receipt_bound() -> void:
	var inbox := NpcEvidenceInbox.new()
	for index: int in NpcEvidenceInbox.MAX_RECEIPTS:
		_complete(inbox, "r%d" % index, "o%d" % index)
	assert_true(inbox.enqueue(_observation("late", "o:late")))
	assert_not_null(inbox.claim("late", 100.0))
	assert_false(inbox.complete("late"))
	assert_eq(inbox.compact({"o0": true}), NpcEvidenceInbox.MAX_RECEIPTS - 1)
	assert_true(inbox.has_receipt("r0"))
	assert_true(inbox.complete("late"))
	assert_true(inbox.has_receipt("late"))

# Relationship graph

func test_graph_compaction_prunes_only_receipts_nothing_references() -> void:
	var graph := NpcRelationshipGraph.new()
	assert_true(graph.apply_delta("player", {"trust": 0.1}, "r1", "o1"))
	assert_true(graph.apply_delta("player", {"trust": 0.1}, "r2", "o2"))
	assert_true(graph.apply_delta("player", {"trust": 0.1}, "r3", "o3"))
	assert_true(graph.apply_delta("player", {"familiarity": 0.01}, "counter:1"))
	var trust: float = graph.get_relationship("player").trust
	assert_eq(graph.compact({"r1": true, "o2": true}), 2)
	assert_true(graph.has_receipt("r1"), "Referenced by its own id")
	assert_true(graph.has_receipt("r2"), "Referenced by its origin")
	assert_false(graph.has_receipt("r3"))
	assert_false(graph.has_receipt("counter:1"), "An origin-less receipt is never reissued")
	assert_eq(graph.get_relationship("player").trust, trust, "Compaction never changes a relationship")
	assert_eq(graph.receipt_count(), 2)

func test_graph_compaction_keeps_receipts_whose_origin_is_unknown() -> void:
	var graph := NpcRelationshipGraph.new()
	graph.apply_delta("player", {"trust": 0.1}, "r1", "o1")
	var legacy: Dictionary = _round_trip(graph.to_data())
	legacy.erase("origins")
	var loaded := NpcRelationshipGraph.new()
	assert_true(loaded.from_data(legacy))
	assert_eq(loaded.compact({}), 0)
	assert_true(loaded.has_receipt("r1"))

func test_a_pruned_graph_keeps_its_survivors_across_a_save() -> void:
	var graph := NpcRelationshipGraph.new()
	graph.apply_delta("player", {"trust": 0.1}, "r1", "o1")
	graph.apply_delta("player", {"trust": 0.1}, "r2", "o2")
	graph.compact({"o1": true})
	var loaded := NpcRelationshipGraph.new()
	assert_true(loaded.from_data(_round_trip(graph.to_data())))
	assert_true(loaded.has_receipt("r1"))
	assert_false(loaded.has_receipt("r2"))
	var trust: float = loaded.get_relationship("player").trust
	assert_false(loaded.apply_delta("player", {"trust": 0.1}, "r1", "o1"), "A kept receipt still blocks the replay")
	assert_eq(loaded.get_relationship("player").trust, trust)
	assert_eq(loaded.compact({}), 1)

func test_graph_compaction_makes_room_at_the_receipt_bound() -> void:
	var graph := NpcRelationshipGraph.new()
	for index: int in NpcRelationshipGraph.MAX_RECEIPTS:
		assert_true(graph.apply_delta("mira", {"familiarity": 0.001}, "r%d" % index, "o%d" % index))
	assert_false(graph.apply_delta("mira", {"familiarity": 0.001}, "late", "o:late"))
	assert_eq(graph.compact({"o0": true}), NpcRelationshipGraph.MAX_RECEIPTS - 1)
	assert_true(graph.apply_delta("mira", {"familiarity": 0.001}, "late", "o:late"))
	assert_true(graph.has_receipt("r0"))

# Store upkeep

func _profile(id: String = OBSERVER) -> NpcProfile:
	var profile := NpcProfile.new()
	profile.npc_id = StringName(id)
	return profile

func _policy(trust: float = 0.0) -> NpcDecisionPolicy.Appraisal:
	return Appraisals.player_trust(trust)

# A player-involved sighting: its commit completes an inbox receipt and a relationship receipt.
func _hit() -> NpcObservation:
	_serial += 1
	var observation: NpcObservation = NpcObservation.from_perception(OBSERVER, "event:%d" % _serial,
		500.0, &"outdoors", {"kind": "actor_hurt", "sense": "sight", "text": "I saw the player strike Mira.",
		"player_involved": true,
		"participants": [{"id": "player", "name": "the player", "role": "aggressor"}]})
	assert_not_null(observation)
	return observation

func _commit(store: NpcMemoryStore, observation: NpcObservation) -> void:
	var inbox: NpcEvidenceInbox = store.minds.get_mind(OBSERVER).evidence
	assert_true(inbox.enqueue(observation))
	assert_not_null(inbox.claim(observation.observation_id, 500.0))
	assert_eq(store.commit_evidence(OBSERVER, observation, _policy(-0.05)), "")

func _store() -> NpcMemoryStore:
	var store := NpcMemoryStore.new()
	store.ensure_npc(_profile())
	return store

func _receipts(store: NpcMemoryStore) -> int:
	var mind: NpcMindState = store.minds.get_mind(OBSERVER)
	return mind.evidence.receipt_count() + mind.relationships.receipt_count()

func test_upkeep_drops_receipts_of_origins_nobody_can_replay_and_keeps_live_ones() -> void:
	var store: NpcMemoryStore = _store()
	var kept: NpcObservation = _hit()
	var dropped: NpcObservation = _hit()
	_commit(store, kept)
	_commit(store, dropped)
	assert_eq(_receipts(store), 4)
	assert_eq(store.maintain({kept.origin_id: true}, 600.0).receipts_pruned, 2)
	var mind: NpcMindState = store.minds.get_mind(OBSERVER)
	assert_true(mind.evidence.has_receipt(kept.observation_id))
	assert_false(mind.evidence.has_receipt(dropped.observation_id))
	assert_true(mind.relationships.has_receipt("observation:%s:%s:player" % [OBSERVER, kept.observation_id]))
	assert_false(mind.relationships.has_receipt("observation:%s:%s:player" % [OBSERVER, dropped.observation_id]))
	assert_eq(store.maintain({kept.origin_id: true}, 600.0).receipts_pruned, 0)

func test_upkeep_keeps_receipts_an_open_commitment_cites_until_it_closes() -> void:
	var store: NpcMemoryStore = _store()
	var hit: NpcObservation = _hit()
	_commit(store, hit)
	var mind: NpcMindState = store.minds.get_mind(OBSERVER)
	var cited: Array[String] = [hit.observation_id]
	var commitment: String = mind.commitments.create("visit_grave", ["mira"] as Array[String], cited, 600.0)
	assert_ne(commitment, "")
	assert_eq(store.maintain({}, 700.0).receipts_pruned, 0)
	assert_true(mind.evidence.has_receipt(hit.observation_id))
	assert_true(mind.relationships.has_receipt("observation:%s:%s:player" % [OBSERVER, hit.observation_id]))
	assert_true(mind.commitments.resolve(commitment, "completed", 710.0))
	assert_eq(store.maintain({}, 720.0).receipts_pruned, 2)
	assert_false(mind.evidence.has_receipt(hit.observation_id))

func test_upkeep_keeps_receipts_whose_origin_is_still_waiting_in_the_inbox() -> void:
	var store: NpcMemoryStore = _store()
	var hit: NpcObservation = _hit()
	_commit(store, hit)
	var mind: NpcMindState = store.minds.get_mind(OBSERVER)
	var replay: NpcObservation = _observation("replay", hit.origin_id)
	assert_true(mind.evidence.enqueue(replay))
	assert_eq(store.maintain({}, 600.0).receipts_pruned, 0, "A pending item of the same origin")
	assert_not_null(mind.evidence.claim("replay", 600.0))
	assert_true(mind.evidence.complete("replay"))
	assert_eq(store.maintain({}, 610.0).receipts_pruned, 3)
	assert_eq(_receipts(store), 0)

func test_upkeep_forgets_heard_origins_nobody_can_retell() -> void:
	var rumors := TownRumors.new()
	var policy: Dictionary = {"remember": true, "importance": 0.8, "belief": 0.7,
		"dispositions": {"player": {"trust": -0.03}}}
	var events: Array[Dictionary] = []
	for origin: String in ["event:live", "event:gone"]:
		events.append({"origin_id": origin, "text": "I saw Den hurt Garrin.", "sense": "sight",
			"player_involved": true})
		rumors.observe("a", "Mirelle", events[-1], policy, 500)
	var memory := NpcMemoryStore.new()
	for known: Dictionary in rumors.get_known("a", 501):
		memory.record_hearsay(_profile("listener"), rumors.hear("listener", "a", "Mirelle", known,
			policy, 501), policy)
	var saved: Dictionary = memory.to_save_data()
	assert_eq(saved.npcs.listener.heard_origins.size(), 2)
	assert_eq(memory.minds.get_mind("listener").relationships.receipt_count(), 2)
	var result: Dictionary = memory.maintain({"event:live": true}, 600.0)
	assert_eq(result.origins_pruned, 1)
	assert_eq(result.receipts_pruned, 1)
	saved = memory.to_save_data()
	assert_eq(saved.npcs.listener.heard_origins.keys(), ["event:live"])
	assert_true(memory.minds.get_mind("listener").relationships.has_receipt("hearsay:listener:event:live:player"))
	assert_false(memory.minds.get_mind("listener").relationships.has_receipt("hearsay:listener:event:gone:player"))
