class_name NpcIncidentBudget
extends RefCounted

## Bounds how far one incident can move how a resident feels about a subject. Each
## (subject, incident, escalation kind) owns BUDGET per relationship dimension; both signs spend
## it, so many hit callbacks of one assault cannot farm more change than a few. A new escalation
## (a death, or an attack after the subject surrendered) opens one fresh budget of its own kind.
const BUDGET: float = 0.15
const MAX_CHANGE: float = 0.1
const ORDINARY: String = "ordinary"
const FATAL: String = "fatal"
const SURRENDER_VIOLATION: String = "surrender_violation"
const KINDS: Array[String] = [ORDINARY, FATAL, SURRENDER_VIOLATION]
## Inbox incidents stop growing after 64 newer ones, so older records cannot receive evidence.
const MAX_RECORDS: int = 256
const MAX_SURRENDERS: int = 64
## An attack this long after a seen surrender still breaks it.
const SURRENDER_WINDOW_MINUTES: float = 30.0
const MAX_ID_LENGTH: int = 401
const SCHEMA_VERSION: int = 1
const _ATTACK_KINDS: Array[StringName] = [&"actor_hurt", &"actor_died"]
const _RECORD_KEYS: Array[String] = ["subject", "incident_id", "kind", "used"]

var version: int = 0

## Oldest first; a record moves to the end when it is spent again.
var _records: Array[Dictionary] = []
## subject -> latest world minute this resident saw them surrender.
var _surrenders: Dictionary = {}

## The part of `delta` (all relationship dimensions, each clamped to MAX_CHANGE) still allowed.
func allowance(subject: String, incident_id: String, kind: String, delta: Dictionary) -> Dictionary:
	var used: Dictionary = _used(subject, incident_id, kind)
	var allowed: Dictionary = {}
	for key: String in NpcRelationshipState.KEYS:
		var remaining: float = maxf(0.0, BUDGET - float(used.get(key, 0.0)))
		var amount: float = clampf(float(delta.get(key, 0.0)), -MAX_CHANGE, MAX_CHANGE)
		allowed[key] = clampf(amount, -remaining, remaining)
	return allowed

func spend(subject: String, incident_id: String, kind: String, applied: Dictionary) -> void:
	var index: int = _find(subject, incident_id, kind)
	var record: Dictionary
	if index >= 0:
		record = _records[index]
		_records.remove_at(index)
	else:
		record = {"subject": subject, "incident_id": incident_id, "kind": kind, "used": {}}
	for key: String in NpcRelationshipState.KEYS:
		var amount: float = absf(float(applied.get(key, 0.0)))
		if amount > 0.0:
			record["used"][key] = minf(BUDGET, float(record["used"].get(key, 0.0)) + amount)
	_records.append(record)
	while _records.size() > MAX_RECORDS:
		_records.remove_at(0)
	version += 1

## Total |change| already spent from one budget, per dimension.
func spent(subject: String, incident_id: String, kind: String) -> Dictionary:
	return _used(subject, incident_id, kind).duplicate()

func record_surrender(subject: String, minute: float) -> void:
	if subject.is_empty() or not is_finite(minute) or float(_surrenders.get(subject, -INF)) >= minute:
		return
	if not _surrenders.has(subject) and _surrenders.size() >= MAX_SURRENDERS:
		var oldest: String = ""
		for key: String in _surrenders:
			if oldest.is_empty() or float(_surrenders[key]) < float(_surrenders[oldest]):
				oldest = key
		_surrenders.erase(oldest)
	_surrenders[subject] = minute
	version += 1

