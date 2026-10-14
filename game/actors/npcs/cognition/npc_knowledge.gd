class_name NpcKnowledge
extends RefCounted

## One resident's personal beliefs: attributed facts with provenance, never the live world state.
## Read methods return copies. Repeating an origin is not corroboration; conflicts stay visible.
enum Status { OBSERVED, REPORTED, INFERRED, CONTESTED, SUPERSEDED }

const MAX_FACTS: int = 1024
const MAX_REFS: int = 64
const MAX_TEXT: int = 200
const MAX_VALUE_CHARS: int = 2000
const PUBLIC_SOURCE: String = "public"
const SELF_SOURCE: String = "self"
const PUBLIC_PLACE_IDS: Array[String] = ["square", "market", "garden", "school", "playground"]
## Predicates whose differing values are independent members of a set, not rival beliefs.
const SET_PREDICATES: Array[String] = ["help_place"]
const _FACT_KEYS: Array[String] = ["id", "subject", "predicate", "value", "status", "source_id",
	"evidence_ids", "origin_ids", "observed_minute", "recorded_minute", "source_confidence"]
const _OBSERVED: String = "OBSERVED"
const _REPORTED: String = "REPORTED"
const _CONTESTED: String = "CONTESTED"
const _SUPERSEDED: String = "SUPERSEDED"

var version: int = 0

var _next_id: int = 1
var _facts: Array[Dictionary] = []

func record(subject: String, predicate: String, value: Variant, status: Status, source_id: String,
		evidence_id: String, origin_id: String, minute: float, source_confidence: float) -> bool:
	if not status in [Status.OBSERVED, Status.REPORTED, Status.INFERRED] \
			or not _is_valid_input(subject, predicate, value, source_id, evidence_id, origin_id,
			minute, source_confidence):
		return false
	var status_name: String = Status.keys()[status]
	var normalized: Variant = _normalize(value)
	var scope: Array[int] = _current_indices(subject, predicate)
	var is_set: bool = predicate in SET_PREDICATES
	var same: int = -1
	for index: int in scope:
		if _facts[index]["value"] == normalized:
			same = index
			break
	if not origin_id.is_empty():
		for index: int in scope:
			if (not is_set or index == same) and origin_id in _facts[index]["origin_ids"]:
				return false
	if same >= 0:
		_corroborate(same, status_name, evidence_id, origin_id, minute)
		return true
	var supersede: Array[int] = []
	var contest: Array[int] = []
	var new_status: String = status_name
	if is_set:
		pass
	elif status == Status.OBSERVED:
		if not scope.is_empty() and minute < _newest_minute(scope):
			new_status = _SUPERSEDED
		else:
			supersede = scope
	else:
		if predicate == "location" and status == Status.REPORTED:
			var own: Array[int] = _same_source_reports(scope, source_id)
			for index: int in own:
				if float(_facts[index]["observed_minute"]) > minute:
					new_status = _SUPERSEDED
			if new_status != _SUPERSEDED:
				var kept: Array[int] = []
				for index: int in scope:
					if index in own and float(_facts[index]["observed_minute"]) < minute:
						supersede.append(index)
					else:
						kept.append(index)
				scope = kept
		if new_status != _SUPERSEDED and not scope.is_empty():
			new_status = _CONTESTED
			if not _has_observed_at_or_after(scope, minute):
				contest = scope
	# A superseded own sighting is dropped, not kept as history: it is the only fact that grows
	# with every minute a resident watches someone.
	var own_sighting: bool = predicate == "location" and status == Status.OBSERVED \
		and source_id == SELF_SOURCE
	if own_sighting and new_status == _SUPERSEDED:
		return false
	var discard: Array[int] = []
	if own_sighting:
		var superseded_elsewhere: Array[int] = []
		for index: int in supersede:
			if _facts[index]["source_id"] == SELF_SOURCE:
				discard.append(index)
			else:
				superseded_elsewhere.append(index)
		supersede = superseded_elsewhere
	var eviction: int = -1
	if source_id != PUBLIC_SOURCE and _personal_count() - discard.size() >= MAX_FACTS:
		eviction = _eviction_index(supersede)
		if eviction < 0:
			return false
	for index: int in supersede:
		_facts[index]["status"] = _SUPERSEDED
	for index: int in contest:
		_facts[index]["status"] = _CONTESTED
	discard.sort()
	discard.reverse()
	for index: int in discard:
		_facts.remove_at(index)
	if eviction >= 0:
		_facts.remove_at(eviction)
	_facts.append(_new_fact(subject, predicate, normalized, new_status, source_id, evidence_id,
		origin_id, minute, source_confidence))
	version += 1
	return true

