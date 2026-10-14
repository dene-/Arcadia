class_name NpcCognitiveContext
extends RefCounted

## A bounded view of working memory, separate from saved diagnostics and the archive.
const WORKING_MEMORY_MINUTES: float = 180.0
const LEGACY_WORKING_MEMORY_SECONDS: float = 120.0
const MAX_CONCERNS: int = 3
## Felt emotion causes carried into context (strongest first).
const MAX_EMOTION_CAUSES: int = 3
## Task kinds that are the resident's duty rather than ordinary routine.
const DUTY_TASKS: Array[String] = ["guard", "recovery"]

## Consumers of `for_consumer`: player dialogue, spontaneous reactions to perceived events,
## NPC-to-NPC speech and routine goal selection.
const DIALOGUE: StringName = &"dialogue"
const REACTION: StringName = &"reaction"
const SOCIAL: StringName = &"social"
const DECISION: StringName = &"decision"
## Facts every consumer sees: identity and voice, the clock, what the resident is doing and
## where, its own condition, feelings, grief and commitments, kin, neighbors (public facts
## only) and its relationships to the consumer's participants.
const SHARED_KEYS: Array[String] = ["world_time", "world_minute", "world_space", "location",
	"activity", "interrupted_activity", "destination", "traveling", "sleeping", "recently_awakened",
	"wake_reason", "alert_phase", "physical_state", "sensory_cues", "current_task", "personality",
	"safety_response", "condition", "emotion_causes", "personal_concerns", "open_commitments",
	"family_members", "known_townspeople", "relationships"]
## Consumer-specific additions. A reaction sees a subset of what dialogue sees, so projecting a
## dialogue context for a reaction gives the reaction context.
const CONSUMER_KEYS: Dictionary[StringName, Array] = {
	DIALOGUE: ["player_identity", "household", "household_economy", "town_rumors", "known_deaths",
		"enforcement", "recent_social", "recent_ambient"],
	REACTION: ["player_identity", "known_deaths", "enforcement", "recent_ambient"],
	SOCIAL: ["household", "town_rumors", "known_deaths", "recent_social", "recent_ambient"],
	DECISION: ["household", "household_economy", "known_deaths", "enforcement"],
}
## What a consumer learns of the current task: its kind, phase and the activity it serves.
const TASK_KEYS: Array[String] = ["kind", "phase", "activity", "label"]

## The whitelisted view of `facts` (BaseNpc's full context) for `consumer`. Private diagnostics,
## the full daily plan and anything not listed never reach a consumer; neighbors keep only
## public facts, and relationships come solely from `facts.relationships` (participant id ->
## relationship-graph value). An unknown consumer gets {}.
static func for_consumer(consumer: StringName, facts: Dictionary) -> Dictionary:
	if not CONSUMER_KEYS.has(consumer):
		return {}
	var result: Dictionary = {}
	for key: String in SHARED_KEYS + CONSUMER_KEYS[consumer]:
		if facts.has(key):
			result[key] = facts[key].duplicate(true) \
				if facts[key] is Dictionary or facts[key] is Array else facts[key]
	if result.get("current_task") is Dictionary:
		var task: Dictionary = {}
		for key: String in TASK_KEYS:
			if result.current_task.has(key):
				task[key] = result.current_task[key]
		result.current_task = task
	if result.get("known_townspeople") is Array:
		for person: Variant in result.known_townspeople:
			if person is Dictionary:
				(person as Dictionary).erase("relationship")
	return result

