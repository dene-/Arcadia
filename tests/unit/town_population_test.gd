extends "res://tests/test_case.gd"

func test_population_is_seeded_and_families_are_reciprocal() -> void:
	var town := TownPopulation.new()
	town.ensure_population(274415)
	assert_eq(town.people.size(), 33)
	var homes: Dictionary = {}
	var names: Dictionary = {}
	var children: int = 0
	var guards: int = 0
	for id: String in town.people:
		var person: Dictionary = town.people[id]
		homes[person.household] = true
		assert_false(names.has(person.name))
		names[person.name] = true
		children += int(person.age < 16)
		guards += int(person.job == "guard")
		for relative: String in person.kin:
			assert_true(town.people[relative].kin.has(id))
		assert_eq(String(town.profile_for(id).npc_id), id)
	assert_eq(homes.size(), 12)
	assert_eq(children, 5)
	assert_eq(guards, 2)
	assert_eq(town.members_of("mirelle_voss").size(), 1, "A widow living alone stays alone.")
	assert_eq(town.people.mirelle_voss.kin.voss_nephew, "nephew")
	assert_eq(town.people.sella_rowan.kin.size(), 6)
	var same := TownPopulation.new()
	same.ensure_population(274415)
	assert_eq(town.to_data(), same.to_data())
	var different := TownPopulation.new()
	different.ensure_population(17)
	assert_ne(town.to_data(), different.to_data())

func test_migrated_v1_save_without_population_expands_without_erasing_history_or_old_ties() -> void:
	var save := NpcWorldSave.new()
	save.life.ensure_person("mirelle_voss", 123, ["mirelle_voss", "cassian_vale"], ["square"])
	var seeded: Dictionary = save.minds.get_mind("mirelle_voss").relationships.get_relationship("cassian_vale")
	var old_tie: Dictionary = {"familiarity": seeded.familiarity, "trust": seeded.trust,
		"affection": seeded.affection}
	# A v1 world from before population, economy and justice existed: ties lived on the person.
	var life: Dictionary = save.life.to_data()
	life.people.mirelle_voss.ties = {"cassian_vale": old_tie}
	var old: Dictionary = {"version": 1,
		"world": {"dead_npcs": ["garrin_holt"], "region_seed": 123,
			"life": {"version": 1, "minute": life.minute, "next_event": life.next_event,
				"people": life.people, "rumors": life.rumors.known, "personalities": life.personalities}},
		"memory": {"version": 1, "turn": 0, "world_minute": 480.0, "next_memory_id": 1, "npcs": {}}}
	var upgraded: Dictionary = NpcSaveMigration.upgrade(old)
	assert_true(upgraded.ok)
	save = NpcWorldSave.new()
	assert_true(save.from_data(upgraded.data))
	assert_true(save.population.people.is_empty())
	save.population.ensure_population(save.region_seed)
	var ids: Array[String] = []
	ids.assign(save.population.people.keys())
	save.life.ensure_person("mirelle_voss", 123, ids, ["square"], save.population)
	assert_true(save.is_dead(&"garrin_holt"))
	var graph: NpcRelationshipGraph = save.minds.get_mind("mirelle_voss").relationships
	var tie: Dictionary = graph.get_relationship("cassian_vale")
	assert_eq({"familiarity": tie.familiarity, "trust": tie.trust, "affection": tie.affection}, old_tie)
	assert_eq(graph.subjects().size(), 32)
	assert_eq(graph.get_relationship("voss_nephew").familiarity, 1.0)
	var restored := NpcWorldSave.new()
	assert_true(restored.from_data(save.to_data()))
	assert_eq(restored.population.to_data(), save.population.to_data())
	var invalid: Dictionary = save.to_data()
	invalid.world.population.people.voss_child.kin.unknown = "parent"
	assert_false(restored.from_data(invalid))
	assert_true(restored.is_dead(&"garrin_holt"))

func test_children_have_school_and_play_and_guards_have_off_duty_time() -> void:
	var town := TownPopulation.new()
	town.ensure_population(99)
	for id: String in town.people:
		var plan: Array[Dictionary] = TownResidentSchedule.generate(town, id, 99, 0, ["square"])
		var previous: int = -1
		for slot: Dictionary in plan:
			assert_true(slot.minute > previous)
			previous = slot.minute
		if town.people[id].age < 16:
			assert_eq(NpcRoutinePlan.current(plan, 600).kind, "school")
			assert_eq(NpcRoutinePlan.current(plan, 900).kind, "play")
			assert_eq(NpcRoutinePlan.current(plan, 1300).kind, "rest")
	var early: Array[Dictionary] = TownResidentSchedule.generate(town, "voss_guard", 99, 0, ["square"])
	var late: Array[Dictionary] = TownResidentSchedule.generate(town, "vale_guard", 99, 0, ["square"])
	assert_eq(NpcRoutinePlan.current(early, 600).kind, "patrol")
	assert_eq(NpcRoutinePlan.current(late, 600).kind, "rest")
	assert_eq(NpcRoutinePlan.current(late, 1200).kind, "patrol")
	assert_eq(NpcRoutinePlan.current(early, 1300).kind, "rest")
	var dead_night: Array[String] = ["vale_guard"]
	var survivor: Array[Dictionary] = TownResidentSchedule.generate(town, "voss_guard", 99, 0, ["square"], dead_night)
	assert_eq(NpcRoutinePlan.current(survivor, 1200).kind, "patrol", "The survivor takes the night watch")
	assert_eq(NpcRoutinePlan.current(survivor, 600).kind, "rest")
	assert_eq(TownResidentSchedule.guard_shift(town, "vale_guard", []).name, "night")
	assert_eq(TownResidentSchedule.guard_shift(town, "voss_guard", []).name, "day")
	assert_eq(TownResidentSchedule.guard_shift(town, "voss_guard", dead_night).name, "night")

