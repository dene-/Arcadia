extends "res://tests/test_case.gd"

const OBSERVER: String = "holt_partner"

func _make(id: String, kind: StringName, modality: NpcObservation.Modality, minute: float,
		people: Array[Dictionary] = [], space: StringName = &"home:garrin_holt") -> NpcObservation:
	var observation := NpcObservation.new()
	observation.observation_id = id
	observation.origin_id = "origin:" + id
	observation.observer_id = OBSERVER
	observation.kind = kind
	observation.modality = modality
	observation.observed_minute = minute
	observation.space_id = space
	observation.text = "Observation " + id
	observation.participants = people
	return observation

func _sight(id: String, minute: float, kind: StringName = &"sighting") -> NpcObservation:
	return _make(id, kind, NpcObservation.Modality.SIGHT, minute)

func _noise(id: String, minute: float) -> NpcObservation:
	return _make(id, &"disturbance", NpcObservation.Modality.NOISE, minute)

func _person(id: String, role: String) -> Dictionary:
	return {"id": id, "name": id, "role": role}

func _fight(id: String, minute: float, kind: StringName, victim: String, attacker: String) -> NpcObservation:
	var people: Array[Dictionary] = [_person(victim, "hurt_person")]
	if not attacker.is_empty():
		people.append(_person(attacker, "aggressor"))
	return _make(id, kind, NpcObservation.Modality.SIGHT, minute, people, &"outdoors")

func _incident(inbox: NpcEvidenceInbox, id: String) -> String:
	return inbox.item(id)["observation"]["incident_id"]

func test_death_evidence_survives_redundant_noise() -> void:
	var inbox := NpcEvidenceInbox.new()
	var death: NpcObservation = _make("observer:death:1", &"body_found", NpcObservation.Modality.SIGHT,
		1380.0, [_person("garrin_holt", "deceased")])
	death.incident_id = "incident:1"
	assert_true(inbox.enqueue(death))
	for index: int in range(100):
		var noise: NpcObservation = _noise("observer:noise:%d" % index, 1381.0)
		noise.incident_id = "noise-incident:1"
		assert_true(inbox.enqueue(noise))
	assert_true(inbox.contains_pending("observer:death:1"))
	assert_true(inbox.ready_count(1400.0) <= NpcEvidenceInbox.READY_WINDOW)
	assert_eq(inbox.pending_observations().size(), 2)
	assert_eq(inbox.item("observer:noise:0")["count"], 100)
	assert_eq(inbox.item("observer:noise:0")["last_minute"], 1381.0)
	assert_false(inbox.contains_pending("observer:noise:1"))
	var stored: NpcObservation = inbox.next_ready(1400.0)
	assert_eq(stored.observation_id, "observer:death:1")
	assert_eq(stored.participant_ids(), ["garrin_holt"] as Array[String])
	assert_eq(stored.participants.size(), 1)
	var diagnostics: Array[Dictionary] = inbox.diagnostics()
	assert_eq(diagnostics.size(), NpcEvidenceInbox.MAX_DIAGNOSTICS)
	assert_eq(diagnostics[-1]["coalesced_id"], "observer:noise:99")
	assert_eq(diagnostics[-1]["incident_id"], "noise-incident:1")
	assert_false(inbox.enqueue(death))
	assert_eq(inbox.pending_observations().size(), 2)

func test_noise_never_adds_participants_and_claimed_noise_is_not_coalesced() -> void:
	var inbox := NpcEvidenceInbox.new()
	assert_true(inbox.enqueue(_noise("n1", 10.0)))
	assert_not_null(inbox.claim("n1", 10.0))
	assert_true(inbox.enqueue(_noise("n2", 11.0)))
	assert_true(inbox.enqueue(_noise("n3", 12.0)))
	assert_eq(inbox.item("n1")["count"], 1)
	assert_eq(inbox.item("n2")["count"], 2)
	for observation: NpcObservation in inbox.pending_observations():
		assert_true(observation.participants.is_empty())

func test_protected_observations_never_coalesce() -> void:
	var inbox := NpcEvidenceInbox.new()
	for index: int in range(3):
		assert_true(inbox.enqueue(_make("body:%d" % index, &"body_found", NpcObservation.Modality.SIGHT, 5.0)))
	assert_eq(inbox.pending_observations().size(), 3)
	assert_true(inbox.diagnostics().is_empty())

