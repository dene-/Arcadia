class_name NpcMindState
extends RefCounted

const TASK_STATUSES: Array[String] = ["CREATED", "RUNNING", "SUSPENDED", "COMPLETED", "CANCELLED", "FAILED"]
const SCHEMA_VERSION: int = 2
const MAX_SECTION_KEYS: int = 256
const MAX_LIST_ITEMS: int = 64
const MAX_JSON_DEPTH: int = 16
const _DATA_KEYS: Array[String] = ["version", "relationships", "commitments", "condition",
	"knowledge", "evidence", "task", "decision_sequence", "incident_budget"]
## Saves written before incident budgets existed load with an empty budget.
const _OPTIONAL_KEYS: Array[String] = ["incident_budget"]
const _CHECKPOINT_KEYS: Array[String] = ["task_id", "kind", "phase", "status", "started_minute",
	"deadline_minute", "generation", "evidence_ids", "commitment_ids", "claims", "params",
	"progress", "suspended"]

var npc_id: String
var relationships := NpcRelationshipGraph.new()
var commitments := NpcCommitments.new()
var condition: Dictionary = {}
## Personal beliefs with provenance; never a copy of world truth.
var knowledge := NpcKnowledge.new()
## Evidence awaiting appraisal; survives provider outages and working-memory pressure.
var evidence := NpcEvidenceInbox.new()
## How much each incident has already changed relationships.
var incident_budget := NpcIncidentBudget.new()
var decision_sequence: int = 0

var _task: Dictionary = {}
var _task_version: int = 0
var _condition_version: int = 0

func _init(id: String = "") -> void:
	npc_id = id
	commitments.owner_id = id

func task_checkpoint() -> Dictionary:
	return _task.duplicate(true)

func set_task_checkpoint(checkpoint: Dictionary) -> bool:
	if not checkpoint.is_empty() and not is_valid_task_checkpoint(checkpoint):
		return false
	_task = _normalized_checkpoint(checkpoint)
	_task_version += 1
	return true

func set_condition(value: Dictionary) -> bool:
	if not _is_valid_section(value):
		return false
	condition = value.duplicate(true)
	_condition_version += 1
	return true

## Records grief for `subject` once: a later learning of the same death adds nothing.
func add_bereavement(subject: String, evidence_id: String, minute: float) -> bool:
	if subject.is_empty() or not is_finite(minute):
		return false
	var concerns: Array = condition.get("concerns", []) if condition.get("concerns") is Array else []
	for concern: Variant in concerns:
		if concern is Dictionary and concern.get("kind") == "bereavement" and concern.get("subject") == subject:
			return false
	var next: Dictionary = condition.duplicate(true)
	var updated: Array = concerns.duplicate(true)
	updated.append({"kind": "bereavement", "subject": subject, "evidence_id": evidence_id, "minute": minute})
	next["concerns"] = updated
	return set_condition(next)

## Applies an evidence-driven change toward `subject` within the observation's incident budget.
## Spends nothing and returns false when `receipt` was already applied.
func apply_evidence_delta(subject: String, observation: NpcObservation, delta: Dictionary,
		receipt: String) -> bool:
	if subject.is_empty() or observation == null:
		return false
	if NpcIncidentBudget.is_surrender(subject, observation):
		incident_budget.record_surrender(subject, observation.observed_minute)
	var incident: String = observation.incident_id if not observation.incident_id.is_empty() \
		else observation.observation_id
	var kind: String = incident_budget.escalation_for(subject, observation,
		evidence.pending_observations())
	var allowed: Dictionary = incident_budget.allowance(subject, incident, kind, delta)
	if not relationships.apply_delta(subject, allowed, receipt, observation.origin_id):
		return false
	incident_budget.spend(subject, incident, kind, allowed)
	return true

func next_decision() -> int:
	decision_sequence += 1
	return decision_sequence

func versions() -> Dictionary:
	return {"relationships": relationships.version, "commitments": commitments.version,
		"task": _task_version, "condition": _condition_version, "knowledge": knowledge.version,
		"evidence": evidence.version, "incident_budget": incident_budget.version}

func to_data() -> Dictionary:
	return {"version": SCHEMA_VERSION, "relationships": relationships.to_data(),
		"commitments": commitments.to_data(), "condition": condition.duplicate(true),
		"knowledge": knowledge.to_data(), "evidence": evidence.to_data(), "task": task_checkpoint(),
		"decision_sequence": decision_sequence, "incident_budget": incident_budget.to_data()}