func test_households_have_distinct_reachable_bed_anchors() -> void:
	var town := TownPopulation.new()
	town.ensure_population(99)
	for home: Dictionary in RegionLayout.HOMES:
		var household: String = TownPopulation.FOUNDERS.get(home.job, home.job)
		var members: Array[String] = town.members_of(household)
		var layout: Dictionary = TownInteriorLayout.create(home.job, 99, household, members)
		var beds: Array = layout.props.filter(func(prop: Dictionary) -> bool: return prop.kind == "bed")
		assert_eq(beds.size(), members.size())
		assert_eq(layout.beds.size(), members.size(), home.job)
		assert_eq(layout.meals.size(), members.size(), home.job)
		for first: Dictionary in beds:
			for second: Dictionary in beds:
				if first != second:
					assert_true(first.foot.distance_to(second.foot) >= 24)

func test_every_interior_plan_is_distinct_and_geometrically_sound() -> void:
	var town := TownPopulation.new()
	town.ensure_population(99)
	var shapes: Dictionary = {}
	var styles: Dictionary = {}
	var floors: Dictionary = {}
	var jobs: Array[String] = []
	for home: Dictionary in RegionLayout.HOMES:
		jobs.append(home.job)
	for building: Dictionary in RegionLayout.PUBLIC_BUILDINGS:
		jobs.append(building.id)
	for job: String in jobs:
		var household: String = TownPopulation.FOUNDERS.get(job, job)
		var layout: Dictionary = TownInteriorLayout.create(job, 99, household, town.members_of(household))
		var problems: Array[String] = TownInteriorLayout.validate(layout)
		assert_true(problems.is_empty(), "%s: %s" % [job, problems])
		assert_false(layout.partitions.is_empty(), job + " has a separate room or alcove")
		var furniture: Array = layout.props.map(func(prop: Dictionary) -> String: return prop.kind)
		furniture.sort()
		shapes[str(layout.floor) + str(layout.partitions) + str(furniture)] = job
		styles[layout.wall] = true
		for zone: Array in layout.floors:
			floors[zone[1]] = true
	assert_eq(shapes.size(), jobs.size(), "Every room has its own shape and furniture")
	assert_eq(styles.size(), 2)
	assert_true(floors.size() >= 2)
	var school: Dictionary = TownInteriorLayout.create("school", 99, "school")
	assert_true(school.seats.pupils.size() >= 8)
	assert_true(school.spots.has("teacher"))
	var inn: Dictionary = TownInteriorLayout.create("cooker", 99, "sella_rowan", ["sella_rowan"])
	assert_true(inn.seats.tavern.size() >= 8)
	assert_true(inn.spots.has("tavern"))

func test_economy_conserves_coins_and_never_pays_twice_or_pays_children() -> void:
	var population := TownPopulation.new()
	population.ensure_population(1)
	var economy := TownEconomy.new()
	economy.ensure_households(population, 480)
	var total: int = economy.treasury
	for coins: int in economy.accounts.values():
		total += coins
	economy.record_work("rowan_father", 480)
	economy.record_work("voss_guard", 480)
	economy.record_work("holt_child_a", 600)
	economy.record_work("garrin_holt", 480)
	economy.settle(1440, population, ["garrin_holt"])
	var next_total: int = economy.treasury
	for coins: int in economy.accounts.values():
		next_total += coins
		assert_true(coins >= 0)
	assert_eq(total, next_total)
	assert_true(economy.stock.grain > 40)
	assert_eq(economy.stock.tools, 40, "Dead residents cannot produce.")
	assert_false(economy.ledger.any(func(entry: Dictionary) -> bool:
		return entry.household == "garrin_holt" and entry.kind == "income"))
	var restored := TownEconomy.new()
	assert_true(restored.from_data(economy.to_data()))
	restored.settle(1440, population, [])
	assert_eq(restored.to_data(), economy.to_data())
	restored.stock.food = 0
	restored.settle(2880, population, [])
	assert_eq(restored.shortages.size(), 12)
	assert_eq(restored.stock.food, 0)
	var corrupt: Dictionary = restored.to_data()
	corrupt.accounts.mirelle_voss = -1
	assert_false(restored.from_data(corrupt))

func test_enforcement_warning_combat_surrender_and_expiry_survive_reload() -> void:
	var justice := TownJustice.new()
	assert_eq(justice.notice("guard", "player", "brandishing", 480).status, "warning")
	assert_eq(justice.notice("guard", "player", "assault", 481).status, "warning")
	assert_eq(justice.notice("guard", "player", "assault", 482).status, "combat")
	assert_true(justice.current("other_guard", "player", 482).is_empty())
	var restored := TownJustice.new()
	assert_true(restored.from_data(justice.to_data()))
	assert_eq(restored.current("guard", "player", 482).status, "combat")
	assert_true(restored.surrender("guard", "player", 483))
	assert_true(restored.current("guard", "player", 484).is_empty())
	assert_eq(restored.known_to("guard")[0].status, "surrendered")
	assert_eq(restored.notice("guard", "player", "assault", 484).status, "combat", "Breaking surrender preserves witnessed violence.")
	assert_eq(restored.notice("guard", "player", "killing", 485).status, "combat")
	assert_true(restored.current("guard", "player", 520).is_empty())
