class_name NpcMindState
extends RefCounted

const TASK_STATUSES: Array[String] = ["CREATED", "RUNNING", "SUSPENDED", "COMPLETED", "CANCELLED", "FAILED"]
const SCHEMA_VERSION: int = 2
const MAX_SECTION_KEYS: int = 256
const MAX_LIST_ITEMS: int = 64
const MAX_JSON_DEPTH: int = 16
const _DATA_KEYS: Array[String] = ["version", "relationships", "commitments", "condition",
	"knowledge", "evidence", "task", "decision_sequence", "incident_budget", "needs", "emotions"]
## Older saves load with an empty budget, neutral needs and no emotions.
const _OPTIONAL_KEYS: Array[String] = ["incident_budget", "needs", "emotions"]
const NEEDS: Array[String] = ["hunger", "fatigue", "social"]
const EMOTIONS: Array[String] = ["fear", "anger", "grief", "relief"]
const MAX_EMOTIONS: int = 32
const MAX_REF_LENGTH: int = 200
const _EMOTION_KEYS: Array[String] = ["emotion", "cause", "subject", "evidence_id", "incident_id",
	"intensity", "onset_minute"]
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
## Need name (NEEDS) -> 0 (satisfied) .. 1 (pressing).
var needs: Dictionary = {}
## Tuning for time-based reads (emotion decay and condition bands).
var tuning: NpcBehaviorTuning = _shared_tuning()

static var _default_tuning: NpcBehaviorTuning

# One record per (cause, emotion), oldest first; see `feel`.
var _emotions: Array[Dictionary] = []

var _task: Dictionary = {}
var _task_version: int = 0
var _condition_version: int = 0

func _init(id: String = "") -> void:
	npc_id = id
	commitments.owner_id = id
	needs = neutral_needs(tuning)

static func neutral_needs(source: NpcBehaviorTuning) -> Dictionary:
	return {"hunger": source.initial_hunger, "fatigue": source.initial_fatigue,
		"social": source.initial_social}

## Advances needs by elapsed game minutes; fatigue eases only while actually asleep.
func advance_needs(minutes: float, sleeping: bool, sociability: float,
		source: NpcBehaviorTuning) -> void:
	if not is_finite(minutes) or minutes <= 0.0 or not is_finite(sociability):
		return
	_set_need("hunger", _need("hunger") + source.hunger_per_minute * minutes)
	var fatigue_rate: float = -source.fatigue_sleep_relief_per_minute if sleeping \
		else source.fatigue_awake_per_minute
	_set_need("fatigue", _need("fatigue") + fatigue_rate * minutes)
	_set_need("social", _need("social") + source.social_per_minute * minutes
		* (source.social_rate_base + clampf(sociability, 0.0, 1.0)))

## A completed meal leaves the resident satisfied, never hungrier than before.
func complete_meal(source: NpcBehaviorTuning) -> void:
	_set_need("hunger", minf(_need("hunger"), source.meal_hunger))

## A delivered meaningful exchange eases social need.
func complete_exchange(source: NpcBehaviorTuning) -> void:
	_set_need("social", _need("social") - source.exchange_social_relief)

## A wordless greeting (no provider answered) eases social need by a smaller amount.
func complete_greeting(source: NpcBehaviorTuning) -> void:
	_set_need("social", _need("social") - source.greeting_social_relief)

