extends "res://tests/test_case.gd"

const OBSERVED := NpcKnowledge.Status.OBSERVED
const REPORTED := NpcKnowledge.Status.REPORTED
const INFERRED := NpcKnowledge.Status.INFERRED

func _place(space: String, x: float, y: float) -> Dictionary:
	return {"space": space, "x": x, "y": y}

func _statuses(facts: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for fact: Dictionary in facts:
		result.append(fact["status"])
	return result

func test_invalid_arguments_are_rejected_without_change() -> void:
	var knowledge := NpcKnowledge.new()
	var where: Dictionary = _place("outdoors", 1.0, 2.0)
	assert_false(knowledge.record("", "location", where, OBSERVED, "self", "e", "o", 1.0, 1.0))
	assert_false(knowledge.record("a", "", where, OBSERVED, "self", "e", "o", 1.0, 1.0))
	assert_false(knowledge.record("a".repeat(201), "location", where, OBSERVED, "self", "e", "o", 1.0, 1.0))
	assert_false(knowledge.record("a", "location", where, OBSERVED, "self", "e", "o", -1.0, 1.0))
	assert_false(knowledge.record("a", "location", where, OBSERVED, "self", "e", "o", INF, 1.0))
	assert_false(knowledge.record("a", "location", where, OBSERVED, "self", "e", "o", 1.0, 1.5))
	assert_false(knowledge.record("a", "location", {"space": "outdoors"}, OBSERVED, "self", "e", "o", 1.0, 1.0))
	assert_false(knowledge.record("a", "mood", Vector2.ONE, OBSERVED, "self", "e", "o", 1.0, 1.0))
	assert_false(knowledge.record("a", "mood", NAN, OBSERVED, "self", "e", "o", 1.0, 1.0))
	assert_false(knowledge.record("a", "mood", "calm", NpcKnowledge.Status.CONTESTED, "self", "e", "o", 1.0, 1.0))
	assert_eq(knowledge.version, 0)
	assert_false(knowledge.knows("a", "location"))

func test_same_value_from_a_new_origin_corroborates_and_same_origin_does_not() -> void:
	var knowledge := NpcKnowledge.new()
	var where: Dictionary = _place("outdoors", 5.0, 6.0)
	assert_true(knowledge.record_report("mara", "location", where, "tess", "report:1", "ev:1", 10.0, 0.6))
	var version: int = knowledge.version
	assert_false(knowledge.record_report("mara", "location", where, "bram", "report:1", "ev:2", 11.0, 0.9))
	assert_eq(knowledge.version, version)
	assert_true(knowledge.record_report("mara", "location", where, "bram", "report:2", "ev:3", 12.0, 0.9))
	var facts: Array[Dictionary] = knowledge.current("mara", "location")
	assert_eq(facts.size(), 1)
	assert_eq(facts[0]["origin_ids"], ["report:1", "report:2"] as Array[String])
	assert_eq(facts[0]["evidence_ids"], ["ev:1", "ev:3"] as Array[String])
	assert_eq(facts[0]["status"], "REPORTED")
	assert_eq(facts[0]["observed_minute"], 12.0)
	assert_true(knowledge.version > version)

func test_firsthand_corroboration_upgrades_a_report_to_observed() -> void:
	var knowledge := NpcKnowledge.new()
	var where: Dictionary = _place("outdoors", 5.0, 6.0)
	knowledge.record_report("mara", "location", where, "tess", "report:1", "ev:1", 10.0, 0.6)
	assert_true(knowledge.record_sighting("mara", "outdoors", Vector2(5, 6), 20.0, "ev:2"))
	var facts: Array[Dictionary] = knowledge.current("mara", "location")
	assert_eq(facts.size(), 1)
	assert_eq(facts[0]["status"], "OBSERVED")
	assert_eq(facts[0]["origin_ids"].size(), 2)

func test_newer_sighting_supersedes_older_report_and_observation() -> void:
	var knowledge := NpcKnowledge.new()
	knowledge.record_report("mara", "location", _place("market", 1.0, 1.0), "tess", "report:1", "ev:1", 10.0, 0.6)
	assert_true(knowledge.record_sighting("mara", "outdoors", Vector2(40, 8), 30.0, "ev:2"))
	var locations: Array[Dictionary] = knowledge.known_locations("mara")
	assert_eq(locations.size(), 1)
	assert_eq(locations[0]["status"], "OBSERVED")
	assert_eq(locations[0]["value"], _place("outdoors", 40.0, 8.0))
	assert_true(knowledge.record_sighting("mara", "outdoors", Vector2(50, 8), 31.0, "ev:3"))
	assert_eq(knowledge.known_locations("mara").size(), 1)
	assert_eq(knowledge.known_locations("mara")[0]["value"], _place("outdoors", 50.0, 8.0))

func test_sightings_in_the_same_tenth_of_a_minute_dedupe() -> void:
	var knowledge := NpcKnowledge.new()
	assert_true(knowledge.record_sighting("mara", "outdoors", Vector2(1, 1), 30.01, "ev:1"))
	assert_false(knowledge.record_sighting("mara", "outdoors", Vector2(1, 1), 30.04, "ev:2"))
	assert_true(knowledge.record_sighting("mara", "outdoors", Vector2(1, 1), 30.2, "ev:3"))

func test_older_sighting_is_not_stored_because_the_newer_one_already_supersedes_it() -> void:
	var knowledge := NpcKnowledge.new()
	knowledge.record_sighting("mara", "outdoors", Vector2(10, 10), 50.0, "ev:1")
	assert_false(knowledge.record_sighting("mara", "market", Vector2(2, 2), 20.0, "ev:2"))
	var locations: Array[Dictionary] = knowledge.known_locations("mara")
	assert_eq(locations.size(), 1)
	assert_eq(locations[0]["value"], _place("outdoors", 10.0, 10.0))
	assert_eq(knowledge.to_data()["facts"].size(), 1)

func test_superseded_sightings_are_discarded_not_kept_as_history() -> void:
	var knowledge := NpcKnowledge.new()
	for step: int in 20:
		knowledge.record_sighting("mara", "outdoors", Vector2(step * 20, 0), 10.0 + step, "ev:%d" % step)
	assert_eq(knowledge.to_data()["facts"].size(), 1)

func test_conflicting_reports_stay_contested() -> void:
	var knowledge := NpcKnowledge.new()
	knowledge.record_report("mara", "location", _place("market", 1.0, 1.0), "tess", "report:1", "ev:1", 10.0, 0.6)
	assert_true(knowledge.record_report("mara", "location", _place("garden", 9.0, 9.0), "bram", "report:2", "ev:2", 12.0, 0.6))
	var facts: Array[Dictionary] = knowledge.current("mara", "location")
	assert_eq(facts.size(), 2)
	assert_eq(_statuses(facts), ["CONTESTED", "CONTESTED"] as Array[String])
	assert_eq(facts[0]["observed_minute"], 12.0, "newest first")
	assert_true(knowledge.record_report("mara", "location", _place("school", 3.0, 3.0), "kell", "report:3", "ev:3", 13.0, 0.6))
	assert_eq(knowledge.current("mara", "location").size(), 3)

func test_report_older_than_a_firsthand_sighting_does_not_replace_it() -> void:
	var knowledge := NpcKnowledge.new()
	knowledge.record_sighting("mara", "outdoors", Vector2(10, 10), 50.0, "ev:1")
	assert_true(knowledge.record_report("mara", "location", _place("market", 1.0, 1.0), "tess", "report:1", "ev:2", 40.0, 0.6))
	var facts: Array[Dictionary] = knowledge.current("mara", "location")
	assert_eq(facts.size(), 2)
	assert_eq(facts[0]["status"], "OBSERVED")
	assert_eq(facts[1]["status"], "CONTESTED")

func test_report_newer_than_a_sighting_contests_both() -> void:
	var knowledge := NpcKnowledge.new()
	knowledge.record_sighting("mara", "outdoors", Vector2(10, 10), 50.0, "ev:1")
	assert_true(knowledge.record_report("mara", "location", _place("market", 1.0, 1.0), "tess", "report:1", "ev:2", 60.0, 0.6))
	assert_eq(_statuses(knowledge.current("mara", "location")), ["CONTESTED", "CONTESTED"] as Array[String])

func test_one_source_updating_its_own_location_replaces_the_old_report() -> void:
	var knowledge := NpcKnowledge.new()
	knowledge.record_report("mara", "location", _place("market", 1.0, 1.0), "tess", "report:1", "ev:1", 10.0, 0.6)
	assert_true(knowledge.record_report("mara", "location", _place("garden", 9.0, 9.0), "tess", "report:2", "ev:2", 20.0, 0.6))
	var facts: Array[Dictionary] = knowledge.current("mara", "location")
	assert_eq(facts.size(), 1)
	assert_eq(facts[0]["status"], "REPORTED")
	assert_eq(facts[0]["value"], _place("garden", 9.0, 9.0))
	assert_true(knowledge.record_report("mara", "location", _place("school", 3.0, 3.0), "tess", "report:0", "ev:0", 5.0, 0.6))
	assert_eq(knowledge.known_locations("mara")[0]["value"], _place("garden", 9.0, 9.0), "an older statement is history")
	assert_eq(knowledge.known_locations("mara").size(), 1)

func test_other_predicates_do_not_get_the_same_source_exception() -> void:
	var knowledge := NpcKnowledge.new()
	knowledge.record_report("mara", "occupation", "baker", "tess", "report:1", "ev:1", 10.0, 0.6)
	knowledge.record_report("mara", "occupation", "miller", "tess", "report:2", "ev:2", 20.0, 0.6)
	assert_eq(_statuses(knowledge.current("mara", "occupation")), ["CONTESTED", "CONTESTED"] as Array[String])

func test_inferred_conflict_with_a_current_observation_is_contested_alongside() -> void:
	var knowledge := NpcKnowledge.new()
	knowledge.record("mara", "mood", "calm", OBSERVED, "self", "ev:1", "o:1", 10.0, 1.0)
	assert_true(knowledge.record("mara", "mood", "angry", INFERRED, "self", "ev:2", "o:2", 10.0, 0.4))
	var facts: Array[Dictionary] = knowledge.current("mara", "mood")
	assert_eq(_statuses(facts).size(), 2)
	assert_true("OBSERVED" in _statuses(facts) and "CONTESTED" in _statuses(facts))

func test_help_places_are_a_set_not_rival_beliefs() -> void:
	var knowledge := NpcKnowledge.new()
	var first: Dictionary = {"place": "home:g", "space": "home:g", "x": 1.0, "y": 1.0, "kind": "guard_home"}
	var second: Dictionary = {"place": "patrol:0", "space": "outdoors", "x": 5.0, "y": 5.0, "kind": "patrol_point"}
	assert_true(knowledge.record("town", "help_place", first, OBSERVED, "public", "e1", "o1", 0.0, 1.0))
	assert_true(knowledge.record("town", "help_place", second, OBSERVED, "public", "e2", "o1", 0.0, 1.0))
	assert_eq(knowledge.known_help_places().size(), 2)

func test_read_projections_are_copies() -> void:
	var knowledge := NpcKnowledge.new()
	knowledge.record_sighting("mara", "outdoors", Vector2(10, 10), 50.0, "ev:1")
	var locations: Array[Dictionary] = knowledge.known_locations("mara")
	locations[0]["value"]["x"] = 999.0
	locations[0]["origin_ids"].append("forged")
	locations.clear()
	var again: Array[Dictionary] = knowledge.known_locations("mara")
	assert_eq(again.size(), 1)
	assert_eq(again[0]["value"]["x"], 10.0)
	assert_eq(again[0]["origin_ids"].size(), 1)
	var data: Dictionary = knowledge.to_data()
	data["facts"][0]["subject"] = "other"
	assert_true(knowledge.knows("mara", "location"))
	var recorded: Dictionary = _place("outdoors", 1.0, 1.0)
	knowledge.record_report("bram", "location", recorded, "tess", "r", "e", 1.0, 0.5)
	recorded["x"] = 77.0
	assert_eq(knowledge.known_locations("bram")[0]["value"]["x"], 1.0)

func _population() -> Dictionary:
	return {
		"holt": {"name": "Holt Ardent", "job": "smith", "household": "ardent", "kin": {"wren": "spouse", "pip": "child"}},
		"wren": {"name": "Wren Ardent", "job": "baker", "household": "ardent", "kin": {"holt": "spouse", "pip": "child"}},
		"pip": {"name": "Pip Ardent", "job": "student", "household": "ardent", "kin": {"holt": "father", "wren": "mother"}},
		"stranger": {"name": "Odd Stranger", "job": "fisher", "household": "odd", "kin": {"far": "cousin"}},
		"guard": {"name": "Voss", "job": "guard", "household": "voss", "kin": {}},
	}

func _places() -> Dictionary:
	return {
		"square": {"label": "square", "position": Vector2(1, 2)},
		"market": {"label": "market", "position": Vector2(3, 4)},
		"school": {"label": "school", "position": Vector2(5, 6)},
		"patrol:0": {"label": "watch route", "position": Vector2(7, 8)},
		"patrol:1": {"label": "watch route", "position": Vector2(9, 10)},
		"home:holt": {"label": "ardent home", "position": Vector2(11, 12), "space": "home:ardent"},
		"work:holt": {"label": "forge", "position": Vector2(13, 14), "space": "home:ardent"},
		"home:wren": {"label": "ardent home", "position": Vector2(15, 16), "space": "home:ardent"},
		"home:pip": {"label": "ardent home", "position": Vector2(17, 18), "space": "home:ardent"},
		"home:stranger": {"label": "odd home", "position": Vector2(19, 20), "space": "home:odd"},
		"home:guard": {"label": "voss home", "position": Vector2(21, 22), "space": "home:voss"},
		"work:stranger": {"label": "docks", "position": Vector2(23, 24)},
	}

func test_bootstrap_records_only_public_stable_knowledge_and_is_idempotent() -> void:
	var knowledge := NpcKnowledge.new()
	knowledge.bootstrap_public("holt", _population(), _places(), ["guard"] as Array[String])
	var version: int = knowledge.version
	var snapshot: Dictionary = knowledge.to_data()
	assert_true(version > 0)
	knowledge.bootstrap_public("holt", _population(), _places(), ["guard"] as Array[String])
	assert_eq(knowledge.version, version)
	assert_eq(knowledge.to_data(), snapshot)
	for subject: String in ["holt", "wren", "pip", "stranger", "guard"]:
		assert_false(knowledge.knows(subject, "location"), "no live positions for " + subject)
		assert_true(knowledge.knows(subject, "identity"))
	var identity: Dictionary = knowledge.current("wren", "identity")[0]["value"]
	assert_eq(identity, {"name": "Wren Ardent", "job": "baker", "household": "ardent"})
	assert_eq(knowledge.current("wren", "identity")[0]["status"], "OBSERVED")
	assert_eq(knowledge.current("wren", "identity")[0]["source_id"], "public")

func test_bootstrap_family_roles_cover_only_this_npcs_relatives() -> void:
	var knowledge := NpcKnowledge.new()
	knowledge.bootstrap_public("holt", _population(), _places(), [] as Array[String])
	assert_eq(knowledge.current("wren", "family_role")[0]["value"], "spouse")
	assert_eq(knowledge.current("pip", "family_role")[0]["value"], "child")
	assert_false(knowledge.knows("holt", "family_role"))
	assert_false(knowledge.knows("stranger", "family_role"))
	assert_false(knowledge.knows("far", "family_role"))

func test_bootstrap_places_are_public_venues_own_rooms_and_relatives_homes() -> void:
	var knowledge := NpcKnowledge.new()
	knowledge.bootstrap_public("holt", _population(), _places(), ["guard"] as Array[String])
	var ids: Array[String] = []
	for fact: Dictionary in knowledge.known_places():
		ids.append(fact["subject"])
	ids.sort()
	var expected: Array[String] = ["square", "market", "school", "patrol:0", "patrol:1",
		"home:holt", "work:holt", "home:wren", "home:pip"]
	expected.sort()
	assert_eq(ids, expected)
	assert_false(knowledge.knows("home:stranger", "familiar_place"))
	assert_false(knowledge.knows("home:guard", "familiar_place"))
	var forge: Dictionary = knowledge.current("work:holt", "familiar_place")[0]["value"]
	assert_eq(forge["space"], "home:ardent")
	assert_eq(forge["x"], 13.0)
	assert_eq(knowledge.current("square", "familiar_place")[0]["value"]["space"], "outdoors")

func test_bootstrap_help_places_include_guard_homes_and_patrol_points() -> void:
	var knowledge := NpcKnowledge.new()
	knowledge.bootstrap_public("holt", _population(), _places(), ["guard"] as Array[String])
	var kinds: Dictionary = {}
	for fact: Dictionary in knowledge.known_help_places():
		kinds[fact["value"]["place"]] = fact["value"]["kind"]
	assert_eq(kinds, {"home:guard": "guard_home", "patrol:0": "patrol_point", "patrol:1": "patrol_point"})
	var guard_home: Dictionary = {}
	for fact: Dictionary in knowledge.known_help_places():
		if fact["value"]["place"] == "home:guard":
			guard_home = fact["value"]
	assert_eq(guard_home, {"place": "home:guard", "space": "home:voss", "x": 21.0, "y": 22.0, "kind": "guard_home"})

func test_bootstrap_skips_missing_data_silently() -> void:
	var knowledge := NpcKnowledge.new()
	knowledge.bootstrap_public("ghost", {"x": {"name": "No Job"}, "y": 5}, {"home:guard": {"label": "bad"}}, ["guard", "nobody"] as Array[String])
	assert_eq(knowledge.known_help_places().size(), 0)
	assert_eq(knowledge.known_places().size(), 0)
	assert_false(knowledge.knows("x", "identity"))

func test_capacity_evicts_superseded_before_current_and_never_public() -> void:
	var knowledge := NpcKnowledge.new()
	knowledge.bootstrap_public("holt", _population(), _places(), [] as Array[String])
	knowledge.record_report("rival", "mood", "calm", "a", "o:a", "e", 3.0, 0.5)
	knowledge.record_report("rival", "mood", "angry", "b", "o:b", "e", 4.0, 0.5)
	knowledge.record("mara", "mood", "calm", OBSERVED, "x", "e", "m:1", 1.0, 1.0)
	knowledge.record("mara", "mood", "tense", OBSERVED, "x", "e", "m:2", 2.0, 1.0)
	var used: int = knowledge.to_data()["facts"].size()
	for index: int in range(1, NpcKnowledge.MAX_FACTS - used + 1):
		assert_true(knowledge.record_report("p%d" % index, "note", "x", "a", "o:%d" % index, "e", 10.0 + index, 0.5))
	assert_eq(knowledge.to_data()["facts"].size(), NpcKnowledge.MAX_FACTS)
	assert_true(knowledge.record_report("overflow", "note", "x", "a", "o:overflow", "e", 5000.0, 0.5))
	var facts: Array = knowledge.to_data()["facts"]
	assert_eq(facts.size(), NpcKnowledge.MAX_FACTS)
	var superseded: int = 0
	for fact: Dictionary in facts:
		if fact["status"] == "SUPERSEDED":
			superseded += 1
	assert_eq(superseded, 0, "the superseded fact was evicted first")
	assert_eq(knowledge.current("rival", "mood").size(), 2, "contested facts survive")
	assert_true(knowledge.knows("overflow", "note"))
	assert_true(knowledge.knows("p1", "note"))
	assert_true(knowledge.knows("wren", "identity"))

func test_capacity_evicts_oldest_non_public_when_nothing_is_superseded() -> void:
	var knowledge := NpcKnowledge.new()
	knowledge.bootstrap_public("holt", _population(), _places(), [] as Array[String])
	for index: int in range(1, NpcKnowledge.MAX_FACTS + 1):
		knowledge.record_report("p%d" % index, "note", "x", "a", "o:%d" % index, "e", float(index), 0.5)
	assert_true(knowledge.record_report("overflow", "note", "x", "a", "o:overflow", "e", 5000.0, 0.5))
	assert_false(knowledge.knows("p1", "note"))
	assert_true(knowledge.knows("p2", "note"))
	assert_true(knowledge.knows("holt", "identity"))
	assert_eq(knowledge.to_data()["facts"].size(), NpcKnowledge.MAX_FACTS)

func test_json_round_trip_preserves_personal_facts_and_bootstrap_restores_public_ones() -> void:
	var knowledge := NpcKnowledge.new()
	knowledge.bootstrap_public("holt", _population(), _places(), ["guard"] as Array[String])
	knowledge.record_sighting("mara", "outdoors", Vector2(10.5, 20.25), 50.0, "ev:1")
	knowledge.record_report("mara", "location", _place("market", 1.0, 1.0), "tess", "report:1", "ev:2", 60.0, 0.6)
	knowledge.record_report("mara", "mood", {"tags": ["a", 2], "ok": true, "none": null}, "tess", "report:2", "ev:3", 61.0, 0.5)
	var encoded: String = JSON.stringify(knowledge.to_data())
	var parsed: Variant = JSON.parse_string(encoded)
	assert_true(NpcKnowledge.is_valid_data(parsed))
	var restored := NpcKnowledge.new()
	assert_true(restored.from_data(parsed))
	assert_eq(restored.to_data(), knowledge.to_data())
	assert_eq(restored.known_locations("mara"), knowledge.known_locations("mara"))
	assert_eq(restored.current("mara", "mood"), knowledge.current("mara", "mood"))
	assert_eq(restored.known_help_places().size(), 0, "public facts are not saved")
	restored.bootstrap_public("holt", _population(), _places(), ["guard"] as Array[String])
	assert_eq(restored.known_help_places().size(), knowledge.known_help_places().size())
	assert_eq(restored.known_places().size(), knowledge.known_places().size())
	assert_true(restored.knows("wren", "identity"))
	assert_true(restored.record_sighting("mara", "outdoors", Vector2(0, 0), 90.0, "ev:9"))
	assert_eq(restored.current("mara", "location")[0]["value"], _place("outdoors", 0.0, 0.0))
	assert_eq(restored.current("mara", "location").size(), 1, "the newer sighting supersedes the contested pair")

func test_to_data_never_contains_public_facts_and_ids_stay_unique_after_reload() -> void:
	var knowledge := NpcKnowledge.new()
	knowledge.bootstrap_public("holt", _population(), _places(), ["guard"] as Array[String])
	knowledge.record_sighting("mara", "outdoors", Vector2(1, 1), 5.0, "ev:1")
	var data: Dictionary = knowledge.to_data()
	assert_eq(data["facts"].size(), 1)
	for fact: Dictionary in data["facts"]:
		assert_ne(fact["source_id"], NpcKnowledge.PUBLIC_SOURCE)
	var restored := NpcKnowledge.new()
	assert_true(restored.from_data(JSON.parse_string(JSON.stringify(data))))
	restored.bootstrap_public("holt", _population(), _places(), ["guard"] as Array[String])
	restored.record_sighting("bram", "outdoors", Vector2(2, 2), 6.0, "ev:2")
	var seen: Dictionary = {}
	for subject: String in ["holt", "wren", "pip", "stranger", "guard", "mara", "bram"]:
		for predicate: String in ["identity", "family_role", "location"]:
			for fact: Dictionary in restored.current(subject, predicate):
				assert_false(seen.has(fact["id"]), "duplicate id " + fact["id"])
				seen[fact["id"]] = true
	assert_true(restored.known_places().size() > 0)
	assert_true(restored.known_help_places().size() > 0)
	assert_true(restored.from_data(restored.to_data()), "a save taken after bootstrap loads again")

func test_bootstrap_after_a_full_personal_load_does_not_evict_personal_facts() -> void:
	var source := NpcKnowledge.new()
	for index: int in NpcKnowledge.MAX_FACTS:
		assert_true(source.record_report("p%d" % index, "note", "x", "a", "o:%d" % index, "e", float(index), 0.5))
	var restored := NpcKnowledge.new()
	assert_true(restored.from_data(JSON.parse_string(JSON.stringify(source.to_data()))))
	restored.bootstrap_public("holt", _population(), _places(), ["guard"] as Array[String])
	assert_true(restored.knows("p0", "note"))
	assert_true(restored.knows("wren", "identity"))
	assert_eq(restored.to_data()["facts"].size(), NpcKnowledge.MAX_FACTS)

func test_from_data_is_atomic_and_rejects_malformed_data() -> void:
	var knowledge := NpcKnowledge.new()
	knowledge.record_sighting("mara", "outdoors", Vector2(10, 10), 50.0, "ev:1")
	var before: Dictionary = knowledge.to_data()
	var source := NpcKnowledge.new()
	source.record_sighting("a", "outdoors", Vector2(1, 1), 1.0, "e")
	source.record_sighting("b", "outdoors", Vector2(2, 2), 2.0, "e")
	var good: Dictionary = source.to_data()
	var cases: Array[Dictionary] = []
	var bad: Dictionary = good.duplicate(true)
	bad["facts"][1]["status"] = "MAYBE"
	cases.append(bad)
	bad = good.duplicate(true)
	bad["facts"][1]["id"] = "fact:1"
	cases.append(bad)
	bad = good.duplicate(true)
	bad["facts"][0]["source_confidence"] = 2.0
	cases.append(bad)
	bad = good.duplicate(true)
	bad["facts"][0]["value"] = {"space": "outdoors", "x": "left", "y": 1.0}
	cases.append(bad)
	bad = good.duplicate(true)
	bad["facts"][0]["extra"] = 1
	cases.append(bad)
	bad = good.duplicate(true)
	bad["facts"][0]["origin_ids"] = [""]
	cases.append(bad)
	bad = good.duplicate(true)
	bad["next_id"] = 2
	cases.append(bad)
	for candidate: Dictionary in cases:
		assert_false(NpcKnowledge.is_valid_data(candidate))
		assert_false(knowledge.from_data(candidate))
		assert_eq(knowledge.to_data(), before)
	assert_false(knowledge.from_data("nope"))
	assert_true(knowledge.from_data(good))
	assert_true(knowledge.knows("b", "location"))
	assert_false(knowledge.knows("mara", "location"))
