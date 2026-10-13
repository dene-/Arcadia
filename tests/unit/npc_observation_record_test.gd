extends "res://tests/test_case.gd"

func _roundtrip(observation: NpcObservation) -> NpcObservation:
	return NpcObservation.from_data(JSON.parse_string(JSON.stringify(observation.to_data())))

func test_combat_noise_maps_to_noise_with_fighting_cue_only() -> void:
	var perceived: Dictionary = {"kind": "combat_noise", "sense": "hearing",
		"text": "I heard sounds of fighting nearby, but could not see what happened.",
		"player_involved": false, "directly_affected": false, "danger_possible": true,
		"topics": ["combat"], "participants": [], "origin_id": "event:1"}
	var observation: NpcObservation = NpcObservation.from_perception("vale", "event:1", 640.0,
		&"outdoors", perceived, Vector2(10.0, 20.0))
	assert_not_null(observation)
	assert_eq(observation.modality, NpcObservation.Modality.NOISE)
	assert_eq(observation.kind, &"combat_noise")
	assert_eq(observation.cues, ["sounds of fighting"] as Array[String])
	assert_eq(observation.topics, ["combat"] as Array[String])
	assert_eq(observation.observation_id, "vale:event:1")
	assert_true(observation.has_position)
	assert_eq(observation.position, Vector2(10.0, 20.0))
	assert_true(observation.participant_ids().is_empty())
	assert_false(observation.is_protected())
	assert_eq(observation.legacy_sense(), "hearing")

func test_hearing_without_kind_is_noise_without_fighting_cue() -> void:
	var observation: NpcObservation = NpcObservation.from_perception("vale", "e:2", 1.0, &"outdoors",
		{"sense": "hearing", "text": "I heard a thud."})
	assert_eq(observation.modality, NpcObservation.Modality.NOISE)
	assert_true(observation.cues.is_empty())
	assert_true(observation.topics.is_empty())
	assert_false(observation.has_position)

func test_body_report_keeps_source_and_deceased_without_fighting_cue() -> void:
	var perceived: Dictionary = {"kind": "body_reported", "sense": "hearing",
		"text": "Holt told me they found Garrin dead. The cause is unconfirmed.",
		"player_involved": false, "directly_affected": false, "danger_possible": false,
		"topics": ["death", "town"],
		"participants": [{"id": "garrin_holt", "name": "Garrin Holt", "role": "deceased",
			"relationship": "neighbor"},
			{"id": "holt_partner", "name": "Holt", "role": "reporter"}]}
	var observation: NpcObservation = NpcObservation.from_perception("vale_guard", "body:garrin_holt",
		1380.0, &"outdoors", perceived)
	assert_not_null(observation)
	assert_eq(observation.modality, NpcObservation.Modality.SPOKEN_REPORT)
	assert_eq(observation.source_id, "holt_partner")
	assert_true("garrin_holt" in observation.participant_ids())
	assert_true(observation.cues.is_empty())
	assert_true(observation.is_protected())
	assert_eq(observation.legacy_sense(), "hearing")
	var event: Dictionary = observation.to_event()
	assert_eq(event["modality"], "SPOKEN_REPORT")
	assert_eq(event["source_id"], "holt_partner")
	assert_eq(event["sense"], "hearing")
	assert_eq(event["kind"], "body_reported")
	assert_true((event["cues"] as Array).is_empty())
	assert_eq((event["participants"] as Array).size(), 2)

func test_body_report_without_reporter_participant_uses_source_id_field() -> void:
	var perceived: Dictionary = {"kind": "body_reported", "sense": "hearing",
		"text": "Someone reported a death.", "source_id": "holt_partner",
		"participants": [{"id": "garrin_holt", "name": "Garrin Holt", "role": "deceased"}]}
	var observation: NpcObservation = NpcObservation.from_perception("vale_guard", "r:1", 5.0,
		&"outdoors", perceived)
	assert_eq(observation.source_id, "holt_partner")
	var unattributed: NpcObservation = NpcObservation.from_perception("vale_guard", "r:2", 5.0,
		&"outdoors", {"kind": "body_reported", "sense": "hearing", "text": "A death was reported."})
	assert_eq(unattributed.source_id, "")

func test_touch_and_direct_affect() -> void:
	var perceived: Dictionary = {"kind": "actor_hurt", "sense": "touch",
		"text": "I was hurt by Den.", "player_involved": true, "directly_affected": true,
		"danger_possible": true, "health_remaining": 6.0, "max_health": 10,
		"topics": ["combat", "injury"],
		"participants": [{"id": "player", "name": "Den", "role": "aggressor"}]}
	var observation: NpcObservation = NpcObservation.from_perception("holt", "e:3", 30.0,
		&"home:holt", perceived)
	assert_eq(observation.modality, NpcObservation.Modality.TOUCH)
	assert_eq(observation.legacy_sense(), "touch")
	assert_true(observation.is_protected())
	assert_eq(observation.facts["health_remaining"], 6)
	var event: Dictionary = observation.to_event()
	assert_eq(event["health_remaining"], 6)
	assert_eq(event["max_health"], 10)
	assert_true(event["player_involved"])
	assert_true(event["directly_affected"])