func test_duplicate_id_and_receipt_replay_are_rejected() -> void:
	var inbox := NpcEvidenceInbox.new()
	assert_true(inbox.enqueue(_sight("a", 1.0)))
	var version_before: int = inbox.version
	assert_false(inbox.enqueue(_sight("a", 2.0)))
	assert_eq(inbox.version, version_before)
	assert_not_null(inbox.claim("a", 1.0))
	assert_true(inbox.complete("a"))
	assert_true(inbox.has_receipt("a"))
	assert_false(inbox.contains_pending("a"))
	assert_false(inbox.enqueue(_sight("a", 3.0)))
	assert_eq(inbox.ready_count(10.0), 0)
	assert_false(inbox.enqueue(null))
	var invalid: NpcObservation = _sight("b", 1.0)
	invalid.text = ""
	assert_false(inbox.enqueue(invalid))
	assert_false(inbox.contains_pending("b"))

func test_lifecycle_and_idempotence() -> void:
	var inbox := NpcEvidenceInbox.new()
	inbox.enqueue(_sight("a", 1.0))
	assert_false(inbox.complete("a"), "pending items cannot complete")
	assert_false(inbox.fail("a", "x", 1.0))
	assert_false(inbox.release("a"))
	assert_null(inbox.claim("missing", 1.0))
	var claimed: NpcObservation = inbox.claim("a", 1.0)
	assert_not_null(claimed)
	assert_eq(claimed.observation_id, "a")
	assert_eq(inbox.item("a")["status"], "CLAIMED")
	assert_null(inbox.claim("a", 1.0), "a claimed item cannot be claimed twice")
	assert_null(inbox.next_ready(1.0))
	assert_eq(inbox.ready_count(1.0), 0)
	assert_true(inbox.release("a"))
	assert_false(inbox.release("a"))
	assert_eq(inbox.item("a")["status"], "PENDING")
	assert_eq(inbox.item("a")["attempts"], 0)
	inbox.claim("a", 1.0)
	var version_before_complete: int = inbox.version
	assert_true(inbox.complete("a"))
	assert_eq(inbox.version, version_before_complete + 1)
	assert_false(inbox.complete("a"))
	assert_eq(inbox.version, version_before_complete + 1)
	assert_false(inbox.fail("a", "late", 2.0))
	assert_eq(inbox.item("a"), {})

func test_failed_items_become_ready_after_the_first_ladder_step() -> void:
	var inbox := NpcEvidenceInbox.new()
	inbox.enqueue(_sight("a", 1.0))
	inbox.claim("a", 10.0)
	assert_true(inbox.fail("a", "provider unavailable", 10.0))
	var record: Dictionary = inbox.item("a")
	assert_eq(record["status"], "DEFERRED")
	assert_eq(record["attempts"], 1)
	assert_eq(record["retry_after"], 10.0 + NpcEvidenceInbox.RETRY_LADDER_MSEC[0])
	assert_eq(record["last_error"], "provider unavailable")
	assert_true(inbox.contains_pending("a"))
	assert_eq(inbox.ready_count(11.0), 0)
	assert_null(inbox.next_ready(11.0))
	assert_null(inbox.claim("a", 11.0))
	assert_eq(inbox.ready_count(2010.0), 1)
	assert_not_null(inbox.claim("a", 2010.0))
	assert_true(inbox.fail("a", "again", 2010.0))
	assert_eq(inbox.item("a")["attempts"], 2)

func test_retry_ladder_is_2_10_30_seconds_then_a_60_second_backoff() -> void:
	assert_eq(NpcEvidenceInbox.RETRY_LADDER_MSEC, [2000, 10000, 30000] as Array[int])
	assert_eq(NpcEvidenceInbox.RETRY_BACKOFF_MSEC, 60000)
	var inbox := NpcEvidenceInbox.new()
	inbox.enqueue(_sight("a", 1.0))
	var now: float = 1000.0
	for expected: float in [2000.0, 10000.0, 30000.0, 60000.0, 60000.0]:
		assert_not_null(inbox.claim("a", now))
		assert_true(inbox.fail("a", "provider unavailable", now))
		assert_eq(inbox.item("a")["retry_after"], now + expected)
		assert_eq(inbox.ready_count(now + expected - 1.0), 0)
		assert_eq(inbox.ready_count(now + expected), 1)
		now += expected
	assert_eq(inbox.item("a")["attempts"], 5)

