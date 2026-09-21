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
		plan = [
			{"minute": 0, "kind": "rest", "place": "home:" + id},
			{"minute": 330 if early else 450, "kind": "meal", "place": "home:" + id},
			{"minute": 360 if early else 500, "kind": "patrol" if early else "socialize", "place": "patrol:0" if early else "square"},
			{"minute": 660 if early else 790, "kind": "meal", "place": "home:" + id},
			{"minute": 690 if early else 840, "kind": "patrol", "place": "patrol:2"},
			{"minute": 840 if early else 1140, "kind": "visit" if early else "meal", "place": "square" if early else "home:" + id},
			{"minute": 1130 if early else 1170, "kind": "meal" if early else "patrol", "place": "home:" + id if early else "patrol:1"},
			{"minute": 1250 if early else 1320, "kind": "rest", "place": "home:" + id},
		]
	return plan