## The escalation kind `observation` represents for `subject`. `pending` is unappraised evidence
## the resident already holds, so a surrender seen before an attack counts even when the attack
## (protected evidence) is appraised first.
func escalation_for(subject: String, observation: NpcObservation,
		pending: Array[NpcObservation] = []) -> String:
	if observation.facts.get("fatal") == true:
		return FATAL
	if not observation.kind in _ATTACK_KINDS or not _is_aggressor(subject, observation):
		return ORDINARY
	var surrendered: float = float(_surrenders.get(subject, -INF))
	for other: NpcObservation in pending:
		if is_surrender(subject, other) and other.observed_minute <= observation.observed_minute:
			surrendered = maxf(surrendered, other.observed_minute)
	if surrendered <= observation.observed_minute \
			and observation.observed_minute - surrendered <= SURRENDER_WINDOW_MINUTES:
		return SURRENDER_VIOLATION
	return ORDINARY

static func is_surrender(subject: String, observation: NpcObservation) -> bool:
	return observation.kind == &"surrender" and subject in observation.participant_ids()

func to_data() -> Dictionary:
	return {"version": SCHEMA_VERSION, "records": _records.duplicate(true),
		"surrenders": _surrenders.duplicate()}

static func is_valid_data(data: Variant) -> bool:
	return not _parse(data).is_empty()

## Replaces the whole budget, or changes nothing and returns false.
func from_data(data: Variant) -> bool:
	var parsed: Dictionary = _parse(data)
	if parsed.is_empty():
		return false
	_records = parsed["records"]
	_surrenders = parsed["surrenders"]
	version += 1
	return true

func _find(subject: String, incident_id: String, kind: String) -> int:
	for index: int in range(_records.size() - 1, -1, -1):
		var record: Dictionary = _records[index]
		if record["subject"] == subject and record["incident_id"] == incident_id \
				and record["kind"] == kind:
			return index
	return -1

func _used(subject: String, incident_id: String, kind: String) -> Dictionary:
	var index: int = _find(subject, incident_id, kind)
	return _records[index]["used"] if index >= 0 else {}

static func _is_aggressor(subject: String, observation: NpcObservation) -> bool:
	for participant: Dictionary in observation.participants:
		if participant.get("id") == subject and participant.get("role") == "aggressor":
			return true
	return false

static func _is_id(value: Variant) -> bool:
	return value is String and not (value as String).is_empty() \
		and (value as String).length() <= MAX_ID_LENGTH

static func _is_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

# Normalized {"records", "surrenders"} or {} when invalid.
static func _parse(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var source: Dictionary = data
	if source.size() != 3 or not NpcMemory.is_integer(source.get("version")) \
			or int(source["version"]) != SCHEMA_VERSION or not source.get("records") is Array \
			or not source.get("surrenders") is Dictionary \
			or (source["records"] as Array).size() > MAX_RECORDS \
			or (source["surrenders"] as Dictionary).size() > MAX_SURRENDERS:
		return {}
	var records: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw: Variant in source["records"]:
		if not raw is Dictionary or (raw as Dictionary).size() != _RECORD_KEYS.size():
			return {}
		var record: Dictionary = raw
		for key: String in _RECORD_KEYS:
			if not record.has(key):
				return {}
		if not _is_id(record["subject"]) or not _is_id(record["incident_id"]) \
				or not record["kind"] in KINDS or not record["used"] is Dictionary:
			return {}
		var identity: String = "%s\n%s\n%s" % [record["subject"], record["incident_id"], record["kind"]]
		if seen.has(identity):
			return {}
		seen[identity] = true
		var used: Dictionary = {}
		for key: Variant in record["used"]:
			var amount: Variant = record["used"][key]
			if not key is String or not (key as String) in NpcRelationshipState.KEYS \
					or not _is_number(amount) or float(amount) < 0.0 or float(amount) > BUDGET:
				return {}
			used[key] = float(amount)
		records.append({"subject": record["subject"], "incident_id": record["incident_id"],
			"kind": record["kind"], "used": used})
	var surrenders: Dictionary = {}
	for key: Variant in source["surrenders"]:
		if not _is_id(key) or not _is_number(source["surrenders"][key]):
			return {}
		surrenders[key] = float(source["surrenders"][key])
	return {"records": records, "surrenders": surrenders}