func test_wake_backoff_releases_only_items_past_the_ladder() -> void:
	var inbox := NpcEvidenceInbox.new()
	inbox.enqueue(_sight("ladder", 1.0))
	inbox.enqueue(_sight("backoff", 2.0))
	var now: float = 1000.0
	inbox.claim("ladder", now)
	inbox.fail("ladder", "x", now)
	for _attempt: int in range(NpcEvidenceInbox.RETRY_LADDER_MSEC.size() + 1):
		inbox.claim("backoff", INF)
		inbox.fail("backoff", "x", now)
		now += 100000.0
	var version_before: int = inbox.version
	var waiting_until: float = inbox.item("backoff")["retry_after"]
	assert_true(waiting_until > 0.0)
	assert_eq(inbox.wake_backoff(), 1, "Only the item past the ladder wakes")
	assert_eq(inbox.item("backoff")["retry_after"], 0.0)
	assert_eq(inbox.item("ladder")["retry_after"], 1000.0 + NpcEvidenceInbox.RETRY_LADDER_MSEC[0],
		"One malformed answer must not turn the ladder into a tight loop")
	assert_true(inbox.version > version_before)
	assert_eq(inbox.next_ready(0.0).observation_id, "backoff")
	assert_eq(inbox.wake_backoff(), 0)

func test_next_ready_orders_protected_then_oldest_then_insertion() -> void:
	var inbox := NpcEvidenceInbox.new()
	inbox.enqueue(_sight("late", 30.0))
	inbox.enqueue(_sight("early_b", 10.0))
	inbox.enqueue(_sight("early_a", 10.0))
	assert_eq(inbox.next_ready(100.0).observation_id, "early_b")
	inbox.enqueue(_make("body", &"body_found", NpcObservation.Modality.SIGHT, 90.0))
	assert_eq(inbox.next_ready(100.0).observation_id, "body")
	var returned: NpcObservation = inbox.next_ready(100.0)
	returned.text = "mutated"
	assert_ne(inbox.next_ready(100.0).text, "mutated")

func test_ready_window_is_bounded() -> void:
	var inbox := NpcEvidenceInbox.new()
	for index: int in range(NpcEvidenceInbox.READY_WINDOW + 10):
		inbox.enqueue(_sight("s%d" % index, float(index)))
	assert_eq(inbox.ready_count(100.0), NpcEvidenceInbox.READY_WINDOW)
	assert_eq(inbox.pending_observations().size(), NpcEvidenceInbox.READY_WINDOW + 10)

func test_capacity_drops_oldest_unprotected_and_never_protected() -> void:
	var inbox := NpcEvidenceInbox.new()
	assert_true(inbox.enqueue(_make("protected_first", &"actor_died", NpcObservation.Modality.SIGHT, 0.0)))
	for index: int in range(1, NpcEvidenceInbox.MAX_ITEMS):
		assert_true(inbox.enqueue(_sight("s%d" % index, float(index))))
	assert_eq(inbox.pending_observations().size(), NpcEvidenceInbox.MAX_ITEMS)
	assert_true(inbox.enqueue(_sight("overflow", 1000.0)))
	assert_eq(inbox.pending_observations().size(), NpcEvidenceInbox.MAX_ITEMS)
	assert_true(inbox.contains_pending("protected_first"))
	assert_false(inbox.contains_pending("s1"), "oldest unprotected item is dropped")
	assert_true(inbox.contains_pending("s2"))
	assert_true(inbox.contains_pending("overflow"))
	var diagnostics: Array[Dictionary] = inbox.diagnostics()
	assert_eq(diagnostics[-1], {"dropped_id": "s1", "reason": "capacity"})

