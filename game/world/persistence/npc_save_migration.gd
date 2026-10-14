class_name NpcSaveMigration
extends RefCounted

## Pure conversion of older NPC saves into the current v2 world root. Never reads or writes files.
## Revision 1 is the first v2 shape; revision 2 adds per-mind knowledge and the evidence inbox;
## revision 3 adds session fields to dialogue and social history.
const REVISION: int = 3
const FIRST_REVISION: int = 1
const SOURCE_NEW_WORLD: int = 0
const SOURCE_WORLD_V1: int = 1
const SOURCE_MEMORY_ONLY: int = 100
const _MEMORY_STATE_KEYS: Array[String] = ["recent_dialogue", "memories", "recent_events",
	"observations", "next_observation_id", "heard_origins"]
const _OTHER_DIMENSIONS: Array[String] = ["respect", "fear", "suspicion"]
const _LEGACY_UNAVAILABLE: String = "legacy_unavailable"
## Session id of history entries written before sessions existed.
const LEGACY_SESSION: String = "legacy"

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
		if revision < FIRST_REVISION:
			return _failure("invalid_source")
		candidate = source.duplicate(true)
		if revision == 1:
			candidate = _to_revision_2(candidate)
		if revision <= 2:
			candidate = _to_revision_3(candidate)
	elif _is_int(version, 1) and source.has("world"):
		candidate = _to_revision_3(_to_revision_2(
			_from_world_v1(source.duplicate(true), SOURCE_WORLD_V1)))
	elif _is_int(version, 1) and source.has("npcs"):
		candidate = _to_revision_3(_to_revision_2(_from_memory_only(source.duplicate(true))))
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
		"migration": {"source_version": source_version, "source_digest": "", "revision": FIRST_REVISION},
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

# Revision 1 -> 2: every mind gains knowledge and an evidence inbox. Unappraised display entries
# become inbox evidence, and fighting cues that only a misclassified report added are removed.
# Returns {} when the root is not a revision-1 shape.
static func _to_revision_2(root: Dictionary) -> Dictionary:
	var migration: Variant = root.get("migration")
	var mind_root: Variant = root.get("minds")
	var memory: Variant = root.get("memory")
	if not migration is Dictionary or not mind_root is Dictionary \
			or not (mind_root as Dictionary).get("minds") is Dictionary \
			or not memory is Dictionary or not (memory as Dictionary).get("npcs") is Dictionary:
		return {}
	var minds: Dictionary = (mind_root as Dictionary)["minds"]
	var states: Dictionary = (memory as Dictionary)["npcs"]
	var clock: Variant = (memory as Dictionary).get("world_minute", 480.0)
	var people: Variant = {}
	var world: Variant = root.get("world")
	if world is Dictionary and (world as Dictionary).get("life") is Dictionary:
		people = ((world as Dictionary)["life"] as Dictionary).get("people", {})
	var inboxes: Dictionary = {}
	var ids: Array = states.keys()
	ids.sort()
	for id: Variant in ids:
		var state: Variant = states[id]
		if not id is String or not state is Dictionary or not (state as Dictionary).get("observations") is Array:
			return {}
		var inbox: Variant = _evidence_from_display(id, state, clock, people)
		if inbox == null:
			return {}
		inboxes[id] = inbox
		_remove_misattributed_fighting_cue(state)
	for id: Variant in minds:
		if not minds[id] is Dictionary:
			return {}
	for id: Variant in ids:
		if not minds.has(id) and not (inboxes[id] as Dictionary).items.is_empty():
			minds[id] = NpcMindState.new(id).to_data()
	for id: Variant in minds:
		var mind: Dictionary = minds[id]
		mind["version"] = NpcMindState.SCHEMA_VERSION
		mind["knowledge"] = NpcKnowledge.new().to_data()
		mind["evidence"] = inboxes.get(id, NpcEvidenceInbox.new().to_data())
	(migration as Dictionary)["revision"] = 2
	return root