## Records the emotional impulse of one cause (the incident, else the evidence). Reappraising
## the same cause may raise its intensity to the larger judgment but never adds a second impulse
## or restarts its decay. Returns true when the record changed.
func feel(emotion: String, intensity: float, subject: String, evidence_id: String,
		incident_id: String, minute: float) -> bool:
	var cause: String = incident_id if not incident_id.is_empty() else evidence_id
	if not emotion in EMOTIONS or not is_finite(intensity) or intensity <= 0.0 \
			or not is_finite(minute) or minute < 0.0 or cause.is_empty() \
			or cause.length() > MAX_REF_LENGTH or subject.length() > MAX_REF_LENGTH \
			or evidence_id.length() > MAX_REF_LENGTH or incident_id.length() > MAX_REF_LENGTH:
		return false
	var value: float = minf(intensity, 1.0)
	for record: Dictionary in _emotions:
		if record["cause"] == cause and record["emotion"] == emotion:
			var changed: bool = false
			if value > float(record["intensity"]):
				record["intensity"] = value
				changed = true
			if (record["subject"] as String).is_empty() and not subject.is_empty():
				record["subject"] = subject
				changed = true
			return changed
	_make_room(minute)
	_emotions.append({"emotion": emotion, "cause": cause, "subject": subject,
		"evidence_id": evidence_id, "incident_id": incident_id, "intensity": value,
		"onset_minute": minute})
	return true

## Current intensity (0..1): the strongest cause after half-life decay since its onset.
func emotion(name: String, minute: float) -> float:
	var strongest: float = 0.0
	for record: Dictionary in _emotions:
		if record["emotion"] == name:
			strongest = maxf(strongest, _current(record, minute))
	return strongest

## Causes still felt at or above `tuning.emotion_mild`, strongest first: {emotion, intensity,
## subject, evidence_id, incident_id, onset_minute}.
func emotion_causes(minute: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in _emotions:
		var current: float = _current(record, minute)
		if current >= tuning.emotion_mild:
			result.append({"emotion": record["emotion"], "intensity": current,
				"subject": record["subject"], "evidence_id": record["evidence_id"],
				"incident_id": record["incident_id"], "onset_minute": record["onset_minute"]})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["intensity"]) > float(b["intensity"]))
	return result

## Semantic bands: {hunger, fatigue, social: low|moderate|pressing; emotions: {name: none|mild|
## strong}; emotion: strongest felt emotion or ""; emotion_band}. Ties keep EMOTIONS order.
func condition_band(minute: float) -> Dictionary:
	var result: Dictionary = {}
	for need: String in NEEDS:
		result[need] = level_band(_need(need), tuning.need_moderate, tuning.need_pressing)
	var bands: Dictionary = {}
	var strongest: String = ""
	var strongest_value: float = 0.0
	for name: String in EMOTIONS:
		var value: float = emotion(name, minute)
		bands[name] = emotion_band(value, tuning)
		if value >= tuning.emotion_mild and value > strongest_value:
			strongest = name
			strongest_value = value
	result["emotions"] = bands
	result["emotion"] = strongest
	result["emotion_band"] = emotion_band(strongest_value, tuning)
	return result

## Read version for decision tickets: changes with concerns and with condition bands, never with
## a decay or need tick that stays inside its band.
func condition_version(minute: float) -> String:
	var band: Dictionary = condition_band(minute)
	var code: String = "%d|" % _condition_version
	for need: String in NEEDS:
		code += (band[need] as String).left(1)
	code += "|"
	for name: String in EMOTIONS:
		code += (band["emotions"][name] as String).left(1)
	return code

static func level_band(value: float, moderate: float, pressing: float) -> String:
	if value >= pressing:
		return "pressing"
	return "moderate" if value >= moderate else "low"

static func emotion_band(value: float, source: NpcBehaviorTuning) -> String:
	if value >= source.emotion_strong:
		return "strong"
	return "mild" if value >= source.emotion_mild else "none"

## Pain (0..1) read from the actor's real health; nothing is stored.
static func pain_of(actor: Object) -> float:
	if actor == null or not "health" in actor or not "max_health" in actor:
		return 0.0
	var maximum: float = float(actor.get("max_health"))
	if maximum <= 0.0:
		return 0.0
	return clampf(1.0 - float(actor.get("health")) / maximum, 0.0, 1.0)