func test_capacity_accepts_protected_evidence_when_nothing_can_be_dropped() -> void:
	var inbox := NpcEvidenceInbox.new()
	for index: int in range(NpcEvidenceInbox.MAX_ITEMS):
		assert_true(inbox.enqueue(_make("p%d" % index, &"body_found", NpcObservation.Modality.SIGHT, float(index))))
	assert_true(inbox.enqueue(_make("extra", &"actor_died", NpcObservation.Modality.SIGHT, 999.0)))
	assert_eq(inbox.pending_observations().size(), NpcEvidenceInbox.MAX_ITEMS + 1)
	assert_true(inbox.contains_pending("p0"))
	assert_true(inbox.contains_pending("extra"))
	assert_true(inbox.diagnostics().is_empty())
	assert_true(inbox.enqueue(_sight("plain", 1000.0)))
	assert_eq(inbox.pending_observations().size(), NpcEvidenceInbox.MAX_ITEMS + 2)

func test_claimed_items_are_not_dropped_at_capacity() -> void:
	var inbox := NpcEvidenceInbox.new()
	for index: int in range(NpcEvidenceInbox.MAX_ITEMS):
		inbox.enqueue(_sight("s%d" % index, float(index)))
	assert_not_null(inbox.claim("s0", 1000.0))
	inbox.enqueue(_sight("overflow", 1000.0))
	assert_true(inbox.contains_pending("s0"))
	assert_false(inbox.contains_pending("s1"))
	assert_true(inbox.complete("s0"))

func test_receipts_at_the_bound_refuse_completion_instead_of_dropping_one() -> void:
	var inbox := NpcEvidenceInbox.new()
	for index: int in range(NpcEvidenceInbox.MAX_RECEIPTS):
		var id: String = "r%d" % index
		inbox.enqueue(_sight(id, 1.0))
		inbox.claim(id, 1.0)
		assert_true(inbox.complete(id))
	inbox.enqueue(_sight("over", 1.0))
	assert_not_null(inbox.claim("over", 1.0))
	assert_false(inbox.complete("over"))
	assert_true(inbox.has_receipt("r0"))
	assert_false(inbox.has_receipt("over"))
	assert_true(inbox.contains_pending("over"))
	assert_eq(inbox.receipt_count(), NpcEvidenceInbox.MAX_RECEIPTS)

func test_incident_grouping_rules() -> void:
	var inbox := NpcEvidenceInbox.new()
	inbox.enqueue(_fight("h1", 100.0, &"actor_hurt", "victim", "attacker"))
	inbox.enqueue(_fight("h2", 105.0, &"actor_hurt", "victim", "attacker"))
	assert_eq(_incident(inbox, "h1"), _incident(inbox, "h2"))
	assert_false(_incident(inbox, "h1").is_empty())
	# Within the window of the incident's latest observation, not its first.
	inbox.enqueue(_fight("h3", 114.0, &"actor_hurt", "victim", "attacker"))
	assert_eq(_incident(inbox, "h3"), _incident(inbox, "h1"))
	# More than ten minutes after the latest observation starts a new incident.
	inbox.enqueue(_fight("h4", 125.0, &"actor_hurt", "victim", "attacker"))
	assert_ne(_incident(inbox, "h4"), _incident(inbox, "h1"))
	# A death is always distinct.
	inbox.enqueue(_fight("d1", 126.0, &"actor_died", "victim", "attacker"))
	assert_ne(_incident(inbox, "d1"), _incident(inbox, "h4"))
	# A different identified victim is distinct.
	inbox.enqueue(_fight("v2", 127.0, &"actor_hurt", "other_victim", "attacker"))
	assert_ne(_incident(inbox, "v2"), _incident(inbox, "h4"))
	assert_ne(_incident(inbox, "v2"), _incident(inbox, "d1"))
	# Different places are distinct.
	var elsewhere: NpcObservation = _fight("h5", 127.0, &"actor_hurt", "victim", "attacker")
	elsewhere.space_id = &"home:garrin_holt"
	inbox.enqueue(elsewhere)
	assert_ne(_incident(inbox, "h5"), _incident(inbox, "h4"))

