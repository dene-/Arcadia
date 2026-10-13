extends "res://tests/test_case.gd"

## Personal knowledge over the real seeded population, without a world: residents start with public
## facts only and learn positions only from first-hand sightings.

const REGION_SEED: int = 274415

func _population() -> TownPopulation:
	var town := TownPopulation.new()
	town.ensure_population(REGION_SEED)
	return town

func _places(town: TownPopulation) -> Dictionary:
	var places: Dictionary = {"square": {"label": "Rekala square", "position": Vector2(16, 48)},
		"market": {"label": "the market stalls", "position": Vector2(-48, 88)},
		"garden": {"label": "the farm garden", "position": Vector2(320, 104)},
		"school": {"label": "the school", "position": Vector2(128, 256)},
		"playground": {"label": "the play green", "position": Vector2(-104, 232)}}
	for index: int in 4:
		places["patrol:%d" % index] = {"label": "village watch route", "position": Vector2(index * 100, 32)}
	for id: String in town.people:
		var space: String = "home:" + String(town.people[id].household)
		places["home:" + id] = {"label": "home", "position": Vector2(10, 20), "space": space}
		places["work:" + id] = {"label": "work", "position": Vector2(30, 40), "space": space}
	return places

func _guards(town: TownPopulation) -> Array[String]:
	var guards: Array[String] = []
	for id: String in town.people:
		if town.people[id].job == "guard":
			guards.append(id)
	guards.sort()
	return guards

func _bootstrapped(town: TownPopulation, id: String) -> NpcKnowledge:
	var knowledge := NpcKnowledge.new()
	knowledge.bootstrap_public(id, town.people, _places(town), _guards(town))
	return knowledge

func test_every_resident_knows_guard_homes_and_patrol_points_as_help_places() -> void:
	var town: TownPopulation = _population()
	var guards: Array[String] = _guards(town)
	assert_eq(guards.size(), 2)
	for id: String in town.people:
		var places: Array[String] = []
		for fact: Dictionary in _bootstrapped(town, id).known_help_places():
			places.append(String(fact.value.place))
		places.sort()
		var expected: Array[String] = ["patrol:0", "patrol:1", "patrol:2", "patrol:3"]
		for guard_id: String in guards:
			expected.append("home:" + guard_id)
		expected.sort()
		assert_eq(places, expected, id)

func test_residents_start_with_no_location_dead_or_burial_knowledge() -> void:
	var town: TownPopulation = _population()
	for id: String in town.people:
		var knowledge: NpcKnowledge = _bootstrapped(town, id)
		for other: String in town.people:
			assert_true(knowledge.known_locations(other).is_empty(), "%s locates %s" % [id, other])
			assert_false(knowledge.knows(other, "status"), "%s knows a status of %s" % [id, other])
			assert_true(knowledge.knows(other, "identity"), "%s does not know %s" % [id, other])
		assert_false(knowledge.knows("player", "location"))

func test_family_roles_cover_only_the_residents_own_kin() -> void:
	var town: TownPopulation = _population()
	var knowledge: NpcKnowledge = _bootstrapped(town, "sella_rowan")
	for other: String in town.people:
		assert_eq(knowledge.knows(other, "family_role"), town.people.sella_rowan.kin.has(other), other)

func test_public_knowledge_stays_small_and_is_the_same_for_equal_residents_after_reload() -> void:
	var town: TownPopulation = _population()
	for id: String in town.people:
		var knowledge: NpcKnowledge = _bootstrapped(town, id)
		var data: Dictionary = knowledge.to_data()
		assert_true((data.facts as Array).size() < 100, "%s starts with %d facts" % [id, data.facts.size()])
		var restored := NpcKnowledge.new()
		assert_true(restored.from_data(JSON.parse_string(JSON.stringify(data))))
		assert_eq(restored.to_data(), data, id)

func test_a_sighting_is_the_only_way_a_resident_learns_a_position_and_survives_rebootstrap() -> void:
	var town: TownPopulation = _population()
	var knowledge: NpcKnowledge = _bootstrapped(town, "garrin_holt")
	assert_true(knowledge.record_sighting("voss_guard", "outdoors", Vector2(40, 12), 500.0, "sighting:1"))
	var locations: Array[Dictionary] = knowledge.known_locations("voss_guard")
	assert_eq(locations.size(), 1)
	assert_eq(locations[0].status, "OBSERVED")
	assert_eq(locations[0].source_id, "self")
	knowledge.bootstrap_public("garrin_holt", town.people, _places(town), _guards(town))
	assert_eq(knowledge.known_locations("voss_guard"), locations, "Re-bootstrap on load keeps sightings.")

func test_a_long_watch_keeps_one_sighting_per_subject() -> void:
	var town: TownPopulation = _population()
	var knowledge: NpcKnowledge = _bootstrapped(town, "garrin_holt")
	var baseline: int = knowledge.to_data().facts.size()
	for minute: int in 600:
		knowledge.record_sighting("voss_guard", "outdoors", Vector2(minute, 0), float(minute), "s:%d" % minute)
		knowledge.record_sighting("holt_partner", "outdoors", Vector2(0, minute), float(minute), "t:%d" % minute)
	assert_eq(knowledge.to_data().facts.size(), baseline + 2)
	assert_eq(knowledge.known_locations("voss_guard")[0].value.x, 599.0)

func test_mind_state_round_trips_bootstrapped_knowledge() -> void:
	var town: TownPopulation = _population()
	var mind := NpcMindState.new("garrin_holt")
	mind.knowledge.bootstrap_public("garrin_holt", town.people, _places(town), _guards(town))
	mind.knowledge.record_sighting("voss_guard", "outdoors", Vector2(1, 2), 10.0, "s:1")
	var restored := NpcMindState.new("garrin_holt")
	assert_true(restored.from_data(JSON.parse_string(JSON.stringify(mind.to_data()))))
	assert_eq(restored.knowledge.to_data(), mind.knowledge.to_data())
