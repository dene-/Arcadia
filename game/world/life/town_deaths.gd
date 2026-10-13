class_name TownDeaths
extends RefCounted

## Saved physical remains and recovery progress. No culprit is inferred from a body.
const STAGES: Array[String] = ["fallen", "discovered", "reported", "recovering", "carried", "buried"]
var records: Dictionary = {}

func record(id: String, space: String, position: Vector2, minute: float) -> void:
	if records.has(id):
		return
	records[id] = {"space": space, "position": [position.x, position.y], "stage": "fallen",
		"since": minute, "reporter": "", "guard": "", "known_by": [], "burial_known_by": []}

func transition(id: String, stage: String, minute: float) -> void:
	assert(stage in STAGES)
	records[id].stage = stage
	records[id].since = minute

func to_data() -> Dictionary:
	return {"version": 1, "records": records.duplicate(true)}

func from_data(data: Variant) -> bool:
	if not data is Dictionary or data.size() != 2 or not NpcMemory.is_integer(data.get("version")) \
		or int(data.version) != 1:
		return false
	var saved: Variant = data.get("records")
	if not saved is Dictionary or saved.size() > 512:
		return false
	for id: Variant in saved:
		if not id is String or id.is_empty() or id.length() > 100:
			return false
		var entry: Variant = saved[id]
		if not entry is Dictionary or not entry.get("stage") in STAGES:
			return false
		for key: String in ["space", "reporter", "guard"]:
			if not entry.get(key) is String or entry[key].length() > 200:
				return false
		if entry.space.is_empty() or not _number(entry.get("since")) or entry.since < 0:
			return false
		if not entry.get("position") is Array or entry.position.size() != 2:
			return false
		for value: Variant in entry.position:
			if not _number(value):
				return false
		for key: String in ["known_by", "burial_known_by"]:
			if not NpcMemory.is_text_list(entry.get(key), 512):
				return false
	records = saved.duplicate(true)
	return true

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