func test_unidentified_noise_groups_by_place_and_time_without_identities() -> void:
	var inbox := NpcEvidenceInbox.new()
	var first: NpcObservation = _make("c1", &"combat_noise", NpcObservation.Modality.NOISE, 10.0)
	var second: NpcObservation = _make("c2", &"combat_noise", NpcObservation.Modality.NOISE, 14.0)
	var third: NpcObservation = _make("c3", &"combat_noise", NpcObservation.Modality.NOISE, 40.0)
	assert_true(inbox.enqueue(first))
	assert_true(inbox.enqueue(second))
	assert_true(inbox.enqueue(third))
	assert_eq(inbox.item("c1")["count"], 2)
	assert_eq(inbox.item("c3")["count"], 1)
	assert_ne(_incident(inbox, "c3"), _incident(inbox, "c1"))
	assert_true(inbox.item("c1")["observation"]["participants"].is_empty())
	# Combat noise and a sighting of the same place are different families of evidence.
	assert_true(inbox.enqueue(_fight("s", 41.0, &"actor_hurt", "x", "")))
	assert_eq(inbox.pending_observations().size(), 3)

func test_explicit_incident_id_is_kept() -> void:
	var inbox := NpcEvidenceInbox.new()
	var observation: NpcObservation = _sight("a", 1.0)
	observation.incident_id = "incident:given"
	inbox.enqueue(observation)
	assert_eq(_incident(inbox, "a"), "incident:given")

func test_producer_mutation_after_enqueue_does_not_change_stored_evidence() -> void:
	var inbox := NpcEvidenceInbox.new()
	var people: Array[Dictionary] = [_person("garrin_holt", "hurt_person")]
	var observation: NpcObservation = _make("a", &"actor_hurt", NpcObservation.Modality.SIGHT, 5.0, people)
	observation.topics = ["combat"]
	observation.facts = {"danger_possible": true}
	assert_true(inbox.enqueue(observation))
	observation.text = "rewritten"
	observation.kind = &"actor_died"
	observation.participants[0]["id"] = "den"
	observation.participants.append(_person("extra", "aggressor"))
	observation.topics.append("lie")
	observation.facts["danger_possible"] = false
	var stored: NpcObservation = inbox.pending_observations()[0]
	assert_eq(stored.text, "Observation a")
	assert_eq(stored.kind, &"actor_hurt")
	assert_eq(stored.participant_ids(), ["garrin_holt"] as Array[String])
	assert_eq(stored.topics, ["combat"] as Array[String])
	assert_eq(stored.facts["danger_possible"], true)
	stored.text = "also rewritten"
	assert_eq(inbox.pending_observations()[0].text, "Observation a")
	assert_eq(inbox.item("a")["observation"]["text"], "Observation a")

func test_version_increments_on_every_mutation() -> void:
	var inbox := NpcEvidenceInbox.new()
	var seen: int = inbox.version
	inbox.enqueue(_sight("a", 1.0))
	assert_true(inbox.version > seen)
	seen = inbox.version
	inbox.claim("a", 1.0)
	assert_true(inbox.version > seen)
	seen = inbox.version
	inbox.fail("a", "x", 1.0)
	assert_true(inbox.version > seen)
	seen = inbox.version
	inbox.ready_count(5.0)
	inbox.next_ready(5.0)
	inbox.pending_observations()
	assert_eq(inbox.version, seen)