## The resident's own unresolved state for `get_cognitive_context`: grief (`personal_concerns`)
## and open commitments (`open_commitments`, with the evidence they rest on). Given the world
## `minute`, also its semantic `condition` bands (needs, emotions and, with the `actor`, pain) and
## the `emotion_causes` still felt, with the subject and evidence each rests on.
static func mind_context(mind: NpcMindState, minute: float = NAN, actor: Object = null) -> Dictionary:
	var personal: Array[Dictionary] = []
	var concerns: Variant = mind.condition.get("concerns", [])
	for concern: Variant in concerns if concerns is Array else []:
		if concern is Dictionary and concern.get("kind") == "bereavement" \
				and concern.get("subject") is String and (concern.get("minute") is float or concern.get("minute") is int):
			personal.append({"kind": "bereavement", "subject": concern["subject"],
				"minute": float(concern["minute"])})
	var commitments: Array[Dictionary] = []
	for item: Dictionary in mind.commitments.open_commitments():
		commitments.append({"id": item["id"], "kind": item["kind"], "other_ids": item["other_ids"],
			"evidence_ids": item["evidence_ids"], "deadline_minute": item["deadline_minute"],
			"priority": item["priority"]})
	var result: Dictionary = {"personal_concerns": personal, "open_commitments": commitments}
	if not is_finite(minute):
		return result
	var condition: Dictionary = mind.condition_band(minute)
	if actor != null:
		condition["pain"] = NpcMindState.pain_band(NpcMindState.pain_of(actor), mind.tuning)
	var causes: Array[Dictionary] = []
	for cause: Dictionary in mind.emotion_causes(minute).slice(0, MAX_EMOTION_CAUSES):
		causes.append({"emotion": cause["emotion"],
			"band": NpcMindState.emotion_band(float(cause["intensity"]), mind.tuning),
			"subject": cause["subject"], "evidence_id": cause["evidence_id"],
			"incident_id": cause["incident_id"]})
	result["condition"] = condition
	result["emotion_causes"] = causes
	return result

## Concerns, at most MAX_CONCERNS, in this order: a personal injury, recent personally relevant
## observations (newest first), strong feelings (strongest first), bereavements (newest first),
## the current duty, open commitments (highest priority first). Relevance comes from the player,
## the resident itself, or a subject of its feelings, grief, family or commitments;
## `player_involved` is not required. Semantic `condition` bands pass through unchanged.
static func build(state: Dictionary, current: Dictionary) -> Dictionary:
	var result: Dictionary = current.duplicate(true)
	result.erase("personal_concerns")
	result.erase("open_commitments")
	result.erase("emotion_causes")
	result.recent_events = state.recent_events.duplicate()
	result.participants = ["player"]
	var past: Array[Dictionary] = []
	var subjects: Dictionary[String, bool] = _personal_subjects(current)
	var concerns: Array[Dictionary] = []
	var observed: Array[Dictionary] = []
	for record: Dictionary in state.observations:
		var view: Dictionary = _observation_view(record, current)
		if view.is_empty():
			continue
		past.append(view)
		var personal_injury: bool = view.sense == "touch" and current.get("physical_state") == "injured"
		if not personal_injury and not (view.recent and _is_personal(record, subjects)):
			continue
		var concern: Dictionary = view.duplicate()
		concern.kind = "observation"
		(concerns if personal_injury else observed).append(concern)
	result.past_observations = past
	var by_age: Callable = func(a: Dictionary, b: Dictionary) -> bool:
		return _relative_age(a) < _relative_age(b)
	concerns.sort_custom(by_age)
	observed.sort_custom(by_age)
	concerns.append_array(observed)
	concerns.append_array(_feelings(current))
	concerns.append_array(_bereavements(current))
	var duty: Dictionary = _duty(current)
	if not duty.is_empty():
		concerns.append(duty)
	concerns.append_array(_commitments(current))
	result.current_concerns = concerns.slice(0, MAX_CONCERNS)
	return result