# Revision 2 -> 3: legacy dialogue and social history entries belong to the "legacy" session.
# Dialogue had no time (minute -1); social entries keep their minute and gain both participants
# from the owner and its "with". Every legacy line was delivered. Returns {} for invalid roots.
static func _to_revision_3(root: Dictionary) -> Dictionary:
	if root.is_empty():
		return {}
	var migration: Variant = root.get("migration")
	var memory: Variant = root.get("memory")
	var world: Variant = root.get("world")
	if not migration is Dictionary or not memory is Dictionary \
			or not (memory as Dictionary).get("npcs") is Dictionary or not world is Dictionary \
			or not (world as Dictionary).get("life") is Dictionary \
			or not ((world as Dictionary)["life"] as Dictionary).get("people") is Dictionary:
		return {}
	for state: Variant in ((memory as Dictionary)["npcs"] as Dictionary).values():
		if not state is Dictionary or not (state as Dictionary).get("recent_dialogue") is Array:
			return {}
		for entry: Variant in (state as Dictionary)["recent_dialogue"]:
			if not entry is Dictionary:
				return {}
			(entry as Dictionary).merge({"session_id": LEGACY_SESSION, "minute": -1.0,
				"delivered": true})
	var people: Dictionary = ((world as Dictionary)["life"] as Dictionary)["people"]
	for id: Variant in people:
		var person: Variant = people[id]
		if not person is Dictionary or not (person as Dictionary).get("recent_social") is Array:
			return {}
		for entry: Variant in (person as Dictionary)["recent_social"]:
			if not entry is Dictionary:
				return {}
			var other: Variant = (entry as Dictionary).get("with", "")
			(entry as Dictionary).merge({"session_id": LEGACY_SESSION, "speaker_id": id,
				"listener_id": other, "delivered": true})
	(migration as Dictionary)["revision"] = REVISION
	return root

# Returns the inbox data for one resident and rewrites its pending/unavailable display entries
# to reference their evidence; null when an entry cannot be turned into valid evidence.
static func _evidence_from_display(id: String, state: Dictionary, clock: Variant,
		people: Variant) -> Variant:
	var inbox := NpcEvidenceInbox.new()
	var space: StringName = _saved_space(people, id)
	var unavailable: Array[String] = []
	for entry: Variant in state["observations"]:
		if not entry is Dictionary:
			return null
		var status: Variant = entry.get("status")
		if status != "pending" and status != "unavailable":
			continue
		var origin: Variant = entry.get("origin_id")
		if not origin is String or (origin as String).is_empty():
			origin = "legacy:%s:%d" % [id, int(entry.get("id", 0))]
		var minute: Variant = entry.get("world_minute", clock)
		if not (minute is float or minute is int):
			return null
		var observation: NpcObservation = NpcObservation.from_perception(id, origin, float(minute), space, entry)
		if observation == null:
			return null
		inbox.enqueue(observation)
		entry["observation_id"] = observation.observation_id
		entry["status"] = "pending"
		if status == "unavailable":
			unavailable.append(observation.observation_id)
	var data: Dictionary = inbox.to_data()
	for item: Dictionary in data["items"]:
		if item["observation"]["observation_id"] in unavailable:
			item["status"] = "DEFERRED"
			item["attempts"] = 1
			item["retry_after"] = 0.0
			item["last_error"] = _LEGACY_UNAVAILABLE
	return data

static func _saved_space(people: Variant, id: String) -> StringName:
	var person: Variant = (people as Dictionary).get(id) if people is Dictionary else null
	var space: Variant = (person as Dictionary).get("space") if person is Dictionary else null
	return StringName(space as String) if space is String and not (space as String).is_empty() \
		else &"outdoors"

# Only a combat noise carries the sounds-of-fighting cue; v1 added it to every heard report.
static func _remove_misattributed_fighting_cue(state: Dictionary) -> void:
	var noise_texts: Array[String] = []
	var report_texts: Array[String] = []
	for entry: Variant in state["observations"]:
		if not entry is Dictionary or entry.get("status") != "classified" or entry.get("sense") != "hearing" \
				or not entry.get("text") is String or not entry.get("kind") is String:
			continue
		if entry["kind"] == "combat_noise":
			noise_texts.append(entry["text"])
		elif not (entry["kind"] as String).is_empty():
			report_texts.append(entry["text"])
	var memories: Variant = state.get("memories")
	if not memories is Array:
		return
	for memory: Variant in memories:
		if not memory is Dictionary or not memory.get("gist") in report_texts \
				or memory.get("gist") in noise_texts or not memory.get("sensory_cues") is Array:
			continue
		memory["sensory_cues"] = (memory["sensory_cues"] as Array).filter(
			func(cue: Variant) -> bool: return cue != NpcObservation.COMBAT_NOISE_CUE)