func test_json_round_trip_preserves_state_and_converts_claims_to_pending() -> void:
	var inbox := NpcEvidenceInbox.new()
	inbox.enqueue(_make("body", &"body_found", NpcObservation.Modality.SIGHT, 5.0,
		[_person("garrin_holt", "deceased")]))
	inbox.enqueue(_sight("claimed", 6.0))
	inbox.enqueue(_sight("failed", 7.0))
	inbox.enqueue(_sight("done", 8.0))
	for index: int in range(5):
		inbox.enqueue(_noise("n%d" % index, 9.0 + index))
	inbox.claim("claimed", 10.0)
	inbox.claim("failed", 10.0)
	inbox.fail("failed", "provider unavailable", 10.0)
	inbox.claim("done", 10.0)
	inbox.complete("done")
	var saved: Dictionary = inbox.to_data()
	assert_true(NpcEvidenceInbox.is_valid_data(saved))
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	assert_true(NpcEvidenceInbox.is_valid_data(parsed))
	var restored := NpcEvidenceInbox.new()
	assert_true(restored.from_data(parsed))
	assert_eq(JSON.stringify(restored.to_data()), JSON.stringify(saved))
	assert_eq(restored.item("claimed")["status"], "PENDING")
	assert_not_null(restored.claim("claimed", 11.0))
	assert_eq(restored.item("failed")["status"], "DEFERRED")
	assert_eq(restored.item("failed")["attempts"], 1)
	assert_true(restored.item("failed")["attempts"] is int)
	assert_eq(restored.item("failed")["last_error"], "provider unavailable")
	assert_eq(restored.item("n0")["count"], 5)
	assert_true(restored.item("n0")["count"] is int)
	assert_true(restored.has_receipt("done"))
	assert_false(restored.enqueue(_sight("done", 20.0)))
	assert_eq(restored.diagnostics().size(), 4)
	assert_eq(restored.pending_observations().size(), inbox.pending_observations().size())
	assert_true(restored.contains_pending("body"))
	# The incident counter and recent incidents continue after a reload.
	restored.enqueue(_fight("h1", 100.0, &"actor_hurt", "victim", "attacker"))
	restored.enqueue(_fight("h2", 101.0, &"actor_hurt", "victim", "attacker"))
	assert_eq(_incident(restored, "h1"), _incident(restored, "h2"))
	var reloaded := NpcEvidenceInbox.new()
	assert_true(reloaded.from_data(JSON.parse_string(JSON.stringify(restored.to_data()))))
	reloaded.enqueue(_fight("h3", 102.0, &"actor_hurt", "victim", "attacker"))
	assert_eq(_incident(reloaded, "h3"), _incident(restored, "h1"))
	reloaded.enqueue(_fight("h4", 300.0, &"actor_hurt", "victim", "attacker"))
	assert_ne(_incident(reloaded, "h4"), _incident(restored, "h1"))

func test_from_data_is_atomic_and_rejects_invalid_data() -> void:
	var source := NpcEvidenceInbox.new()
	source.enqueue(_sight("a", 1.0))
	source.enqueue(_sight("b", 2.0))
	source.claim("b", 2.0)
	source.complete("b")
	var good: Dictionary = source.to_data()
	var target := NpcEvidenceInbox.new()
	target.enqueue(_sight("keep", 1.0))
	var before: String = JSON.stringify(target.to_data())
	var version_before: int = target.version
	var mutations: Array[Callable] = [
		func(data: Dictionary) -> void: data.erase("receipts"),
		func(data: Dictionary) -> void: data["version"] = 2,
		func(data: Dictionary) -> void: data["incident_counter"] = -1,
		func(data: Dictionary) -> void: data["items"] = "none",
		func(data: Dictionary) -> void: data["items"][0]["status"] = "CLAIMED",
		func(data: Dictionary) -> void: data["items"][0]["count"] = 0,
		func(data: Dictionary) -> void: data["items"][0]["count"] = 3,
		func(data: Dictionary) -> void: data["items"][0]["observation"]["text"] = "",
		func(data: Dictionary) -> void: data["items"][0]["observation"]["incident_id"] = "",
		func(data: Dictionary) -> void: data["items"].append(data["items"][0].duplicate(true)),
		func(data: Dictionary) -> void: data["receipts"].append("a"),
		func(data: Dictionary) -> void: data["receipts"] = ["b", "b"],
		func(data: Dictionary) -> void: data["incidents"] = [{"incident_id": "x"}],
		func(data: Dictionary) -> void: data["diagnostics"] = [{"unexpected": true}]]
	for index: int in mutations.size():
		var mutated: Dictionary = good.duplicate(true)
		mutations[index].call(mutated)
		assert_false(NpcEvidenceInbox.is_valid_data(mutated), "mutation %d accepted" % index)
		assert_false(target.from_data(mutated), "mutation %d loaded" % index)
	assert_false(target.from_data(null))
	assert_eq(JSON.stringify(target.to_data()), before)
	assert_eq(target.version, version_before)
	assert_true(target.contains_pending("keep"))
	assert_true(target.from_data(good))
	assert_false(target.contains_pending("keep"))
	assert_true(target.contains_pending("a"))
	assert_true(target.has_receipt("b"))