func current(subject: String, predicate: String) -> Array[Dictionary]:
	var indices: Array[int] = _current_indices(subject, predicate)
	indices.sort_custom(func(a: int, b: int) -> bool:
		var left: float = _facts[a]["observed_minute"]
		var right: float = _facts[b]["observed_minute"]
		return a > b if left == right else left > right)
	var result: Array[Dictionary] = []
	for index: int in indices:
		result.append(_facts[index].duplicate(true))
	return result

func knows(subject: String, predicate: String) -> bool:
	return not _current_indices(subject, predicate).is_empty()

func known_locations(subject_id: String) -> Array[Dictionary]:
	return current(subject_id, "location")

func record_sighting(subject_id: String, space_id: String, position: Vector2, minute: float,
		evidence_id: String) -> bool:
	if not is_finite(minute):
		return false
	return record(subject_id, "location", {"space": space_id, "x": position.x, "y": position.y},
		Status.OBSERVED, SELF_SOURCE, evidence_id,
		"sighting:%s:%d" % [subject_id, int(minute * 10.0)], minute, 1.0)

func record_report(subject_id: String, predicate: String, value: Variant, source_id: String,
		origin_id: String, evidence_id: String, minute: float, confidence: float) -> bool:
	return record(subject_id, predicate, value, Status.REPORTED, source_id, evidence_id,
		origin_id, minute, confidence)

func known_help_places() -> Array[Dictionary]:
	return current("town", "help_place")

func known_places() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for fact: Dictionary in _facts:
		if fact["predicate"] == "familiar_place" and fact["status"] != _SUPERSEDED:
			result.append(fact.duplicate(true))
	return result

