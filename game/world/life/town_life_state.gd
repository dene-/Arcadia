class_name TownLifeState
extends RefCounted

## Save-owned daily life. No scene nodes or provider clients are serialized.
signal time_changed(minute: float)

var minute: float = 480.0:
	set(value):
		minute = value
		time_changed.emit(minute)
var rumors := TownRumors.new()
var _people: Dictionary = {}
var _next_event: int = 1
var _personalities: Dictionary = {}

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

func ensure_person(id: String, seed_value: int, residents: Array[String], places: Array[String]) -> void:
	if not _people.has(id):
		var random := NpcRoutinePlan.random_for(seed_value, id + ":social")
		var ties: Dictionary = {}
		var sorted: Array[String] = residents.duplicate()
		sorted.sort()
		for other: String in sorted:
			if other != id:
				ties[other] = {"familiarity": random.randf_range(0.45, 0.95),
					"trust": random.randf_range(-0.25, 0.65), "affection": random.randf_range(-0.4, 0.7)}
		_people[id] = {"plan_day": -1, "plan": [], "ties": ties,
			"activity": "rest", "place": "home:" + id, "until": minute,
			"social_after": minute + random.randf_range(1, 12), "encounters": 0,
			"position": [], "recent_social": [], "decision": {}, "safety": {}}
	var person: Dictionary = _people[id]
	if person.plan_day != day() or person.get("plan_revision", 0) != NpcRoutinePlan.REVISION:
		person.plan = NpcRoutinePlan.generate(seed_value, id, day(), places)
		person.plan_day = day()
		person.plan_revision = NpcRoutinePlan.REVISION
		if not NpcSafetyState.sheltering(person.safety, minute):
			person.until = minute

func get_person(id: String) -> Dictionary:
	return _people.get(id, {}).duplicate(true)

func select_activity(id: String, activity: Dictionary, duration: float, diagnostic: Dictionary) -> void:
	if not _people.has(id):
		return
	var person: Dictionary = _people[id]
	person.activity = activity.kind
	person.place = activity.place
	person.until = minute + clampf(duration, 5, 120)
	if activity.kind == "shelter" and NpcSafetyState.sheltering(person.safety, minute):
		person.until = minf(person.until, person.safety.until)
	else:
		person.until = minf(person.until, NpcRoutinePlan.next_change(person.plan, minute))
	person.decision = diagnostic.duplicate(true)

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

func remember_exchange(id: String, other: String, text: String, disposition: float = 0.0) -> void:
	var person: Dictionary = _people[id]
	person.recent_social.append({"with": other, "text": text.substr(0, 500), "minute": minute})
	while person.recent_social.size() > 6:
		person.recent_social.pop_front()
	if person.ties.has(other):
		person.ties[other].familiarity = minf(1, person.ties[other].familiarity + 0.02)
		person.ties[other].affection = clampf(person.ties[other].affection + clampf(disposition, -0.04, 0.04), -1, 1)

func to_data() -> Dictionary:
	return {"version": 1, "minute": minute, "next_event": _next_event,
		"people": _people.duplicate(true), "rumors": rumors.to_data(),
		"personalities": _personalities.duplicate(true)}

func from_data(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1:
		return false
	if not _number(data.get("minute")) or data.minute < 0 \
		or not NpcMemory.is_integer(data.get("next_event")) or data.next_event < 1:
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
	_people = data.people.duplicate(true)
	for person: Dictionary in _people.values():
		if not person.has("safety"):
			person.safety = {}
	_personalities = personalities.duplicate(true)
	rumors.from_data(validated.to_data())
	return true

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _valid_person(person: Variant) -> bool:
	if not person is Dictionary:
		return false
	if not NpcSafetyState.is_valid(person.get("safety", {})):
		return false
	if not person.get("space", "outdoors") is String or person.get("space", "outdoors").length() > 200:
		return false
	for key: String in ["plan_day", "encounters"]:
		if not NpcMemory.is_integer(person.get(key)):
			return false
	for key: String in ["until", "social_after"]:
		if not _number(person.get(key)) or person[key] < 0:
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
	if not person.get("ties") is Dictionary or person.ties.size() > 512:
		return false
	for other: Variant in person.ties:
		var tie: Variant = person.ties[other]
		if not other is String or not tie is Dictionary or not NpcMemory.is_unit(tie.get("familiarity")):
			return false
		for key: String in ["trust", "affection"]:
			if not _number(tie.get(key)) or absf(tie[key]) > 1:
				return false
	if not person.get("position") is Array or not person.position.size() in [0, 2]:
		return false
	for coordinate: Variant in person.position:
		if not _number(coordinate):
			return false
	if not person.get("recent_social") is Array or person.recent_social.size() > 6:
		return false
	for entry: Variant in person.recent_social:
		if not entry is Dictionary or not entry.get("with") is String or not entry.get("text") is String \
			or entry.text.length() > 500 or not _number(entry.get("minute")):
			return false
	return person.get("decision") is Dictionary
