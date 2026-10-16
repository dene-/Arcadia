class_name TownResidentSchedule
extends RefCounted

## Watch shifts in assignment order. Each row is `[minute, kind, place]`; "home" expands to the
## guard's home. `origin` is the patrol stop the shift's route cycles on from.
## The first living guard keeps the night watch, so one survivor still patrols after dark.
const GUARD_SHIFTS: Array[Dictionary] = [
	# The late watch crosses midnight and sleeps after handing over in the morning.
	{"name": "night", "origin": 2, "plan": [[0, "patrol", "patrol:2"], [390, "meal", "home"],
		[450, "rest", "home"], [930, "meal", "home"], [960, "socialize", "square"],
		[1110, "patrol", "patrol:1"]]},
	{"name": "day", "origin": 0, "plan": [[0, "rest", "home"], [330, "meal", "home"],
		[360, "patrol", "patrol:0"], [690, "meal", "home"], [720, "patrol", "patrol:2"],
		[1140, "meal", "home"], [1200, "socialize", "square"], [1250, "rest", "home"]]},
]

## Deterministic shift assignment by role: the guard's index among living guards (sorted ids).
static func guard_shift(population: TownPopulation, id: String, dead: Array[String]) -> Dictionary:
	var living: Array[String] = []
	for other: String in population.people:
		if population.people[other].job == "guard" and not other in dead:
			living.append(other)
	living.sort()
	return GUARD_SHIFTS[maxi(living.find(id), 0) % GUARD_SHIFTS.size()]

## Obligations constrain Jev's choices; the model chooses among appropriate activities.
static func generate(population: TownPopulation, id: String, seed_value: int,
		day: int, places: Array[String], dead: Array[String] = []) -> Array[Dictionary]:
	var person: Dictionary = population.people[id]
	var plan: Array[Dictionary] = NpcRoutinePlan.generate(seed_value, id, day, places)
	var random := NpcRoutinePlan.random_for(seed_value, "%s:family-day:%d" % [person.household, day])
	var personal := NpcRoutinePlan.random_for(seed_value, "%s:fixed-times:%d" % [id, day])
	# Shared meal times provide recurring opportunities to meet relatives at home.
	plan[1] = {"minute": 400 + random.randi_range(-15, 15), "kind": "meal", "place": "home:" + id}
	# Fixed obligations still start a few minutes apart, so no one leaves the door in lockstep.
	plan[2].minute = 460 + personal.randi_range(-12, 14)
	plan[6] = {"minute": 1130 + random.randi_range(-15, 15), "kind": "meal", "place": "home:" + id}
	if person.age < 16:
		plan[2] = {"minute": 480 + personal.randi_range(-6, 6), "kind": "school", "place": "school"}
		plan[4] = {"minute": 800 + personal.randi_range(-10, 10), "kind": "play", "place": "playground"}
		plan[5] = {"minute": 1000 + personal.randi_range(-10, 10), "kind": "play", "place": "playground"}
		plan[7].minute = 1200 + personal.randi_range(-12, 12)
	elif String(person.job).begins_with("retired"):
		plan[2].kind = "walk"
		plan[2].place = "garden"
		plan[4].kind = "socialize"
		plan[4].place = "square"
	elif person.job == "guard":
		plan = []
		for slot: Array in guard_shift(population, id, dead).plan:
			plan.append({"minute": slot[0], "kind": slot[1],
				"place": "home:" + id if slot[2] == "home" else slot[2]})
	return plan
