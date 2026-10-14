class_name NpcRelationshipGraph
extends RefCounted

const MAX_SUBJECTS: int = 1024
## Hard bound on stored receipts. Receipts are never dropped while an origin may still replay
## them: at the bound only origin-less receipts make room, otherwise a new delta is refused.
const MAX_RECEIPTS: int = 4096
const MAX_RECEIPT_LENGTH: int = 500

var version: int = 0

var _subjects: Dictionary = {}
var _receipts: Array[String] = []
var _receipt_set: Dictionary = {}
# Replayable origin of each receipt applied since origins were recorded ("" = none). Receipts
# loaded from older saves have no entry: their origin is unknown, so compaction keeps them.
var _origins: Dictionary[String, String] = {}

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

## `origin_id` names the event or rumor origin whose replay this receipt guards ("" when the
## receipt id itself is never reissued, e.g. a counter-based receipt).
func apply_delta(subject_id: String, delta: Dictionary, receipt_id: String,
		origin_id: String = "") -> bool:
	if subject_id.is_empty() or receipt_id.is_empty() or receipt_id.length() > MAX_RECEIPT_LENGTH \
			or origin_id.length() > MAX_RECEIPT_LENGTH or _receipt_set.has(receipt_id):
		return false
	for key: Variant in delta:
		if not key is String or not (key as String) in NpcRelationshipState.KEYS \
				or not _is_finite_number(delta[key]):
			return false
	if not _subjects.has(subject_id) and _subjects.size() >= MAX_SUBJECTS:
		return false
	if _receipts.size() >= MAX_RECEIPTS and not _drop_originless_receipt():
		return false
	var current: Dictionary = _subjects.get(subject_id, NpcRelationshipState.initial())
	_subjects[subject_id] = NpcRelationshipState.changed(current, delta)
	_receipts.append(receipt_id)
	_receipt_set[receipt_id] = true
	_origins[receipt_id] = origin_id
	version += 1
	return true

## Prunes every receipt that no `references` entry (receipt ids or origin ids) can replay: its
## origin is known and neither it nor its origin is referenced. Returns the number pruned.
func compact(references: Dictionary) -> int:
	var kept: Array[String] = []
	for receipt: String in _receipts:
		if _origins.has(receipt) and not references.has(receipt) \
				and (_origins[receipt].is_empty() or not references.has(_origins[receipt])):
			_receipt_set.erase(receipt)
			_origins.erase(receipt)
		else:
			kept.append(receipt)
	var pruned: int = _receipts.size() - kept.size()
	_receipts = kept
	return pruned

func receipt_count() -> int:
	return _receipts.size()

func _drop_originless_receipt() -> bool:
	for index: int in _receipts.size():
		var receipt: String = _receipts[index]
		if _origins.has(receipt) and _origins[receipt].is_empty():
			_receipts.remove_at(index)
			_receipt_set.erase(receipt)
			_origins.erase(receipt)
			return true
	return false

func has_receipt(receipt_id: String) -> bool:
	return _receipt_set.has(receipt_id)

## "origins" is written only when some receipt recorded one; saves without it load as legacy.
func to_data() -> Dictionary:
	var data: Dictionary = {"subjects": _subjects.duplicate(true), "receipts": _receipts.duplicate()}
	if not _origins.is_empty():
		data["origins"] = _origins.duplicate()
	return data

static func is_valid_data(data: Variant) -> bool:
	return not _parse(data).is_empty()

func from_data(data: Variant) -> bool:
	var parsed: Dictionary = _parse(data)
	if parsed.is_empty():
		return false
	_subjects = parsed["subjects"]
	_receipts = parsed["receipts"]
	_origins = parsed["origins"]
	_receipt_set.clear()
	for receipt: String in _receipts:
		_receipt_set[receipt] = true
	version += 1
	return true

static func _is_finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

# Returns normalized {"subjects", "receipts", "origins"} (floats, typed receipts) or {} when invalid.
static func _parse(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var source: Dictionary = data
	if source.size() != (3 if source.has("origins") else 2) or not source.get("subjects") is Dictionary \
			or not source.get("receipts") is Array or not source.get("origins", {}) is Dictionary:
		return {}
	var raw_subjects: Dictionary = source["subjects"]
	var raw_receipts: Array = source["receipts"]
	var raw_origins: Dictionary = source.get("origins", {})
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
	var origins: Dictionary[String, String] = {}
	for receipt: Variant in raw_origins:
		var origin: Variant = raw_origins[receipt]
		if not seen.has(receipt) or not origin is String \
				or (origin as String).length() > MAX_RECEIPT_LENGTH:
			return {}
		origins[receipt] = origin
	return {"subjects": subjects, "receipts": receipts, "origins": origins}
