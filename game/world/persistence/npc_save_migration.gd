class_name NpcSaveMigration
extends RefCounted

## Pure conversion of older NPC saves into the current v2 world root. Never reads or writes files.
const REVISION: int = 1
const SOURCE_NEW_WORLD: int = 0
const SOURCE_WORLD_V1: int = 1
const SOURCE_MEMORY_ONLY: int = 100
const _MEMORY_STATE_KEYS: Array[String] = ["recent_dialogue", "memories", "recent_events",
	"observations", "next_observation_id", "heard_origins"]
const _OTHER_DIMENSIONS: Array[String] = ["respect", "fear", "suspicion"]

## Returns {"ok", "data", "error"}; data is a validated current-revision v2 root, or {} on failure.
static func upgrade(source: Dictionary) -> Dictionary:
	var version: Variant = source.get("version")
	var candidate: Dictionary = {}
	if _is_int(version, 2):
		var migration: Variant = source.get("migration")
		if not migration is Dictionary or not NpcMemory.is_integer(migration.get("revision")):
			return _failure("invalid_source")
		var revision: int = int(migration.revision)
		if revision > REVISION:
			return _failure("future_revision")
		# Revision 1 is the first v2 shape; later milestones add their steps below it.
		if revision != REVISION:
			return _failure("invalid_source")
		candidate = source.duplicate(true)
	elif _is_int(version, 1) and source.has("world"):
		candidate = _from_world_v1(source.duplicate(true), SOURCE_WORLD_V1)
	elif _is_int(version, 1) and source.has("npcs"):
		candidate = _from_memory_only(source.duplicate(true))
	else:
		return _failure("unsupported_version")
	if candidate.is_empty():
		return _failure("invalid_source")
	if not NpcWorldSave.new().from_data(candidate):
		return _failure("invalid_candidate")
	return {"ok": true, "data": candidate, "error": ""}

## Identifies the exact source file text a migrated save came from.
static func digest(text: String) -> String:
	return text.sha256_text()

static func _failure(code: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": code}

static func _is_int(value: Variant, expected: int) -> bool:
	return NpcMemory.is_integer(value) and int(value) == expected

static func _integer_or_raw(value: Variant) -> Variant:
	return int(value) if NpcMemory.is_integer(value) else value

# The legacy memory-only file is a world with no world facts and its clock at world_minute.
static func _from_memory_only(memory: Dictionary) -> Dictionary:
	var life: Dictionary = _empty_life_v1()
	life.minute = memory.get("world_minute", 480.0)
	return _from_world_v1({"version": 1, "world": {"dead_npcs": [], "life": life}, "memory": memory},
		SOURCE_MEMORY_ONLY)

static func _empty_life_v1() -> Dictionary:
	return {"version": 1, "minute": 480.0, "next_event": 1, "people": {}, "rumors": {},
		"personalities": {}}

static func _from_world_v1(source: Dictionary, source_version: int) -> Dictionary:
	var world: Variant = source.get("world")
	var memory: Variant = source.get("memory")
	if not world is Dictionary or not memory is Dictionary or not _is_int(memory.get("version"), 1):
		return {}
	var life: Variant = world.get("life", _empty_life_v1())
	if not life is Dictionary or not _is_int(life.get("version"), 1) or not life.get("people") is Dictionary \
			or not memory.get("npcs") is Dictionary:
		return {}
	var subjects: Dictionary = {}
	var people: Dictionary = {}
	for id: Variant in life.people:
		var person: Variant = life.people[id]
		if not id is String or (id as String).is_empty() or not person is Dictionary \
				or not person.get("ties") is Dictionary:
			return {}
		for other: Variant in person.ties:
			var tie: Variant = person.ties[other]
			if not other is String or (other as String).is_empty() or not tie is Dictionary:
				return {}
			var relationship: Dictionary = (tie as Dictionary).duplicate()
			for dimension: String in _OTHER_DIMENSIONS:
				if not relationship.has(dimension):
					relationship[dimension] = 0.0
			_subjects_of(subjects, id)[other] = relationship
		var converted: Dictionary = person
		converted.erase("ties")
		if not converted.has("safety"):
			converted.safety = {}
		people[id] = converted
	var states: Dictionary = {}
	for id: Variant in memory.npcs:
		var state: Variant = memory.npcs[id]
		if not id is String or (id as String).is_empty() or not state is Dictionary:
			return {}
		for key: Variant in state:
			if key != "relationship" and not key in _MEMORY_STATE_KEYS:
				return {}
		if state.has("relationship"):
			_subjects_of(subjects, id)["player"] = state.relationship
		states[id] = {"recent_dialogue": state.get("recent_dialogue"), "memories": state.get("memories"),
			"recent_events": state.get("recent_events"), "observations": state.get("observations", []),
			"next_observation_id": state.get("next_observation_id", 1),
			"heard_origins": state.get("heard_origins", {})}
	return {"version": 2,
		"migration": {"source_version": source_version, "source_digest": "", "revision": REVISION},
		"world": {"dead_npcs": world.get("dead_npcs"),
			"region_seed": _integer_or_raw(world.get("region_seed", 0)),
			"npc_seed": _integer_or_raw(world.get("npc_seed", 0)),
			"life": {"version": 2, "minute": life.get("minute"), "next_event": life.get("next_event"),
				"next_social_receipt": 1, "people": people,
				"rumors": {"version": 1, "known": life.get("rumors")},
				"personalities": life.get("personalities", {})},
			"population": world.get("population", TownPopulation.new().to_data()),
			"economy": world.get("economy", TownEconomy.new().to_data()),
			"justice": world.get("justice", TownJustice.new().to_data()),
			"deaths": {"version": 1, "records": world.get("deaths", {})}},
		"minds": {"version": 1, "minds": _minds(subjects)},
		"memory": {"version": 2, "turn": memory.get("turn"),
			"world_minute": memory.get("world_minute", 480.0),
			"next_memory_id": memory.get("next_memory_id"), "npcs": states}}

static func _subjects_of(subjects: Dictionary, id: String) -> Dictionary:
	if not subjects.has(id):
		subjects[id] = {}
	return subjects[id]

# Relationships are the only legacy mental state; every other mind section starts neutral.
static func _minds(subjects: Dictionary) -> Dictionary:
	var ids: Array = subjects.keys()
	ids.sort()
	var minds: Dictionary = {}
	for id: String in ids:
		minds[id] = {"version": 1, "relationships": {"subjects": subjects[id], "receipts": []},
			"commitments": {"next_id": 1, "items": []}, "condition": {}, "knowledge": {}, "task": {},
			"decision_sequence": 0}
	return minds