static func is_valid_data(data: Variant, npc_id: String) -> bool:
	if not data is Dictionary:
		return false
	var source: Dictionary = data
	var present: int = 0
	for key: String in _DATA_KEYS:
		if source.has(key):
			present += 1
		elif not key in _OPTIONAL_KEYS:
			return false
	if source.size() != present:
		return false
	return _is_count(source["version"], SCHEMA_VERSION) and int(source["version"]) == SCHEMA_VERSION \
		and NpcRelationshipGraph.is_valid_data(source["relationships"]) \
		and NpcCommitments.is_valid_data(source["commitments"], npc_id) \
		and _is_valid_section(source["condition"]) and NpcKnowledge.is_valid_data(source["knowledge"]) \
		and NpcEvidenceInbox.is_valid_data(source["evidence"]) \
		and (not source.has("incident_budget")
			or NpcIncidentBudget.is_valid_data(source["incident_budget"])) \
		and (source["task"] is Dictionary and ((source["task"] as Dictionary).is_empty()
			or is_valid_task_checkpoint(source["task"]))) \
		and _is_count(source["decision_sequence"], 0)

func from_data(data: Variant) -> bool:
	if not is_valid_data(data, npc_id):
		return false
	var source: Dictionary = data
	relationships.from_data(source["relationships"])
	commitments.from_data(source["commitments"])
	condition = (source["condition"] as Dictionary).duplicate(true)
	knowledge.from_data(source["knowledge"])
	evidence.from_data(source["evidence"])
	incident_budget.from_data(source.get("incident_budget", NpcIncidentBudget.new().to_data()))
	_task = _normalized_checkpoint(source["task"])
	decision_sequence = int(source["decision_sequence"])
	_task_version += 1
	_condition_version += 1
	return true

static func is_valid_task_checkpoint(value: Variant, allow_suspended: bool = true) -> bool:
	if not value is Dictionary:
		return false
	var checkpoint: Dictionary = value
	if checkpoint.size() != _CHECKPOINT_KEYS.size():
		return false
	for key: String in _CHECKPOINT_KEYS:
		if not checkpoint.has(key):
			return false
	var task_id: Variant = checkpoint["task_id"]
	var kind: Variant = checkpoint["kind"]
	var phase: Variant = checkpoint["phase"]
	var status: Variant = checkpoint["status"]
	if not task_id is String or (task_id as String).is_empty() or (task_id as String).length() > 200 \
			or not kind is String or (kind as String).is_empty() or (kind as String).length() > 64 \
			or not phase is String or (phase as String).length() > 64 \
			or not status is String or not (status as String) in TASK_STATUSES:
		return false
	var started: Variant = checkpoint["started_minute"]
	var deadline: Variant = checkpoint["deadline_minute"]
	if not _is_finite_number(started) or float(started) < 0.0 or not _is_finite_number(deadline) \
			or (float(deadline) != -1.0 and float(deadline) < float(started)):
		return false
	if not _is_count(checkpoint["generation"], 0):
		return false
	for key: String in ["evidence_ids", "commitment_ids", "claims"]:
		if not _is_string_list(checkpoint[key]):
			return false
	for key: String in ["params", "progress"]:
		if not checkpoint[key] is Dictionary or not is_json_safe(checkpoint[key]):
			return false
	var suspended: Variant = checkpoint["suspended"]
	if not suspended is Dictionary:
		return false
	if (suspended as Dictionary).is_empty():
		return true
	return allow_suspended and is_valid_task_checkpoint(suspended, false)

# True for null, bool, int, finite float, String, and Arrays/Dictionaries (String keys) of those.
static func is_json_safe(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_JSON_DEPTH:
		return false
	if value == null or value is bool or value is int or value is String:
		return true
	if value is float:
		return is_finite(value)
	if value is Array:
		for entry: Variant in value:
			if not is_json_safe(entry, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not is_json_safe(value[key], depth + 1):
				return false
		return true
	return false

static func _is_valid_section(value: Variant) -> bool:
	return value is Dictionary and (value as Dictionary).size() <= MAX_SECTION_KEYS \
		and is_json_safe(value)

static func _is_finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _is_count(value: Variant, minimum: int) -> bool:
	return NpcMemory.is_integer(value) and float(value) >= float(minimum) \
		and float(value) <= 9007199254740992.0

static func _is_string_list(value: Variant) -> bool:
	if not value is Array or (value as Array).size() > MAX_LIST_ITEMS:
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

# Copies a validated checkpoint with canonical types (JSON round trips turn ints into floats).
static func _normalized_checkpoint(checkpoint: Dictionary) -> Dictionary:
	if checkpoint.is_empty():
		return {}
	return {"task_id": checkpoint["task_id"], "kind": checkpoint["kind"],
		"phase": checkpoint["phase"], "status": checkpoint["status"],
		"started_minute": float(checkpoint["started_minute"]),
		"deadline_minute": float(checkpoint["deadline_minute"]),
		"generation": int(checkpoint["generation"]),
		"evidence_ids": _string_list(checkpoint["evidence_ids"]),
		"commitment_ids": _string_list(checkpoint["commitment_ids"]),
		"claims": _string_list(checkpoint["claims"]),
		"params": (checkpoint["params"] as Dictionary).duplicate(true),
		"progress": (checkpoint["progress"] as Dictionary).duplicate(true),
		"suspended": _normalized_checkpoint(checkpoint["suspended"])}
