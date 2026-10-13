class_name NpcObservation
extends RefCounted

## One resident's personal, value-only account of something perceived. Participants carry only
## what the observer could perceive: an id of "" means unidentified and is never invented.
enum Modality { SIGHT, TOUCH, NOISE, SPOKEN_REPORT, DIRECT_SPEECH }

const MAX_ID_LENGTH: int = 200
const MAX_OBSERVATION_ID_LENGTH: int = 401
const MAX_KIND_LENGTH: int = 64
const MAX_ROLE_LENGTH: int = 64
const MAX_TEXT_LENGTH: int = 500
const MAX_TAGS: int = 16
const MAX_TAG_LENGTH: int = 64
const MAX_PARTICIPANTS: int = 8
const MAX_FACT_KEYS: int = 32
const COMBAT_NOISE_CUE: String = "sounds of fighting"

const _PROTECTED_KINDS: Array[StringName] = [&"actor_died", &"body_found", &"body_reported",
	&"body_buried", &"commitment"]
const _DATA_KEYS: Array[String] = ["observation_id", "origin_id", "incident_id", "observer_id",
	"kind", "modality", "observed_minute", "space_id", "position", "participants", "source_id",
	"text", "topics", "cues", "facts"]
const _FLAG_FACTS: Array[String] = ["player_involved", "directly_affected", "danger_possible", "fatal"]
const _COUNT_FACTS: Array[String] = ["health_remaining", "max_health"]

var observation_id: String = ""
var origin_id: String = ""
var incident_id: String = ""
var observer_id: String = ""
var kind: StringName = &""
var modality: Modality = Modality.SIGHT
var observed_minute: float = 0.0
var space_id: StringName = &""
var has_position: bool = false
var position: Vector2 = Vector2.ZERO
var participants: Array[Dictionary] = []
var source_id: String = ""
var text: String = ""
var topics: Array[String] = []
var cues: Array[String] = []
var facts: Dictionary = {}

func participant_ids() -> Array[String]:
	var ids: Array[String] = []
	for participant: Dictionary in participants:
		var id: Variant = participant.get("id")
		if id is String and not (id as String).is_empty() and not id in ids:
			ids.append(id)
	return ids

func is_protected() -> bool:
	if modality == Modality.NOISE:
		return false
	if modality == Modality.TOUCH and facts.get("directly_affected") == true:
		return true
	if kind in _PROTECTED_KINDS:
		return true
	for participant: Dictionary in participants:
		var id: Variant = participant.get("id")
		if id is String and not (id as String).is_empty() and participant.get("role") == "aggressor":
			return true
	return false

func legacy_sense() -> String:
	match modality:
		Modality.SIGHT:
			return "sight"
		Modality.TOUCH:
			return "touch"
	return "hearing"

func copy() -> NpcObservation:
	var result := NpcObservation.new()
	result.observation_id = observation_id
	result.origin_id = origin_id
	result.incident_id = incident_id
	result.observer_id = observer_id
	result.kind = kind
	result.modality = modality
	result.observed_minute = observed_minute
	result.space_id = space_id
	result.has_position = has_position
	result.position = position
	result.participants = participants.duplicate(true)
	result.source_id = source_id
	result.text = text
	result.topics = topics.duplicate()
	result.cues = cues.duplicate()
	result.facts = facts.duplicate(true)
	return result

## The dictionary shape consumed by the memory store and backend payloads.
func to_event() -> Dictionary:
	var event: Dictionary = {"text": text, "sense": legacy_sense(),
		"player_involved": facts.get("player_involved", false) == true, "kind": String(kind),
		"topics": topics.duplicate(), "participants": participants.duplicate(true),
		"directly_affected": facts.get("directly_affected", false) == true,
		"danger_possible": facts.get("danger_possible", false) == true,
		"origin_id": origin_id, "observation_id": observation_id, "incident_id": incident_id,
		"modality": _modality_name(), "source_id": source_id, "cues": cues.duplicate()}
	for key: String in _COUNT_FACTS:
		if facts.has(key):
			event[key] = facts[key]
	return event

func is_valid() -> bool:
	return from_data(to_data()) != null