func test_sight_with_unknown_kind_stays_unknown_and_topics_stay_empty() -> void:
	var observation: NpcObservation = NpcObservation.from_perception("holt", "e:4", 30.0,
		&"outdoors", {"sense": "sight", "text": "I saw something odd."})
	assert_eq(observation.modality, NpcObservation.Modality.SIGHT)
	assert_eq(observation.kind, &"unknown")
	assert_true(observation.topics.is_empty())
	assert_true(observation.cues.is_empty())
	assert_true(observation.participants.is_empty())
	assert_false(observation.is_protected())
	var touched: NpcObservation = NpcObservation.from_perception("holt", "e:5", 30.0,
		&"outdoors", {"sense": "touch", "text": "I was struck."})
	assert_eq(touched.kind, &"unknown")
	assert_false(touched.is_protected())

func test_conversation_kinds_map_to_direct_speech() -> void:
	var observation: NpcObservation = NpcObservation.from_perception("holt", "c:1", 30.0,
		&"outdoors", {"kind": "conversation", "sense": "hearing", "text": "Den said hello.",
		"participants": [{"id": "player", "name": "Den", "role": "speaker"}]})
	assert_eq(observation.modality, NpcObservation.Modality.DIRECT_SPEECH)
	assert_eq(observation.source_id, "player")

func test_unidentified_participants_keep_empty_id_and_are_not_listed() -> void:
	var perceived: Dictionary = {"kind": "actor_hurt", "sense": "sight",
		"text": "I saw someone hurt a stranger.",
		"participants": [{"id": "", "name": "someone", "role": "aggressor"},
			{"id": "garrin_holt", "name": "Garrin", "role": "hurt_person"},
			{"id": "garrin_holt", "name": "Garrin", "role": "hurt_person"}]}
	var observation: NpcObservation = NpcObservation.from_perception("holt", "e:6", 30.0,
		&"outdoors", perceived)
	assert_eq(observation.participants.size(), 3)
	assert_eq(observation.participants[0]["id"], "")
	assert_eq(observation.participant_ids(), ["garrin_holt"] as Array[String])
	# An unidentified aggressor does not make the evidence protected.
	assert_false(observation.is_protected())
	perceived["participants"] = [{"id": "player", "name": "Den", "role": "aggressor"}]
	assert_true(NpcObservation.from_perception("holt", "e:7", 30.0, &"outdoors", perceived).is_protected())

func test_protected_kinds() -> void:
	for kind_name: String in ["actor_died", "body_found", "body_reported", "body_buried", "commitment"]:
		var observation: NpcObservation = NpcObservation.from_perception("holt", "k:" + kind_name, 1.0,
			&"outdoors", {"kind": kind_name, "sense": "sight", "text": "Something happened."})
		assert_true(observation.is_protected(), kind_name)
	var hurt: NpcObservation = NpcObservation.from_perception("holt", "k:hurt", 1.0, &"outdoors",
		{"kind": "actor_hurt", "sense": "sight", "text": "Someone was hurt."})
	assert_false(hurt.is_protected())

func test_json_round_trip_preserves_everything() -> void:
	var perceived: Dictionary = {"kind": "body_reported", "sense": "hearing", "text": "Report.",
		"danger_possible": false, "directly_affected": false, "player_involved": false,
		"health_remaining": 3, "max_health": 9, "topics": ["death"],
		"participants": [{"id": "garrin_holt", "name": "Garrin", "role": "deceased",
			"relationship": {"label": "friend", "trust": 0.5}},
			{"id": "", "name": "someone", "role": "reporter"}]}
	var observation: NpcObservation = NpcObservation.from_perception("vale", "o:1", 12.5,
		&"home:vale", perceived, Vector2(1.5, -2.0))
	observation.incident_id = "incident:vale:1"
	var restored: NpcObservation = _roundtrip(observation)
	assert_not_null(restored)
	assert_eq(JSON.stringify(restored.to_data()), JSON.stringify(observation.to_data()))
	assert_eq(restored.position, Vector2(1.5, -2.0))
	assert_eq(restored.facts["health_remaining"], 3)
	assert_true(restored.facts["health_remaining"] is int)
	assert_eq(restored.modality, NpcObservation.Modality.SPOKEN_REPORT)
	assert_eq(restored.participants[0]["relationship"], {"label": "friend", "trust": 0.5})
	var no_position: NpcObservation = NpcObservation.from_perception("vale", "o:2", 1.0, &"x",
		{"sense": "sight", "text": "Hi."})
	assert_false(_roundtrip(no_position).has_position)

