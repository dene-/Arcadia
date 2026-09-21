class_name NpcMemory
extends RefCounted

## Explicit JSON-compatible memory contract shared by authored and runtime records.
const TYPES: Array[String] = ["episodic", "semantic", "social", "prospective"]
const SOURCES: Array[String] = ["authored", "player_claim", "npc_statement", "observed_event", "hearsay"]
const TEXT_LISTS: Array[String] = ["topics", "people", "places", "sensory_cues",
	"important_details", "weak_details", "known_gaps"]
const UNIT_FIELDS: Array[String] = ["importance", "emotional_intensity", "vividness", "confidence"]

static func create(id: String, type: String, gist: String, source: String,
		turn: int) -> Dictionary:
	var memory: Dictionary = {
		"id": id, "type": type, "gist": gist, "source": source,
		"created_turn": turn, "last_recalled_turn": -1, "recall_count": 0,
		"importance": 0.5, "emotional_intensity": 0.0, "vividness": 0.5,
		"confidence": 0.5, "completed": false,
	}
	for key: String in TEXT_LISTS:
		memory[key] = []
	return memory

static func is_unit(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) \
		and float(value) >= 0.0 and float(value) <= 1.0

static func is_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) == floorf(float(value))

static func is_text_list(value: Variant, limit: int = 8) -> bool:
	if not value is Array or value.size() > limit:
		return false
	for item: Variant in value:
		if not item is String or item.length() > 200:
			return false
	return true

static func is_valid(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key: String in ["id", "type", "gist", "source"]:
		if not value.get(key) is String or value[key].is_empty() or value[key].length() > 500:
			return false
	if not value.type in TYPES or not value.source in SOURCES:
		return false
	for key: String in UNIT_FIELDS:
		if not is_unit(value.get(key)):
			return false
	for key: String in TEXT_LISTS:
		if not is_text_list(value.get(key)):
			return false
	for key: String in ["created_turn", "last_recalled_turn", "recall_count"]:
		if not is_integer(value.get(key)):
			return false
	return value.recall_count >= 0 and value.get("completed") is bool
