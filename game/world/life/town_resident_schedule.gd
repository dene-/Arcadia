class_name TownResidentSchedule
extends RefCounted

## Obligations constrain Jev's choices; the model chooses among appropriate activities.
static func generate(population: TownPopulation, id: String, seed_value: int,
		day: int, places: Array[String]) -> Array[Dictionary]:
	var person: Dictionary = population.people[id]
	var plan: Array[Dictionary] = NpcRoutinePlan.generate(seed_value, id, day, places)
	var random := NpcRoutinePlan.random_for(seed_value, "%s:family-day:%d" % [person.household, day])
	# Shared meal times provide recurring opportunities to meet relatives at home.
	plan[1] = {"minute": 400 + random.randi_range(-15, 15), "kind": "meal", "place": "home:" + id}
	plan[2].minute = 460
	plan[6] = {"minute": 1130 + random.randi_range(-15, 15), "kind": "meal", "place": "home:" + id}
	if person.age < 16:
		plan[2] = {"minute": 480, "kind": "school", "place": "school"}
		plan[4] = {"minute": 800, "kind": "play", "place": "playground"}
		plan[5] = {"minute": 1000, "kind": "play", "place": "playground"}
		plan[7].minute = 1200
	elif String(person.job).begins_with("retired"):
		plan[2].kind = "walk"
		plan[2].place = "garden"
		plan[4].kind = "socialize"
		plan[4].place = "square"
	elif person.job == "guard":
		var early: bool = id == "voss_guard"
		# The late watch crosses midnight and sleeps after handing over in the morning.
		if not early:
			return [
				{"minute": 0, "kind": "patrol", "place": "patrol:2"},
				{"minute": 390, "kind": "meal", "place": "home:" + id},
				{"minute": 450, "kind": "rest", "place": "home:" + id},
				{"minute": 930, "kind": "meal", "place": "home:" + id},
				{"minute": 960, "kind": "socialize", "place": "square"},
				{"minute": 1110, "kind": "patrol", "place": "patrol:1"},
			]
		plan = [
			{"minute": 0, "kind": "rest", "place": "home:" + id},
			{"minute": 330, "kind": "meal", "place": "home:" + id},
			{"minute": 360, "kind": "patrol", "place": "patrol:0"},
			{"minute": 690, "kind": "meal", "place": "home:" + id},
			{"minute": 720, "kind": "patrol", "place": "patrol:2"},
			{"minute": 1140, "kind": "meal", "place": "home:" + id},
			{"minute": 1200, "kind": "socialize", "place": "square"},
			{"minute": 1250, "kind": "rest", "place": "home:" + id},
		]
	return plan