func test_copy_is_deep() -> void:
	var observation: NpcObservation = NpcObservation.from_perception("vale", "o:3", 1.0, &"x",
		{"sense": "sight", "text": "Hi.", "topics": ["a"],
		"participants": [{"id": "p", "name": "P", "role": "r"}]})
	var copied: NpcObservation = observation.copy()
	copied.participants[0]["id"] = "other"
	copied.topics.append("b")
	copied.facts["player_involved"] = true
	assert_eq(observation.participants[0]["id"], "p")
	assert_eq(observation.topics, ["a"] as Array[String])
	assert_true(observation.facts.is_empty())

func test_invalid_perception_is_rejected() -> void:
	var valid: Dictionary = {"sense": "sight", "text": "Hi."}
	assert_null(NpcObservation.from_perception("", "o", 1.0, &"x", valid))
	assert_null(NpcObservation.from_perception("vale", "", 1.0, &"x", valid))
	assert_null(NpcObservation.from_perception("vale", "o", INF, &"x", valid))
	assert_null(NpcObservation.from_perception("vale", "o", NAN, &"x", valid))
	assert_null(NpcObservation.from_perception("vale", "o", 1.0, &"x", {"sense": "sight", "text": ""}))
	assert_null(NpcObservation.from_perception("vale", "o", 1.0, &"x", {"sense": "sight"}))
	assert_null(NpcObservation.from_perception("vale", "o", 1.0, &"x",
		{"sense": "sight", "text": "x".repeat(501)}))
	assert_not_null(NpcObservation.from_perception("vale", "o", 1.0, &"x",
		{"sense": "sight", "text": "x".repeat(500)}))

func test_invalid_data_is_rejected() -> void:
	var observation: NpcObservation = NpcObservation.from_perception("vale", "o:4", 1.0, &"x",
		{"sense": "sight", "text": "Hi.", "participants": [{"id": "p", "name": "P", "role": "r"}]})
	observation.incident_id = "incident:1"
	var base: Dictionary = observation.to_data()
	assert_true(NpcObservation.is_valid_data(base))
	assert_false(NpcObservation.is_valid_data(null))
	assert_false(NpcObservation.is_valid_data([]))
	var mutations: Array[Callable] = [
		func(data: Dictionary) -> void: data.erase("facts"),
		func(data: Dictionary) -> void: data["extra"] = 1,
		func(data: Dictionary) -> void: data["modality"] = "BOGUS",
		func(data: Dictionary) -> void: data["observation_id"] = "",
		func(data: Dictionary) -> void: data["observer_id"] = "",
		func(data: Dictionary) -> void: data["origin_id"] = "",
		func(data: Dictionary) -> void: data["kind"] = "",
		func(data: Dictionary) -> void: data["text"] = "",
		func(data: Dictionary) -> void: data["text"] = "x".repeat(501),
		func(data: Dictionary) -> void: data["observed_minute"] = INF,
		func(data: Dictionary) -> void: data["observed_minute"] = "1",
		func(data: Dictionary) -> void: data["position"] = [1.0],
		func(data: Dictionary) -> void: data["position"] = [NAN, 1.0],
		func(data: Dictionary) -> void: data["origin_id"] = "x".repeat(201),
		func(data: Dictionary) -> void: data["source_id"] = "someone",
		func(data: Dictionary) -> void: data["topics"] = ["x".repeat(65)],
		func(data: Dictionary) -> void: data["topics"] = [1],
		func(data: Dictionary) -> void: data["cues"] = range(17).map(func(i: int) -> String: return str(i)),
		func(data: Dictionary) -> void: data["participants"] = [{"id": "p", "name": "P"}],
		func(data: Dictionary) -> void: data["participants"] = [{"id": 1, "name": "P", "role": "r"}],
		func(data: Dictionary) -> void: data["participants"] = range(9).map(
			func(i: int) -> Dictionary: return {"id": str(i), "name": "n", "role": "r"}),
		func(data: Dictionary) -> void: data["facts"] = {"player_involved": "yes"},
		func(data: Dictionary) -> void: data["facts"] = {"health_remaining": 1.5},
		func(data: Dictionary) -> void: data["facts"] = {"health_remaining": -1},
		func(data: Dictionary) -> void: data["facts"] = {"nested": Vector2.ZERO},
		func(data: Dictionary) -> void: data["facts"] = []]
	for index: int in mutations.size():
		var mutated: Dictionary = base.duplicate(true)
		mutations[index].call(mutated)
		assert_false(NpcObservation.is_valid_data(mutated), "mutation %d accepted" % index)
		assert_null(NpcObservation.from_data(mutated), "mutation %d produced a record" % index)

func test_integral_floats_are_accepted_for_counts() -> void:
	var observation: NpcObservation = NpcObservation.from_perception("vale", "o:5", 1.0, &"x",
		{"sense": "touch", "text": "Hi.", "health_remaining": 4, "max_health": 10})
	var data: Dictionary = observation.to_data()
	data["facts"] = {"health_remaining": 4.0, "max_health": 10.0}
	var restored: NpcObservation = NpcObservation.from_data(data)
	assert_not_null(restored)
	assert_true(restored.facts["max_health"] is int)
