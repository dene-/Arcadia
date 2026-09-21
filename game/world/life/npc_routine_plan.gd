class_name NpcRoutinePlan
extends RefCounted

## Daily preferences are reproducible from world, person and day; actual choices remain contextual.
const MINUTES_PER_DAY: int = 1440
const REVISION: int = 3

static func random_for(world_seed: int, key: String) -> RandomNumberGenerator:
	var random := RandomNumberGenerator.new()
	random.seed = hash("%d:%s" % [world_seed, key])
	return random

static func generate(world_seed: int, id: String, day: int, places: Array[String]) -> Array[Dictionary]:
	var random := random_for(world_seed, "%s:day:%d" % [id, day])
	var leisure: Array[String] = places.duplicate()
	leisure.sort()
	var breakfast: int = 390 + random.randi_range(-35, 35)
	var lunch: int = 710 + random.randi_range(-45, 45)
	var morning_place: String = "market" if random.randf() < 0.35 else "home:" + id
	var lunch_place: String = "market" if random.randf() < 0.5 else "home:" + id
	var evening_place: String = leisure[random.randi_range(0, leisure.size() - 1)] \
		if not leisure.is_empty() else "square"
	var plan: Array[Dictionary] = [
		{"minute": 0, "kind": "rest", "place": "home:" + id},
		{"minute": breakfast, "kind": "meal", "place": morning_place},
		{"minute": breakfast + random.randi_range(25, 45), "kind": "work", "place": "work:" + id},
		{"minute": lunch, "kind": "meal", "place": lunch_place},
		{"minute": lunch + random.randi_range(25, 45), "kind": "work", "place": "work:" + id},
		{"minute": 1000 + random.randi_range(-35, 35), "kind": "visit",
			"place": leisure[random.randi_range(0, leisure.size() - 1)] if not leisure.is_empty() else "square"},
		{"minute": 1140 + random.randi_range(-45, 45), "kind": "socialize", "place": evening_place},
		{"minute": 1290 + random.randi_range(-40, 40), "kind": "rest", "place": "home:" + id},
	]
	return plan

static func current(plan: Array, minute: float) -> Dictionary:
	var result: Dictionary = plan[0]
	var within_day: float = fmod(minute, MINUTES_PER_DAY)
	for slot: Dictionary in plan:
		if float(slot.minute) > within_day:
			break
		result = slot
	return result.duplicate(true)

static func next_change(plan: Array, minute: float) -> float:
	var day_start: float = floorf(minute / MINUTES_PER_DAY) * MINUTES_PER_DAY
	for slot: Dictionary in plan:
		if day_start + float(slot.minute) > minute:
			return day_start + float(slot.minute)
	return day_start + MINUTES_PER_DAY
