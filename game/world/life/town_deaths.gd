class_name TownDeaths
extends RefCounted

## Saved physical remains and recovery progress. No culprit is inferred from a body.
const STAGES: Array[String] = ["fallen", "discovered", "reported", "recovering", "carried", "buried"]
var _records: Dictionary = {}

const OK_RESULT: StringName = &"ok"
const UNKNOWN_BODY: StringName = &"unknown_body"
const WRONG_STAGE: StringName = &"wrong_stage"
const NOT_OWNER: StringName = &"not_owner"
const ALREADY_CLAIMED: StringName = &"already_claimed"
const NOT_AT_BODY: StringName = &"not_at_body"
const INVALID: StringName = &"invalid"
const PICKUP_DISTANCE: float = 24.0

func record(id: String, space: String, position: Vector2, minute: float) -> void:
	if _records.has(id):
		return
	_records[id] = {"space": space, "position": [position.x, position.y], "stage": "fallen",
		"since": minute, "reporter": "", "guard": "", "known_by": [], "burial_known_by": []}

func snapshot(id: String) -> Dictionary:
	return _records[id].duplicate(true) if _records.has(id) else {}

func ids() -> Array[String]:
	var result: Array[String] = []
	for id: Variant in _records:
		result.append(id)
	result.sort()
	return result

## Where an unattended body came to rest after its death animation. A carried or buried body
## moves only through its carrier.
func settle(id: String, space: String, position: Vector2) -> StringName:
	var failure := _precheck(id, [space], [position.x, position.y])
	if failure != OK_RESULT:
		return failure
	if _records[id].stage in ["carried", "buried"]:
		return WRONG_STAGE
	_place(_records[id], space, position)
	return OK_RESULT

func discover(id: String, witness_id: String, minute: float) -> StringName:
	var failure := _precheck(id, [witness_id], [minute])
	if failure != OK_RESULT:
		return failure
	var entry: Dictionary = _records[id]
	if entry.stage == "buried":
		return WRONG_STAGE
	_add_once(entry.known_by, witness_id)
	if entry.stage == "fallen":
		entry.reporter = witness_id
		_advance(entry, "discovered", minute)
	return OK_RESULT

func claim_report(id: String, reporter_id: String, minute: float) -> StringName:
	var failure := _precheck(id, [reporter_id], [minute], "discovered")
	if failure != OK_RESULT:
		return failure
	var entry: Dictionary = _records[id]
	if not entry.reporter.is_empty() and entry.reporter != reporter_id:
		return ALREADY_CLAIMED
	entry.reporter = reporter_id
	return OK_RESULT

func acknowledge_report(id: String, guard_id: String, reporter_id: String, minute: float) -> StringName:
	var failure := _precheck(id, [guard_id, reporter_id], [minute], "discovered")
	if failure != OK_RESULT:
		return failure
	var entry: Dictionary = _records[id]
	if entry.reporter != reporter_id:
		return NOT_OWNER
	entry.guard = guard_id
	_add_once(entry.known_by, guard_id)
	_advance(entry, "reported", minute)
	return OK_RESULT

func begin_recovery(id: String, guard_id: String, minute: float) -> StringName:
	var failure := _precheck(id, [guard_id], [minute])
	if failure != OK_RESULT:
		return failure
	var entry: Dictionary = _records[id]
	var claimed_by_other: bool = not entry.guard.is_empty() and entry.guard != guard_id
	if claimed_by_other and entry.stage in ["reported", "recovering", "carried"]:
		return ALREADY_CLAIMED
	if entry.stage != "reported":
		return WRONG_STAGE
	entry.guard = guard_id
	_advance(entry, "recovering", minute)
	return OK_RESULT

func update_carried_position(id: String, guard_id: String, space: String, position: Vector2) -> StringName:
	var failure := _owned(id, guard_id, "carried", [space], [position.x, position.y])
	if failure != OK_RESULT:
		return failure
	_place(_records[id], space, position)
	return OK_RESULT

