class_name NpcRelationshipGraph
extends RefCounted

const MAX_SUBJECTS: int = 1024
# FIFO cap; M6 replaces this with real receipt compaction.
const MAX_RECEIPTS: int = 1024
const MAX_RECEIPT_LENGTH: int = 500

var version: int = 0

var _subjects: Dictionary = {}
var _receipts: Array[String] = []
var _receipt_set: Dictionary = {}

func get_relationship(subject_id: String) -> Dictionary:
	if not _subjects.has(subject_id):
		return NpcRelationshipState.initial()
	var stored: Dictionary = _subjects[subject_id]
	return stored.duplicate()

func has_subject(subject_id: String) -> bool:
	return _subjects.has(subject_id)

func subjects() -> Array[String]:
	var result: Array[String] = []
	for key: Variant in _subjects:
		result.append(key as String)
	result.sort()
	return result

# Seeds a new subject. With replace, an existing subject is overwritten by the given values
# (missing dimensions return to neutral); receipts are untouched.
func seed_relationship(subject_id: String, values: Dictionary, replace: bool = false) -> bool:
	if subject_id.is_empty() or (_subjects.has(subject_id) and not replace) \
			or (not _subjects.has(subject_id) and _subjects.size() >= MAX_SUBJECTS):
		return false
	var seeded: Dictionary = NpcRelationshipState.initial()
	for key: Variant in values:
		if not key is String or not (key as String) in NpcRelationshipState.KEYS \
				or not _is_finite_number(values[key]):
			return false
		seeded[key] = float(values[key])
	if not NpcRelationshipState.is_valid(seeded):
		return false
	_subjects[subject_id] = seeded
	version += 1
	return true

func apply_delta(subject_id: String, delta: Dictionary, receipt_id: String) -> bool:
	if subject_id.is_empty() or receipt_id.is_empty() or receipt_id.length() > MAX_RECEIPT_LENGTH \
			or _receipt_set.has(receipt_id):
		return false
	for key: Variant in delta:
		if not key is String or not (key as String) in NpcRelationshipState.KEYS \
				or not _is_finite_number(delta[key]):
			return false
	if not _subjects.has(subject_id) and _subjects.size() >= MAX_SUBJECTS:
		return false
	var current: Dictionary = _subjects.get(subject_id, NpcRelationshipState.initial())
	_subjects[subject_id] = NpcRelationshipState.changed(current, delta)
	_receipts.append(receipt_id)
	_receipt_set[receipt_id] = true
	while _receipts.size() > MAX_RECEIPTS:
		_receipt_set.erase(_receipts.pop_front())
	version += 1
	return true

func has_receipt(receipt_id: String) -> bool:
	return _receipt_set.has(receipt_id)

func to_data() -> Dictionary:
	return {"subjects": _subjects.duplicate(true), "receipts": _receipts.duplicate()}

static func is_valid_data(data: Variant) -> bool:
	return not _parse(data).is_empty()

func from_data(data: Variant) -> bool:
	var parsed: Dictionary = _parse(data)
	if parsed.is_empty():
		return false
	_subjects = parsed["subjects"]
	_receipts = parsed["receipts"]
	_receipt_set.clear()
	for receipt: String in _receipts:
		_receipt_set[receipt] = true
	version += 1
	return true

static func _is_finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

# Returns normalized {"subjects", "receipts"} (floats, typed receipts) or {} when invalid.
static func _parse(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var source: Dictionary = data
	if source.size() != 2 or not source.get("subjects") is Dictionary \
			or not source.get("receipts") is Array:
		return {}
	var raw_subjects: Dictionary = source["subjects"]
	var raw_receipts: Array = source["receipts"]
	if raw_subjects.size() > MAX_SUBJECTS or raw_receipts.size() > MAX_RECEIPTS:
		return {}
	var subjects: Dictionary = {}
	for key: Variant in raw_subjects:
		if not key is String or (key as String).is_empty() \
				or not NpcRelationshipState.is_valid(raw_subjects[key]):
			return {}
		var normalized: Dictionary = {}
		for dimension: String in NpcRelationshipState.KEYS:
			normalized[dimension] = float(raw_subjects[key][dimension])
		subjects[key] = normalized
	var receipts: Array[String] = []
	var seen: Dictionary = {}
	for raw: Variant in raw_receipts:
		if not raw is String:
			return {}
		var receipt: String = raw
		if receipt.is_empty() or receipt.length() > MAX_RECEIPT_LENGTH or seen.has(receipt):
			return {}
		seen[receipt] = true
		receipts.append(receipt)
	return {"subjects": subjects, "receipts": receipts}
