class_name NpcRelationshipState
extends RefCounted

const KEYS: Array[String] = ["familiarity", "trust", "respect", "affection", "fear", "suspicion"]

static func initial() -> Dictionary:
	return {"familiarity": 0.0, "trust": 0.0, "respect": 0.0,
		"affection": 0.0, "fear": 0.0, "suspicion": 0.0}

static func is_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != KEYS.size():
		return false
	for key: String in KEYS:
		var number: Variant = value.get(key)
		if not (number is float or number is int) or not is_finite(float(number)):
			return false
		var minimum: float = 0.0 if key in ["familiarity", "fear", "suspicion"] else -1.0
		if float(number) < minimum or float(number) > 1.0:
			return false
	return true

static func changed(current: Dictionary, delta: Dictionary) -> Dictionary:
	var result: Dictionary = current.duplicate()
	for key: String in KEYS:
		var amount: float = clampf(float(delta.get(key, 0.0)), -0.1, 0.1)
		var minimum: float = 0.0 if key in ["familiarity", "fear", "suspicion"] else -1.0
		result[key] = clampf(float(current[key]) + amount, minimum, 1.0)
	return result
