class_name NpcCommitments
extends RefCounted

const KINDS: Array[String] = ["report_discovery", "check_relative", "attend_obligation", "visit_grave"]
const STATUSES: Array[String] = ["open", "completed", "cancelled", "failed"]
const MAX_ITEMS: int = 256
const MAX_IDS: int = 64
const MAX_TASK_ID_LENGTH: int = 200
const _RECORD_KEYS: Array[String] = ["id", "owner", "kind", "other_ids", "evidence_ids",
	"created_minute", "deadline_minute", "priority", "status", "task_id", "resolved_minute"]

var owner_id: String = ""
var version: int = 0

var _next_id: int = 1
var _items: Array[Dictionary] = []

func create(kind: String, other_ids: Array[String], evidence_ids: Array[String],
		created_minute: float, deadline_minute: float = -1.0, priority: float = 0.5) -> String:
	if owner_id.is_empty() or not kind in KINDS or _items.size() >= MAX_ITEMS:
		return ""
	if not is_finite(created_minute) or not is_finite(deadline_minute) or not is_finite(priority) \
			or priority < 0.0 or priority > 1.0:
		return ""
	if not _is_id_list(other_ids) or not _is_id_list(evidence_ids):
		return ""
	var id: String = _id_for(owner_id, _next_id)
	_next_id += 1
	_items.append({"id": id, "owner": owner_id, "kind": kind, "other_ids": other_ids.duplicate(),
		"evidence_ids": evidence_ids.duplicate(), "created_minute": created_minute,
		"deadline_minute": deadline_minute, "priority": priority, "status": "open",
		"task_id": "", "resolved_minute": -1.0})
	version += 1
	return id

func link_task(commitment_id: String, task_id: String) -> bool:
	var index: int = _index_of(commitment_id)
	if index < 0 or task_id.is_empty() or task_id.length() > MAX_TASK_ID_LENGTH \
			or _items[index]["status"] != "open":
		return false
	_items[index]["task_id"] = task_id
	version += 1
	return true

func resolve(commitment_id: String, status: String, at_minute: float) -> bool:
	var index: int = _index_of(commitment_id)
	if index < 0 or status == "open" or not status in STATUSES or not is_finite(at_minute) \
			or _items[index]["status"] != "open":
		return false
	_items[index]["status"] = status
	_items[index]["resolved_minute"] = at_minute
	version += 1
	return true

func get_commitment(commitment_id: String) -> Dictionary:
	var index: int = _index_of(commitment_id)
	if index < 0:
		return {}
	return _items[index].duplicate(true)

func open_commitments() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in _items:
		if item["status"] == "open":
			result.append(item.duplicate(true))
	return result

func to_data() -> Dictionary:
	var items: Array = []
	for item: Dictionary in _items:
		items.append(item.duplicate(true))
	return {"next_id": _next_id, "items": items}

static func is_valid_data(data: Variant, owner: String) -> bool:
	return not _parse(data, owner).is_empty()

func from_data(data: Variant) -> bool:
	var parsed: Dictionary = _parse(data, owner_id)
	if parsed.is_empty():
		return false
	_next_id = parsed["next_id"]
	_items = parsed["items"]
	version += 1
	return true

func _index_of(commitment_id: String) -> int:
	for index: int in _items.size():
		if _items[index]["id"] == commitment_id:
			return index
	return -1

static func _prefix(owner: String) -> String:
	return "commitment:%s:" % owner

static func _id_for(owner: String, number: int) -> String:
	return _prefix(owner) + str(number)

static func _is_finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _is_count(value: Variant, minimum: int) -> bool:
	return NpcMemory.is_integer(value) and float(value) >= float(minimum) \
		and float(value) <= 9007199254740992.0

static func _is_id_list(value: Variant) -> bool:
	if not value is Array or (value as Array).size() > MAX_IDS:
		return false
	for entry: Variant in value:
		if not entry is String or (entry as String).is_empty():
			return false
	return true

static func _string_list(value: Array) -> Array[String]:
	var result: Array[String] = []
	for entry: Variant in value:
		result.append(entry as String)
	return result

# Returns normalized {"next_id", "items"} or {} when invalid.
static func _parse(data: Variant, owner: String) -> Dictionary:
	if not data is Dictionary:
		return {}
	var source: Dictionary = data
	if source.size() != 2 or not _is_count(source.get("next_id"), 1) \
			or not source.get("items") is Array:
		return {}
	var raw_items: Array = source["items"]
	var next_id: int = int(source["next_id"])
	if raw_items.size() > MAX_ITEMS:
		return {}
	var items: Array[Dictionary] = []
	var previous: int = 0
	for raw: Variant in raw_items:
		var item: Dictionary = _parse_item(raw, owner)
		if item.is_empty():
			return {}
		var number: int = int((item["id"] as String).substr(_prefix(owner).length()))
		if number <= previous or number >= next_id:
			return {}
		previous = number
		items.append(item)
	return {"next_id": next_id, "items": items}

static func _parse_item(raw: Variant, owner: String) -> Dictionary:
	if not raw is Dictionary or owner.is_empty():
		return {}
	var record: Dictionary = raw
	if record.size() != _RECORD_KEYS.size():
		return {}
	for key: String in _RECORD_KEYS:
		if not record.has(key):
			return {}
	var id: Variant = record["id"]
	var kind: Variant = record["kind"]
	var status: Variant = record["status"]
	var task_id: Variant = record["task_id"]
	if not id is String or not _is_item_id(id, owner) or record["owner"] != owner \
			or not kind is String or not (kind as String) in KINDS \
			or not status is String or not (status as String) in STATUSES \
			or not task_id is String or (task_id as String).length() > MAX_TASK_ID_LENGTH \
			or not _is_id_list(record["other_ids"]) or not _is_id_list(record["evidence_ids"]):
		return {}
	for key: String in ["created_minute", "deadline_minute", "priority", "resolved_minute"]:
		if not _is_finite_number(record[key]):
			return {}
	var priority: float = float(record["priority"])
	var resolved: float = float(record["resolved_minute"])
	if priority < 0.0 or priority > 1.0 or (status == "open" and resolved != -1.0):
		return {}
	return {"id": id, "owner": owner, "kind": kind,
		"other_ids": _string_list(record["other_ids"]),
		"evidence_ids": _string_list(record["evidence_ids"]),
		"created_minute": float(record["created_minute"]),
		"deadline_minute": float(record["deadline_minute"]), "priority": priority,
		"status": status, "task_id": task_id, "resolved_minute": resolved}

static func _is_item_id(id: String, owner: String) -> bool:
	var prefix: String = _prefix(owner)
	if not id.begins_with(prefix):
		return false
	var suffix: String = id.substr(prefix.length())
	return suffix.is_valid_int() and str(int(suffix)) == suffix and int(suffix) >= 1
