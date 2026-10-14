class_name NpcMemory
extends RefCounted

## Explicit JSON-compatible memory contract shared by authored and runtime records.
const TYPES: Array[String] = ["episodic", "semantic", "social", "prospective"]
const SOURCES: Array[String] = ["authored", "player_claim", "npc_statement", "observed_event", "hearsay"]
const TEXT_LISTS: Array[String] = ["topics", "people", "places", "sensory_cues",
	"important_details", "weak_details", "known_gaps"]
const UNIT_FIELDS: Array[String] = ["importance", "emotional_intensity", "vividness", "confidence"]
## Optional evidence fields of event memories; validated when present.
const MODALITIES: Array[String] = ["sight", "hearing", "touch", "speech", "unknown"]
const ID_FIELDS: Array[String] = ["observation_kind", "incident_id", "origin_id"]
const MAX_ID_LENGTH: int = 401
const MAX_EVIDENCE_IDS: int = 16
const MAX_CHAIN: int = 4
## `created_minute` of a memory whose world date was never recorded.
const UNKNOWN_MINUTE: float = -1.0
## One retention unit is half an in-game hour, independent of NPC/event counts.
const MINUTES_PER_RETENTION_UNIT: float = 30.0

## Marks an undated memory as such and starts its world-time aging at `minute`. Only authored
## relative age (a negative `created_turn`) carries over: exchange counts are not elapsed time.
## A memory that was anchored before keeps its anchor minute, so repeated loads change nothing.
static func anchor_legacy(memory: Dictionary, minute: float) -> void:
	if memory.get("date_known") is bool or float(memory.get("created_minute", UNKNOWN_MINUTE)) >= 0.0:
		return
	memory.created_minute = UNKNOWN_MINUTE
	memory.date_known = false
	if not memory.has("age_anchor_minute"):
		memory.age_anchor_minute = minute
	memory.age_at_anchor = float(maxi(0, -int(memory.created_turn)))

static func retention_age(memory: Dictionary, minute: float) -> float:
	if float(memory.get("created_minute", UNKNOWN_MINUTE)) >= 0.0:
		return maxf(0.0, minute - float(memory.created_minute)) / MINUTES_PER_RETENTION_UNIT
	if memory.has("age_anchor_minute"):
		return float(memory.age_at_anchor) + maxf(0.0, minute - float(memory.age_anchor_minute)) \
			/ MINUTES_PER_RETENTION_UNIT
	# Uninstantiated authored records have relative age, not a known world date.
	return maxf(0.0, -float(memory.created_turn))

## Evidence modality of an observation, in memory vocabulary.
static func modality_of(observation: NpcObservation) -> String:
	match observation.modality:
		NpcObservation.Modality.SIGHT:
			return "sight"
		NpcObservation.Modality.TOUCH:
			return "touch"
		NpcObservation.Modality.NOISE:
			return "hearing"
		NpcObservation.Modality.SPOKEN_REPORT, NpcObservation.Modality.DIRECT_SPEECH:
			return "speech"
	return "unknown"

static func create(id: String, type: String, gist: String, source: String,
		turn: int) -> Dictionary:
	var memory: Dictionary = {
		"id": id, "type": type, "gist": gist, "source": source,
		"created_turn": turn, "last_recalled_turn": -1, "recall_count": 0,
		"importance": 0.5, "emotional_intensity": 0.0, "vividness": 0.5,
		"confidence": 0.5, "completed": false,
	}
	for key: String in TEXT_LISTS:
		memory[key] = []
	return memory

static func is_unit(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) \
		and float(value) >= 0.0 and float(value) <= 1.0

static func is_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) == floorf(float(value))

static func is_text_list(value: Variant, limit: int = 8) -> bool:
	if not value is Array or value.size() > limit:
		return false
	for item: Variant in value:
		if not item is String or item.length() > 200:
			return false
	return true

static func is_valid(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key: String in ["id", "type", "gist", "source"]:
		if not value.get(key) is String or value[key].is_empty() or value[key].length() > 500:
			return false
	if not value.type in TYPES or not value.source in SOURCES:
		return false
	if value.has("evidence") and (not value.evidence is String or value.evidence.length() > 500):
		return false
	if value.has("age_anchor_minute") != value.has("age_at_anchor"):
		return false
	for key: String in ["age_anchor_minute", "age_at_anchor", "last_recalled_minute"]:
		if value.has(key) and (not (value[key] is float or value[key] is int) \
			or not is_finite(float(value[key])) or value[key] < 0):
			return false
	if not _is_valid_date(value) or not _is_valid_evidence(value):
		return false
	for key: String in UNIT_FIELDS:
		if not is_unit(value.get(key)):
			return false
	for key: String in TEXT_LISTS:
		if not is_text_list(value.get(key)):
			return false
	for key: String in ["created_turn", "last_recalled_turn", "recall_count"]:
		if not is_integer(value.get(key)):
			return false
	return value.recall_count >= 0 and value.get("completed") is bool

# created_minute is a world minute or UNKNOWN_MINUTE; an unknown date ages from its load anchor.
static func _is_valid_date(value: Dictionary) -> bool:
	if value.has("date_known") and not value.date_known is bool:
		return false
	if not value.has("created_minute"):
		return value.get("date_known", false) == false
	var minute: Variant = value.created_minute
	if not (minute is float or minute is int) or not is_finite(float(minute)):
		return false
	if float(minute) >= 0.0:
		return value.get("date_known", true) == true and not value.has("age_anchor_minute")
	return float(minute) == UNKNOWN_MINUTE and value.get("date_known") == false \
		and value.has("age_anchor_minute")

static func _is_valid_evidence(value: Dictionary) -> bool:
	for key: String in ID_FIELDS:
		if value.has(key) and (not value[key] is String or value[key].length() > MAX_ID_LENGTH):
			return false
	if value.has("modality") and not value.modality in MODALITIES:
		return false
	if value.has("observed_minute"):
		var minute: Variant = value.observed_minute
		if not (minute is float or minute is int) or not is_finite(float(minute)) \
				or (float(minute) < 0.0 and float(minute) != UNKNOWN_MINUTE):
			return false
	return (not value.has("evidence_ids") or _is_id_list(value.evidence_ids, MAX_EVIDENCE_IDS)) \
		and (not value.has("chain") or _is_id_list(value.chain, MAX_CHAIN))

static func _is_id_list(value: Variant, limit: int) -> bool:
	if not value is Array or value.size() > limit:
		return false
	for item: Variant in value:
		if not item is String or item.is_empty() or item.length() > MAX_ID_LENGTH:
			return false
	return true