## `position` is a Vector2 or null. Unknown evidence stays unknown: no kind, topic or participant
## is defaulted, and an identity is kept only when the legacy dictionary supplied one.
static func from_perception(observer_id: String, origin_id: String, minute: float,
		space_id: StringName, perceived: Dictionary, position: Variant = null) -> NpcObservation:
	if observer_id.is_empty() or origin_id.is_empty() or not is_finite(minute):
		return null
	var kind_name: String = _text(perceived.get("kind"))
	var observation := NpcObservation.new()
	observation.observation_id = "%s:%s" % [observer_id, origin_id]
	observation.origin_id = origin_id
	observation.observer_id = observer_id
	observation.kind = StringName(kind_name) if not kind_name.is_empty() else &"unknown"
	observation.modality = _modality_for(_text(perceived.get("sense")), kind_name)
	observation.observed_minute = minute
	observation.space_id = space_id
	if position is Vector2 and is_finite((position as Vector2).x) and is_finite((position as Vector2).y):
		observation.has_position = true
		observation.position = position
	observation.participants = _perceived_participants(perceived.get("participants"))
	observation.text = _text(perceived.get("text"))
	observation.topics = _tags(perceived.get("topics"))
	if kind_name == "combat_noise":
		observation.cues = [COMBAT_NOISE_CUE]
	if observation.modality in [Modality.SPOKEN_REPORT, Modality.DIRECT_SPEECH]:
		observation.source_id = _speaker_id(observation.participants, perceived.get("source_id"))
	for key: String in _FLAG_FACTS:
		if perceived.get(key) is bool:
			observation.facts[key] = perceived[key]
	for key: String in _COUNT_FACTS:
		if NpcMemory.is_integer(perceived.get(key)):
			observation.facts[key] = int(perceived[key])
	if kind_name == "actor_died":
		observation.facts["fatal"] = true
	return observation if observation.is_valid() else null

func to_data() -> Dictionary:
	return {"observation_id": observation_id, "origin_id": origin_id, "incident_id": incident_id,
		"observer_id": observer_id, "kind": String(kind), "modality": _modality_name(),
		"observed_minute": observed_minute, "space_id": String(space_id),
		"position": [position.x, position.y] if has_position else [],
		"participants": participants.duplicate(true), "source_id": source_id, "text": text,
		"topics": topics.duplicate(), "cues": cues.duplicate(), "facts": facts.duplicate(true)}

static func is_valid_data(data: Variant) -> bool:
	return from_data(data) != null

## Returns null when `data` is not a complete, bounded, JSON-safe observation record.
static func from_data(data: Variant) -> NpcObservation:
	if not data is Dictionary:
		return null
	var source: Dictionary = data
	if source.size() != _DATA_KEYS.size():
		return null
	for key: String in _DATA_KEYS:
		if not source.has(key):
			return null
	for key: String in ["observation_id", "origin_id", "incident_id", "observer_id", "kind",
			"modality", "space_id", "source_id", "text"]:
		if not source[key] is String:
			return null
	var modality_name: String = source["modality"]
	var kind_name: String = source["kind"]
	var observation_id_value: String = source["observation_id"]
	if not Modality.has(modality_name) or observation_id_value.is_empty() \
			or observation_id_value.length() > MAX_OBSERVATION_ID_LENGTH \
			or kind_name.is_empty() or kind_name.length() > MAX_KIND_LENGTH:
		return null
	for key: String in ["origin_id", "observer_id"]:
		if (source[key] as String).is_empty():
			return null
	for key: String in ["origin_id", "incident_id", "observer_id", "space_id", "source_id"]:
		if (source[key] as String).length() > MAX_ID_LENGTH:
			return null
	var text_value: String = source["text"]
	if text_value.is_empty() or text_value.length() > MAX_TEXT_LENGTH:
		return null
	var minute: Variant = source["observed_minute"]
	if not (minute is float or minute is int) or not is_finite(float(minute)):
		return null
	var point: Variant = source["position"]
	if not point is Array or not ((point as Array).is_empty() or ((point as Array).size() == 2
			and _is_number((point as Array)[0]) and _is_number((point as Array)[1]))):
		return null
	var parsed_participants: Variant = _parse_participants(source["participants"])
	if parsed_participants == null:
		return null
	var parsed_topics: Variant = _parse_tags(source["topics"])
	var parsed_cues: Variant = _parse_tags(source["cues"])
	var parsed_facts: Variant = _parse_facts(source["facts"])
	if parsed_topics == null or parsed_cues == null or parsed_facts == null:
		return null
	var resolved_modality: Modality = Modality[modality_name]
	if not (source["source_id"] as String).is_empty() \
			and not resolved_modality in [Modality.SPOKEN_REPORT, Modality.DIRECT_SPEECH]:
		return null
	var observation := NpcObservation.new()
	observation.observation_id = observation_id_value
	observation.origin_id = source["origin_id"]
	observation.incident_id = source["incident_id"]
	observation.observer_id = source["observer_id"]
	observation.kind = StringName(kind_name)
	observation.modality = resolved_modality
	observation.observed_minute = float(minute)
	observation.space_id = StringName(source["space_id"] as String)
	observation.has_position = not (point as Array).is_empty()
	if observation.has_position:
		observation.position = Vector2(float((point as Array)[0]), float((point as Array)[1]))
	observation.participants = parsed_participants
	observation.source_id = source["source_id"]
	observation.text = text_value
	observation.topics = parsed_topics
	observation.cues = parsed_cues
	observation.facts = parsed_facts
	return observation