static func pain_band(pain: float, source: NpcBehaviorTuning) -> String:
	return level_band(pain, source.pain_moderate, source.pain_pressing)

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
		"decision_sequence": decision_sequence, "incident_budget": incident_budget.to_data(),
		"needs": needs.duplicate(), "emotions": _emotions.duplicate(true)}

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
		and _is_count(source["decision_sequence"], 0) \
		and (not source.has("needs") or not _parsed_needs(source["needs"]).is_empty()) \
		and (not source.has("emotions") or _parsed_emotions(source["emotions"]) != null)

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
	needs = _parsed_needs(source["needs"]) if source.has("needs") else neutral_needs(tuning)
	var loaded: Array[Dictionary] = []
	if source.has("emotions"):
		loaded = _parsed_emotions(source["emotions"])
	_emotions = loaded
	_task = _normalized_checkpoint(source["task"])
	decision_sequence = int(source["decision_sequence"])
	_task_version += 1
	_condition_version += 1
	return true

static func _shared_tuning() -> NpcBehaviorTuning:
	if _default_tuning == null:
		_default_tuning = NpcBehaviorTuning.new()
	return _default_tuning

func _need(name: String) -> float:
	return float(needs.get(name, 0.0))

func _set_need(name: String, value: float) -> void:
	needs[name] = clampf(value, 0.0, 1.0)

func _half_life(name: String) -> float:
	match name:
		"fear":
			return tuning.fear_half_life_minutes
		"anger":
			return tuning.anger_half_life_minutes
		"relief":
			return tuning.relief_half_life_minutes
	return tuning.grief_half_life_minutes

func _current(record: Dictionary, minute: float) -> float:
	var elapsed: float = maxf(0.0, minute - float(record["onset_minute"])) if is_finite(minute) else 0.0
	return float(record["intensity"]) * pow(0.5, elapsed / maxf(_half_life(record["emotion"]), 1.0))

# Drops causes no longer felt; at the cap, also the weakest remaining one.
func _make_room(minute: float) -> void:
	_emotions = _emotions.filter(func(record: Dictionary) -> bool:
		return _current(record, minute) >= tuning.emotion_mild)
	if _emotions.size() < MAX_EMOTIONS:
		return
	var weakest: int = 0
	for index: int in _emotions.size():
		if _current(_emotions[index], minute) < _current(_emotions[weakest], minute):
			weakest = index
	_emotions.remove_at(weakest)

# Canonical needs, or {} when invalid.
static func _parsed_needs(value: Variant) -> Dictionary:
	if not value is Dictionary or (value as Dictionary).size() != NEEDS.size():
		return {}
	var result: Dictionary = {}
	for name: String in NEEDS:
		var level: Variant = (value as Dictionary).get(name)
		if not _is_finite_number(level) or float(level) < 0.0 or float(level) > 1.0:
			return {}
		result[name] = float(level)
	return result

# Canonical emotion records, or null when invalid.
static func _parsed_emotions(value: Variant) -> Variant:
	if not value is Array or (value as Array).size() > MAX_EMOTIONS:
		return null
	var result: Array[Dictionary] = []
	var keys: Dictionary[String, bool] = {}
	for raw: Variant in value:
		if not raw is Dictionary or (raw as Dictionary).size() != _EMOTION_KEYS.size():
			return null
		var record: Dictionary = raw
		for key: String in ["emotion", "cause", "subject", "evidence_id", "incident_id"]:
			if not record.get(key) is String or (record[key] as String).length() > MAX_REF_LENGTH:
				return null
		var key: String = "%s|%s" % [record["emotion"], record["cause"]]
		if not record["emotion"] in EMOTIONS or (record["cause"] as String).is_empty() \
				or keys.has(key) or not _is_finite_number(record.get("intensity")) \
				or float(record["intensity"]) <= 0.0 or float(record["intensity"]) > 1.0 \
				or not _is_finite_number(record.get("onset_minute")) or float(record["onset_minute"]) < 0.0:
			return null
		keys[key] = true
		result.append({"emotion": record["emotion"], "cause": record["cause"],
			"subject": record["subject"], "evidence_id": record["evidence_id"],
			"incident_id": record["incident_id"], "intensity": float(record["intensity"]),
			"onset_minute": float(record["onset_minute"])})
	return result

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