## The newest personal (non-public) beliefs still held, at most `limit`, newest first. Copies.
func newest_personal(limit: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(_facts.size() - 1, -1, -1):
		if result.size() >= limit:
			break
		var fact: Dictionary = _facts[index]
		if fact["source_id"] != PUBLIC_SOURCE and fact["status"] != _SUPERSEDED:
			result.append(fact.duplicate(true))
	return result

## `people` has TownPopulation.people's shape; `places` maps id -> {label, space?, position: Vector2}.
## Only stable public facts are recorded: never live positions, deaths, emotions or balances.
func bootstrap_public(npc_id: String, people: Dictionary, places: Dictionary,
		guard_ids: Array[String]) -> void:
	for person_id: Variant in people:
		var person: Variant = people[person_id]
		if not person_id is String or not person is Dictionary:
			continue
		var display_name: Variant = person.get("name")
		var job: Variant = person.get("job")
		var household: Variant = person.get("household")
		if display_name is String and job is String and household is String:
			_public(person_id, "identity", {"name": display_name, "job": job, "household": household})
	var relatives: Array[String] = []
	var own: Variant = people.get(npc_id)
	if own is Dictionary and own.get("kin") is Dictionary:
		var kin: Dictionary = own["kin"]
		for other_id: Variant in kin:
			if other_id is String and kin[other_id] is String:
				relatives.append(other_id)
				_public(other_id, "family_role", kin[other_id])
	var familiar: Array[String] = ["home:" + npc_id, "work:" + npc_id]
	for relative: String in relatives:
		familiar.append("home:" + relative)
	for place_id: Variant in places:
		if place_id is String and (place_id in PUBLIC_PLACE_IDS or place_id.begins_with("patrol:")):
			familiar.append(place_id)
	for place_id: String in familiar:
		var place: Dictionary = _place_value(places, place_id)
		if not place.is_empty():
			_public(place_id, "familiar_place", {"label": place["label"], "space": place["space"],
				"x": place["x"], "y": place["y"]})
	for guard_id: String in guard_ids:
		_public_help(places, "home:" + guard_id, "guard_home")
	for place_id: Variant in places:
		if place_id is String and place_id.begins_with("patrol:"):
			_public_help(places, place_id, "patrol_point")

## Public facts are not saved: bootstrap_public re-derives them from population and places, so call
## it after from_data (which replaces every fact). Capacity counts personal facts only.
func to_data() -> Dictionary:
	var facts: Array = []
	for fact: Dictionary in _facts:
		if fact["source_id"] != PUBLIC_SOURCE:
			facts.append(fact.duplicate(true))
	return {"next_id": _next_id, "facts": facts}

static func is_valid_data(data: Variant) -> bool:
	return not _parse(data).is_empty()

func from_data(data: Variant) -> bool:
	var parsed: Dictionary = _parse(data)
	if parsed.is_empty():
		return false
	_next_id = parsed["next_id"]
	_facts = parsed["facts"]
	version += 1
	return true

func _public(subject: String, predicate: String, value: Variant, origin_suffix: String = "") -> void:
	var origin: String = "public:%s:%s%s" % [subject, predicate, origin_suffix]
	record(subject, predicate, value, Status.OBSERVED, PUBLIC_SOURCE, origin, origin, 0.0, 1.0)

func _public_help(places: Dictionary, place_id: String, kind: String) -> void:
	var place: Dictionary = _place_value(places, place_id)
	if not place.is_empty():
		_public("town", "help_place", {"place": place_id, "space": place["space"],
			"x": place["x"], "y": place["y"], "kind": kind}, ":" + place_id)

static func _place_value(places: Dictionary, place_id: String) -> Dictionary:
	var place: Variant = places.get(place_id)
	if not place is Dictionary or not place.get("position") is Vector2:
		return {}
	var position: Vector2 = place["position"]
	var label: Variant = place.get("label", "")
	var space: Variant = place.get("space", "outdoors")
	if not label is String or not space is String or (space as String).is_empty():
		return {}
	return {"label": label, "space": space, "x": position.x, "y": position.y}

func _corroborate(index: int, status_name: String, evidence_id: String, origin_id: String,
		minute: float) -> void:
	var fact: Dictionary = _facts[index]
	_append_ref(fact["evidence_ids"], evidence_id)
	_append_ref(fact["origin_ids"], origin_id)
	if status_name == _OBSERVED:
		fact["status"] = _OBSERVED
	fact["observed_minute"] = maxf(float(fact["observed_minute"]), minute)
	fact["recorded_minute"] = maxf(float(fact["recorded_minute"]), minute)
	version += 1

static func _append_ref(refs: Array, ref: String) -> void:
	if ref.is_empty() or ref in refs:
		return
	if refs.size() >= MAX_REFS:
		refs.remove_at(0)
	refs.append(ref)

func _new_fact(subject: String, predicate: String, value: Variant, status_name: String,
		source_id: String, evidence_id: String, origin_id: String, minute: float,
		confidence: float) -> Dictionary:
	var evidence: Array[String] = []
	var origins: Array[String] = []
	_append_ref(evidence, evidence_id)
	_append_ref(origins, origin_id)
	var fact: Dictionary = {"id": "fact:%d" % _next_id, "subject": subject,
		"predicate": predicate, "value": value, "status": status_name, "source_id": source_id,
		"evidence_ids": evidence, "origin_ids": origins, "observed_minute": minute,
		"recorded_minute": minute, "source_confidence": confidence}
	_next_id += 1
	return fact

func _current_indices(subject: String, predicate: String) -> Array[int]:
	var result: Array[int] = []
	for index: int in _facts.size():
		var fact: Dictionary = _facts[index]
		if fact["subject"] == subject and fact["predicate"] == predicate \
				and fact["status"] != _SUPERSEDED:
			result.append(index)
	return result

func _same_source_reports(indices: Array[int], source_id: String) -> Array[int]:
	var result: Array[int] = []
	for index: int in indices:
		if _facts[index]["source_id"] == source_id and _facts[index]["status"] in [_REPORTED, _CONTESTED]:
			result.append(index)
	return result

func _newest_minute(indices: Array[int]) -> float:
	var newest: float = 0.0
	for index: int in indices:
		newest = maxf(newest, float(_facts[index]["observed_minute"]))
	return newest

func _has_observed_at_or_after(indices: Array[int], minute: float) -> bool:
	for index: int in indices:
		if _facts[index]["status"] == _OBSERVED and float(_facts[index]["observed_minute"]) >= minute:
			return true
	return false

# Capacity counts personal facts only: public ones are runtime-only and not saved.
func _personal_count() -> int:
	var count: int = 0
	for fact: Dictionary in _facts:
		if fact["source_id"] != PUBLIC_SOURCE:
			count += 1
	return count

# Oldest superseded personal fact (including ones about to be), else the oldest personal fact.
func _eviction_index(about_to_supersede: Array[int]) -> int:
	var best: int = -1
	for index: int in _facts.size():
		if _facts[index]["source_id"] == PUBLIC_SOURCE:
			continue
		if _facts[index]["status"] == _SUPERSEDED or index in about_to_supersede:
			if best < 0 or float(_facts[index]["observed_minute"]) < float(_facts[best]["observed_minute"]):
				best = index
	if best >= 0:
		return best
	for index: int in _facts.size():
		if _facts[index]["source_id"] != PUBLIC_SOURCE:
			if best < 0 or float(_facts[index]["observed_minute"]) < float(_facts[best]["observed_minute"]):
				best = index
	return best

static func _normalize(value: Variant) -> Variant:
	if value is int:
		return float(value)
	if value is Array:
		var items: Array = []
		for entry: Variant in value:
			items.append(_normalize(entry))
		return items
	if value is Dictionary:
		var copy: Dictionary = {}
		for key: Variant in value:
			copy[key] = _normalize(value[key])
		return copy
	return value

static func _is_valid_input(subject: String, predicate: String, value: Variant, source_id: String,
		evidence_id: String, origin_id: String, minute: float, confidence: float) -> bool:
	return _is_label(subject) and _is_label(predicate) and source_id.length() <= MAX_TEXT \
		and evidence_id.length() <= MAX_TEXT and origin_id.length() <= MAX_TEXT \
		and is_finite(minute) and minute >= 0.0 and NpcMemory.is_unit(confidence) \
		and _is_valid_value(predicate, value)

static func _is_label(text: String) -> bool:
	return not text.is_empty() and text.length() <= MAX_TEXT

static func _is_valid_value(predicate: String, value: Variant) -> bool:
	if not NpcMindState.is_json_safe(value) or JSON.stringify(value).length() > MAX_VALUE_CHARS:
		return false
	match predicate:
		"location":
			return _has_shape(value, ["space", "x", "y"], ["place"])
		"help_place":
			return _has_shape(value, ["place", "space", "x", "y", "kind"], [])
	return true

static func _has_shape(value: Variant, required: Array[String], optional: Array[String]) -> bool:
	if not value is Dictionary:
		return false
	var source: Dictionary = value
	for key: Variant in source:
		if not key in required and not key in optional:
			return false
	for key: String in required:
		if not source.has(key):
			return false
		var entry: Variant = source[key]
		if key == "x" or key == "y":
			if not (entry is int or entry is float) or not is_finite(float(entry)):
				return false
		elif not entry is String or (entry as String).is_empty() or (entry as String).length() > MAX_TEXT:
			return false
	for key: String in optional:
		if source.has(key) and (not source[key] is String or (source[key] as String).length() > MAX_TEXT):
			return false
	return true

# Returns {"next_id", "facts"} with canonical types, or {} when invalid.
static func _parse(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var source: Dictionary = data
	if source.size() != 2 or not NpcMemory.is_integer(source.get("next_id")) \
			or float(source["next_id"]) < 1.0 or float(source["next_id"]) > 9007199254740992.0 \
			or not source.get("facts") is Array or (source["facts"] as Array).size() > MAX_FACTS:
		return {}
	var next_id: int = int(source["next_id"])
	var facts: Array[Dictionary] = []
	var previous: int = 0
	for raw: Variant in source["facts"]:
		var fact: Dictionary = _parse_fact(raw)
		if fact.is_empty():
			return {}
		var number: int = int((fact["id"] as String).substr(5))
		if number <= previous or number >= next_id:
			return {}
		previous = number
		facts.append(fact)
	return {"next_id": next_id, "facts": facts}

static func _parse_fact(raw: Variant) -> Dictionary:
	if not raw is Dictionary or (raw as Dictionary).size() != _FACT_KEYS.size():
		return {}
	var entry: Dictionary = raw
	for key: String in _FACT_KEYS:
		if not entry.has(key):
			return {}
	var id: Variant = entry["id"]
	var status: Variant = entry["status"]
	var source_id: Variant = entry["source_id"]
	if not id is String or not (id as String).begins_with("fact:") \
			or not (id as String).substr(5).is_valid_int() \
			or str(int((id as String).substr(5))) != (id as String).substr(5) \
			or int((id as String).substr(5)) < 1 \
			or not entry["subject"] is String or not _is_label(entry["subject"]) \
			or not entry["predicate"] is String or not _is_label(entry["predicate"]) \
			or not status is String or not (status as String) in Status.keys() \
			or not source_id is String or (source_id as String).length() > MAX_TEXT \
			or not _is_valid_value(entry["predicate"], entry["value"]) \
			or not _is_ref_list(entry["evidence_ids"]) or not _is_ref_list(entry["origin_ids"]):
		return {}
	for key: String in ["observed_minute", "recorded_minute"]:
		if not _is_number(entry[key]) or float(entry[key]) < 0.0:
			return {}
	if not NpcMemory.is_unit(entry["source_confidence"]):
		return {}
	return {"id": id, "subject": entry["subject"], "predicate": entry["predicate"],
		"value": _normalize(entry["value"]), "status": status, "source_id": source_id,
		"evidence_ids": _string_list(entry["evidence_ids"]),
		"origin_ids": _string_list(entry["origin_ids"]),
		"observed_minute": float(entry["observed_minute"]),
		"recorded_minute": float(entry["recorded_minute"]),
		"source_confidence": float(entry["source_confidence"])}

static func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _is_ref_list(value: Variant) -> bool:
	if not NpcMemory.is_text_list(value, MAX_REFS):
		return false
	for entry: String in value:
		if entry.is_empty():
			return false
	return true

static func _string_list(value: Array) -> Array[String]:
	var result: Array[String] = []
	for entry: Variant in value:
		result.append(entry as String)
	return result