func _modality_name() -> String:
	var names: Array = Modality.keys()
	return names[modality] if modality >= 0 and modality < names.size() else ""

static func _modality_for(sense: String, kind_name: String) -> Modality:
	if kind_name == "combat_noise" or (sense == "hearing" and kind_name.is_empty()):
		return Modality.NOISE
	if kind_name == "body_reported":
		return Modality.SPOKEN_REPORT
	if kind_name == "conversation" or kind_name == "spoken":
		return Modality.DIRECT_SPEECH
	match sense:
		"touch":
			return Modality.TOUCH
		"sight":
			return Modality.SIGHT
	# Heard or unclassified evidence is anonymous noise rather than an assumed sighting.
	return Modality.NOISE

static func _text(value: Variant) -> String:
	return value if value is String else ""

static func _tags(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for entry: Variant in value:
		if result.size() >= MAX_TAGS:
			break
		if entry is String and not (entry as String).is_empty():
			result.append((entry as String).substr(0, MAX_TAG_LENGTH))
	return result

static func _perceived_participants(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	for entry: Variant in value:
		if result.size() >= MAX_PARTICIPANTS:
			break
		if not entry is Dictionary:
			continue
		var participant: Dictionary = {"id": _text(entry.get("id")).substr(0, MAX_ID_LENGTH),
			"name": _text(entry.get("name")).substr(0, MAX_ID_LENGTH),
			"role": _text(entry.get("role")).substr(0, MAX_ROLE_LENGTH)}
		if entry.has("relationship") and NpcMindState.is_json_safe(entry["relationship"]):
			var relationship: Variant = entry["relationship"]
			participant["relationship"] = relationship.duplicate(true) \
				if relationship is Array or relationship is Dictionary else relationship
		result.append(participant)
	return result

static func _speaker_id(perceived_participants: Array[Dictionary], fallback: Variant) -> String:
	for participant: Dictionary in perceived_participants:
		if participant["role"] in ["reporter", "speaker"] and not (participant["id"] as String).is_empty():
			return participant["id"]
	var id: String = _text(fallback)
	return id if id.length() <= MAX_ID_LENGTH else ""

static func _is_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _parse_participants(value: Variant) -> Variant:
	if not value is Array or (value as Array).size() > MAX_PARTICIPANTS:
		return null
	var result: Array[Dictionary] = []
	for entry: Variant in value:
		if not entry is Dictionary:
			return null
		var participant: Dictionary = entry
		var has_relationship: bool = participant.has("relationship")
		if participant.size() != (4 if has_relationship else 3):
			return null
		for key: String in ["id", "name", "role"]:
			if not participant.get(key) is String:
				return null
		if (participant["id"] as String).length() > MAX_ID_LENGTH \
				or (participant["name"] as String).length() > MAX_ID_LENGTH \
				or (participant["role"] as String).length() > MAX_ROLE_LENGTH:
			return null
		if has_relationship and not NpcMindState.is_json_safe(participant["relationship"]):
			return null
		result.append(participant.duplicate(true))
	return result

static func _parse_tags(value: Variant) -> Variant:
	if not NpcMemory.is_text_list(value, MAX_TAGS):
		return null
	var result: Array[String] = []
	for entry: String in value:
		if entry.is_empty() or entry.length() > MAX_TAG_LENGTH:
			return null
		result.append(entry)
	return result

static func _parse_facts(value: Variant) -> Variant:
	if not value is Dictionary or (value as Dictionary).size() > MAX_FACT_KEYS \
			or not NpcMindState.is_json_safe(value):
		return null
	var result: Dictionary = (value as Dictionary).duplicate(true)
	for key: String in _FLAG_FACTS:
		if result.has(key) and not result[key] is bool:
			return null
	for key: String in _COUNT_FACTS:
		if not result.has(key):
			continue
		if not NpcMemory.is_integer(result[key]) or float(result[key]) < 0.0 \
				or float(result[key]) > 1000000000.0:
			return null
		result[key] = int(result[key])
	return result