static func observations(records: Array, current: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in records:
		var view: Dictionary = _observation_view(record, current)
		if not view.is_empty():
			result.append(view)
	return result

# {} when the record has left working memory.
static func _observation_view(record: Dictionary, current: Dictionary) -> Dictionary:
	var seconds: float = maxf(0.0, Time.get_unix_time_from_system() - record.created_at)
	var recent: bool = seconds <= LEGACY_WORKING_MEMORY_SECONDS
	var elapsed_minutes: float = -1.0
	if record.has("world_minute") and current.has("world_minute"):
		elapsed_minutes = maxf(0.0, float(current.world_minute) - float(record.world_minute))
		recent = elapsed_minutes <= WORKING_MEMORY_MINUTES
	var ongoing_injury: bool = record.sense == "touch" and current.get("physical_state") == "injured"
	if not recent and not ongoing_injury:
		return {}
	var view: Dictionary = {"text": record.text, "sense": record.sense,
		"player_involved": record.player_involved, "recent": recent, "assessment": record.status}
	if elapsed_minutes >= 0.0:
		view["age_game_minutes"] = elapsed_minutes
	else:
		view["age_seconds"] = seconds
	return view

static func _is_personal(record: Dictionary, subjects: Dictionary[String, bool]) -> bool:
	if record.player_involved or record.get("directly_affected") == true:
		return true
	var participants: Variant = record.get("participants", [])
	for participant: Variant in participants if participants is Array else []:
		if participant is Dictionary and participant.get("id") is String \
				and subjects.has(participant["id"]):
			return true
	return false

static func _personal_subjects(current: Dictionary) -> Dictionary[String, bool]:
	var subjects: Dictionary[String, bool] = {}
	for concern: Dictionary in _list(current, "personal_concerns"):
		if concern.get("subject") is String:
			subjects[concern["subject"]] = true
	for relative: Dictionary in _list(current, "family_members"):
		if relative.get("id") is String:
			subjects[relative["id"]] = true
	for item: Dictionary in _list(current, "open_commitments"):
		var others: Variant = item.get("other_ids", [])
		for other: Variant in others if others is Array else []:
			if other is String:
				subjects[other] = true
	for cause: Dictionary in _list(current, "emotion_causes"):
		if cause.get("subject") is String:
			subjects[cause["subject"]] = true
	subjects.erase("")
	return subjects

# Strong feelings with their subject; grief for a known bereavement is that concern instead.
static func _feelings(current: Dictionary) -> Array[Dictionary]:
	var mourned: Dictionary[String, bool] = {}
	for concern: Dictionary in _list(current, "personal_concerns"):
		if concern.get("kind") == "bereavement" and concern.get("subject") is String:
			mourned[concern["subject"]] = true
	var result: Array[Dictionary] = []
	for cause: Dictionary in _list(current, "emotion_causes"):
		var subject: String = String(cause.get("subject", ""))
		if cause.get("band") != "strong" or not cause.get("emotion") is String \
				or (cause["emotion"] == "grief" and mourned.has(subject)):
			continue
		var entry: Dictionary = {"kind": "feeling", "emotion": cause["emotion"], "band": "strong"}
		if not subject.is_empty():
			var name: String = _name_of(current, subject)
			entry["subject"] = name if not name.is_empty() else subject
		result.append(entry)
	return result

static func _bereavements(current: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for concern: Dictionary in _list(current, "personal_concerns"):
		if concern.get("kind") != "bereavement" or not concern.get("subject") is String:
			continue
		var entry: Dictionary = {"kind": "bereavement", "subject": concern["subject"]}
		var name: String = _name_of(current, concern["subject"])
		if not name.is_empty():
			entry["name"] = name
		for relative: Dictionary in _list(current, "family_members"):
			if relative.get("id") == concern["subject"] and relative.get("relationship") is String:
				entry["relationship"] = relative["relationship"]
		if current.has("world_minute") and concern.get("minute") is float:
			entry["age_game_minutes"] = maxf(0.0, float(current.world_minute) - float(concern["minute"]))
		result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("age_game_minutes", 0.0)) < float(b.get("age_game_minutes", 0.0)))
	return result

static func _duty(current: Dictionary) -> Dictionary:
	var task: Variant = current.get("current_task", {})
	if not task is Dictionary or not String(task.get("kind", "")) in DUTY_TASKS:
		return {}
	return {"kind": "duty", "task": task["kind"], "phase": task.get("phase", ""),
		"activity": task.get("activity", ""), "label": task.get("label", "")}

static func _commitments(current: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in _list(current, "open_commitments"):
		if not item.get("kind") is String:
			continue
		var subjects: Array[String] = []
		var others: Variant = item.get("other_ids", [])
		for other: Variant in others if others is Array else []:
			if other is String:
				var name: String = _name_of(current, other)
				subjects.append(name if not name.is_empty() else other)
		result.append({"kind": "commitment", "commitment": item["kind"], "subjects": subjects,
			"priority": float(item.get("priority", 0.0))})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.priority > b.priority)
	return result

static func _name_of(current: Dictionary, id: String) -> String:
	for key: String in ["family_members", "known_townspeople"]:
		for person: Dictionary in _list(current, key):
			if person.get("id") == id and person.get("name") is String:
				return person["name"]
	return ""

# Dictionary entries of an optional context list.
static func _list(current: Dictionary, key: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var items: Variant = current.get(key, [])
	for item: Variant in items if items is Array else []:
		if item is Dictionary:
			result.append(item)
	return result

static func _relative_age(observed: Dictionary) -> float:
	if observed.has("age_game_minutes"):
		return float(observed.age_game_minutes) / WORKING_MEMORY_MINUTES
	return float(observed.age_seconds) / LEGACY_WORKING_MEMORY_SECONDS
