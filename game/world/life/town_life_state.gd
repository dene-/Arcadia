class_name TownLifeState
extends RefCounted

## Save-owned daily life. No scene nodes or provider clients are serialized.
signal time_changed(minute: float)

const VERSION: int = 2
const MAX_SEARCHES: int = 64

var minute: float = 480.0:
	set(value):
		minute = value
		time_changed.emit(minute)
var rumors := TownRumors.new()
var _people: Dictionary = {}
var _next_event: int = 1
var _personalities: Dictionary = {}
var _next_social_receipt: int = 1
## Owner of directed relationships; NpcWorldSave shares one instance with NpcMemoryStore.
var minds: NpcMindStore = NpcMindStore.new()

func personality_for(id: String, seed_value: int) -> Dictionary:
	if not _personalities.has(id):
		_personalities[id] = NpcTemperament.generate(seed_value, id)
	NpcTemperament.ensure_voice(_personalities[id], seed_value, id)
	return _personalities[id].duplicate(true)

func advance(minutes: float) -> void:
	minute += maxf(minutes, 0.0)

func day() -> int:
	return floori(minute / 1440.0)

func clock_text() -> String:
	return "Day %d  %02d:%02d" % [day() + 1, int(minute / 60.0) % 24, int(minute) % 60]

func issue_event_id() -> String:
	var id: String = "world:%d" % _next_event
	_next_event += 1
	return id

func ensure_person(id: String, seed_value: int, residents: Array[String], places: Array[String],
		population: TownPopulation = null, dead: Array[String] = []) -> void:
	var relationships: NpcRelationshipGraph = minds.get_mind(id).relationships
	if not _people.has(id):
		var random := NpcRoutinePlan.random_for(seed_value, id + ":social")
		var sorted: Array[String] = residents.duplicate()
		sorted.sort()
		for other: String in sorted:
			if other != id:
				relationships.seed_relationship(other, {"familiarity": random.randf_range(0.45, 0.95),
					"trust": random.randf_range(-0.25, 0.65), "affection": random.randf_range(-0.4, 0.7)})
		_people[id] = {"plan_day": -1, "plan": [],
			"activity": "rest", "place": "home:" + id, "until": minute,
			"social_after": minute + random.randf_range(1, 12), "encounters": 0,
			"position": [], "recent_social": [], "decision": {}, "safety": {}}
	var person: Dictionary = _people[id]
	# An existing save already contains its original relationships. Add only missing neighbors.
	for other: String in residents:
		if other == id or relationships.has_subject(other):
			continue
		var random := NpcRoutinePlan.random_for(seed_value, id + ":tie:" + other)
		relationships.seed_relationship(other, {"familiarity": random.randf_range(0.45, 0.95),
			"trust": random.randf_range(-0.25, 0.65), "affection": random.randf_range(-0.4, 0.7)})
	if population != null and not person.get("family_initialized", false):
		for relative: String in population.people[id].kin:
			var random := NpcRoutinePlan.random_for(seed_value, id + ":family:" + relative)
			relationships.seed_relationship(relative, {"familiarity": 1.0,
				"trust": random.randf_range(0.25, 0.9), "affection": random.randf_range(0.25, 0.95)}, true)
		person.family_initialized = true
	# A guard's shift follows the living watch, so a death reassigns it the same day.
	var shifted: bool = population != null and population.people[id].job == "guard" and not _same_plan(
		TownResidentSchedule.generate(population, id, seed_value, day(), places, dead), person.plan)
	if shifted or person.plan_day != day() or person.get("plan_revision", 0) != NpcRoutinePlan.REVISION:
		person.plan = NpcRoutinePlan.generate(seed_value, id, day(), places) if population == null \
			else TownResidentSchedule.generate(population, id, seed_value, day(), places, dead)
		person.plan_day = day()
		person.plan_revision = NpcRoutinePlan.REVISION
		if not NpcSafetyState.sheltering(person.safety, minute):
			person.until = minute

## Temporary read adapter over the mind store: resident subjects only, three dimensions.
func get_person(id: String) -> Dictionary:
	if not _people.has(id):
		return {}
	var person: Dictionary = _people[id].duplicate(true)
	var ties: Dictionary = {}
	if minds.has_mind(id):
		var relationships: NpcRelationshipGraph = minds.get_mind(id).relationships
		for other: String in relationships.subjects():
			if other == "player":
				continue
			var tie: Dictionary = relationships.get_relationship(other)
			ties[other] = {"familiarity": tie.familiarity, "trust": tie.trust, "affection": tie.affection}
	person.ties = ties
	return person