func pick_up(id: String, guard_id: String, space: String, position: Vector2, minute: float) -> StringName:
	var failure := _owned(id, guard_id, "recovering", [space], [position.x, position.y, minute])
	if failure != OK_RESULT:
		return failure
	var entry: Dictionary = _records[id]
	if entry.space != space or _body_position(entry).distance_to(position) > PICKUP_DISTANCE:
		return NOT_AT_BODY
	_advance(entry, "carried", minute)
	return OK_RESULT

func drop(id: String, guard_id: String, space: String, position: Vector2, minute: float) -> StringName:
	var failure := _owned(id, guard_id, "carried", [space], [position.x, position.y, minute])
	if failure != OK_RESULT:
		return failure
	var entry: Dictionary = _records[id]
	_place(entry, space, position)
	entry.guard = ""
	_advance(entry, "reported", minute)
	return OK_RESULT

func interrupt_recovery(id: String, guard_id: String, minute: float) -> StringName:
	var failure := _owned(id, guard_id, "recovering", [], [minute])
	if failure != OK_RESULT:
		return failure
	_records[id].guard = ""
	_advance(_records[id], "reported", minute)
	return OK_RESULT

func bury(id: String, guard_id: String, minute: float) -> StringName:
	var failure := _owned(id, guard_id, "carried", [], [minute])
	if failure != OK_RESULT:
		return failure
	_advance(_records[id], "buried", minute)
	return OK_RESULT

## The actor died or became unavailable. A carrier leaves the body at its last carried position.
func release_assignment(id: String, actor_id: String, minute: float) -> StringName:
	var failure := _precheck(id, [actor_id], [minute])
	if failure != OK_RESULT:
		return failure
	var entry: Dictionary = _records[id]
	if entry.stage == "discovered" and entry.reporter == actor_id:
		entry.reporter = ""
		return OK_RESULT
	if entry.guard != actor_id:
		return NOT_OWNER
	match entry.stage:
		"reported":
			entry.guard = ""
			return OK_RESULT
		"recovering", "carried":
			entry.guard = ""
			_advance(entry, "reported", minute)
			return OK_RESULT
	return NOT_OWNER

func mark_known(id: String, npc_id: String) -> StringName:
	var failure := _precheck(id, [npc_id], [])
	if failure == OK_RESULT:
		_add_once(_records[id].known_by, npc_id)
	return failure

func mark_burial_known(id: String, npc_id: String) -> StringName:
	var failure := _precheck(id, [npc_id], [], "buried")
	if failure == OK_RESULT:
		_add_once(_records[id].burial_known_by, npc_id)
	return failure

func to_data() -> Dictionary:
	return {"version": 1, "records": _records.duplicate(true)}

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
	_records = saved.duplicate(true)
	return true

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

## Validates arguments and, when `stage` is given, the body's stage. Never mutates.
func _precheck(id: String, texts: Array, numbers: Array, stage: String = "") -> StringName:
	if id.is_empty():
		return INVALID
	for text: String in texts:
		if text.is_empty():
			return INVALID
	for value: float in numbers:
		if not is_finite(value):
			return INVALID
	if not _records.has(id):
		return UNKNOWN_BODY
	if not stage.is_empty() and _records[id].stage != stage:
		return WRONG_STAGE
	return OK_RESULT

func _owned(id: String, guard_id: String, stage: String, texts: Array, numbers: Array) -> StringName:
	var failure := _precheck(id, [guard_id] + texts, numbers, stage)
	if failure != OK_RESULT:
		return failure
	return OK_RESULT if _records[id].guard == guard_id else NOT_OWNER

static func _add_once(list: Array, value: String) -> void:
	if not value in list:
		list.append(value)

static func _advance(entry: Dictionary, stage: String, minute: float) -> void:
	entry.stage = stage
	entry.since = minute

static func _place(entry: Dictionary, space: String, position: Vector2) -> void:
	entry.space = space
	entry.position = [position.x, position.y]

static func _body_position(entry: Dictionary) -> Vector2:
	return Vector2(float(entry.position[0]), float(entry.position[1]))