## `since` records when the activity or place last changed: how long the current goal has run.
func select_activity(id: String, activity: Dictionary, duration: float, diagnostic: Dictionary) -> void:
	if not _people.has(id):
		return
	var person: Dictionary = _people[id]
	if person.activity != activity.kind or person.place != activity.place or not person.has("since"):
		person.since = minute
	person.activity = activity.kind
	person.place = activity.place
	person.until = minute + clampf(duration, 5, 120)
	if activity.kind == "shelter" and NpcSafetyState.sheltering(person.safety, minute):
		person.until = minf(person.until, person.safety.until)
	else:
		person.until = minf(person.until, NpcRoutinePlan.next_change(person.plan, minute))
	person.decision = diagnostic.duplicate(true)

## Progress of the search a commitment asks for: {step: index of the place being searched,
## deferred_until: minute before which the search is not resumed}.
func search_for(id: String, commitment_id: String) -> Dictionary:
	var searches: Dictionary = _people.get(id, {}).get("searches", {})
	var search: Dictionary = searches.get(commitment_id, {"step": 0, "deferred_until": 0.0})
	return {"step": int(search.step), "deferred_until": float(search.deferred_until)}

func set_search(id: String, commitment_id: String, step: int, deferred_until: float) -> void:
	if not _people.has(id):
		return
	var searches: Dictionary = _people[id].get("searches", {})
	if not searches.has(commitment_id) and searches.size() >= MAX_SEARCHES:
		return
	searches[commitment_id] = {"step": maxi(step, 0), "deferred_until": maxf(deferred_until, 0.0)}
	_people[id].searches = searches

## Forgets a finished search.
func end_search(id: String, commitment_id: String) -> void:
	if _people.has(id) and _people[id].has("searches"):
		_people[id].searches.erase(commitment_id)

func notice_perception(id: String, event: Dictionary, space: String) -> void:
	if _people.has(id):
		_set_safety(id, NpcSafetyState.notice(_people[id].safety, event, space, minute))

func assess_perception(id: String, event: Dictionary, policy: Dictionary) -> void:
	if _people.has(id):
		_set_safety(id, NpcSafetyState.assess(_people[id].safety, event, policy, minute))

func _set_safety(id: String, concern: Dictionary) -> void:
	if _people[id].safety != concern:
		_people[id].safety = concern.duplicate(true)
		interrupt(id)

func remember_position(id: String, position: Vector2, space: String = "outdoors") -> void:
	if _people.has(id):
		_people[id].position = [position.x, position.y]
		_people[id].space = space

func interrupt(id: String) -> void:
	if _people.has(id):
		_people[id].until = minute

func reserve_encounter(id: String, seed_value: int) -> void:
	var person: Dictionary = _people[id]
	person.encounters += 1
	var random := NpcRoutinePlan.random_for(seed_value, "%s:meeting:%s" % [id, person.encounters])
	person.social_after = minute + random.randf_range(35, 85)

## Records a delivered line of session `session_id` in `id`'s social history.
func remember_exchange(id: String, other: String, text: String, session_id: String,
		speaker_id: String, listener_id: String) -> void:
	var person: Dictionary = _people[id]
	person.recent_social.append({"with": other, "text": text.substr(0, 500), "minute": minute,
		"session_id": session_id, "speaker_id": speaker_id, "listener_id": listener_id,
		"delivered": true})
	while person.recent_social.size() > 6:
		person.recent_social.pop_front()
	var receipt: String = "social:%s:%s:%d" % [id, other, _next_social_receipt]
	_next_social_receipt += 1
	var relationships: NpcRelationshipGraph = minds.get_mind(id).relationships
	if relationships.has_subject(other):
		relationships.apply_delta(other, {"familiarity": 0.02}, receipt)

func to_data() -> Dictionary:
	return {"version": VERSION, "minute": minute, "next_event": _next_event,
		"next_social_receipt": _next_social_receipt,
		"people": _people.duplicate(true), "rumors": rumors.to_data(),
		"personalities": _personalities.duplicate(true)}

func from_data(data: Variant) -> bool:
	if not data is Dictionary or not NpcMemory.is_integer(data.get("version")) \
		or int(data.version) != VERSION:
		return false
	if not _number(data.get("minute")) or data.minute < 0 \
		or not NpcMemory.is_integer(data.get("next_event")) or data.next_event < 1 \
		or not NpcMemory.is_integer(data.get("next_social_receipt")) or data.next_social_receipt < 1:
		return false
	if not data.get("people") is Dictionary or data.people.size() > 512:
		return false
	for id: Variant in data.people:
		if not id is String or id.is_empty() or not _valid_person(data.people[id]):
			return false
	var validated := TownRumors.new()
	if not validated.from_data(data.get("rumors")):
		return false
	var personalities: Variant = data.get("personalities", {})
	if not personalities is Dictionary or personalities.size() > 512:
		return false
	for id: Variant in personalities:
		if not id is String or not NpcTemperament.is_valid(personalities[id]):
			return false
	minute = float(data.minute)
	_next_event = int(data.next_event)
	_next_social_receipt = int(data.next_social_receipt)
	_people = data.people.duplicate(true)
	_personalities = personalities.duplicate(true)
	rumors.from_data(validated.to_data())
	return true

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

# Saved plans come back from JSON with float minutes; compare slots by value.
static func _same_plan(expected: Array[Dictionary], actual: Array) -> bool:
	if expected.size() != actual.size():
		return false
	for index: int in range(expected.size()):
		var slot: Dictionary = expected[index]
		if not actual[index] is Dictionary or float(actual[index].get("minute", -1)) != float(slot.minute) \
			or actual[index].get("kind") != slot.kind or actual[index].get("place") != slot.place:
			return false
	return true

static func _valid_person(person: Variant) -> bool:
	if not person is Dictionary:
		return false
	if person.has("family_initialized") and not person.family_initialized is bool:
		return false
	if person.has("ties") or not person.get("safety") is Dictionary \
		or not NpcSafetyState.is_valid(person.safety):
		return false
	if not person.get("space", "outdoors") is String or person.get("space", "outdoors").length() > 200:
		return false
	for key: String in ["plan_day", "encounters"]:
		if not NpcMemory.is_integer(person.get(key)):
			return false
	for key: String in ["until", "social_after"]:
		if not _number(person.get(key)) or person[key] < 0:
			return false
	if person.has("since") and (not _number(person.since) or person.since < 0):
		return false
	if not _valid_searches(person.get("searches", {})):
		return false
	for key: String in ["activity", "place"]:
		if not person.get(key) is String or person[key].length() > 200:
			return false
	if not person.get("plan") is Array or person.plan.is_empty() or person.plan.size() > 16:
		return false
	var previous: float = -1
	for slot: Variant in person.plan:
		if not slot is Dictionary or not _number(slot.get("minute")) or slot.minute <= previous \
			or slot.minute >= 1440 or not slot.get("kind") is String or not slot.get("place") is String:
			return false
		previous = slot.minute
	if not person.get("position") is Array or not person.position.size() in [0, 2]:
		return false
	for coordinate: Variant in person.position:
		if not _number(coordinate):
			return false
	if not person.get("recent_social") is Array or person.recent_social.size() > 6:
		return false
	for entry: Variant in person.recent_social:
		if not entry is Dictionary or not entry.get("with") is String or not entry.get("text") is String \
			or entry.text.length() > 500 or not _number(entry.get("minute")) \
			or not entry.get("speaker_id") is String or not entry.get("listener_id") is String \
			or not NpcMemoryStore.is_valid_session_entry(entry):
			return false
	return person.get("decision") is Dictionary

# Optional search progress per commitment id (absent in older saves).
static func _valid_searches(searches: Variant) -> bool:
	if not searches is Dictionary or searches.size() > MAX_SEARCHES:
		return false
	for commitment_id: Variant in searches:
		var search: Variant = searches[commitment_id]
		if not commitment_id is String or commitment_id.length() > 200 or not search is Dictionary \
			or search.size() != 2 or not NpcMemory.is_integer(search.get("step")) or search.step < 0 \
			or not _number(search.get("deferred_until")) or search.deferred_until < 0:
			return false
	return true
