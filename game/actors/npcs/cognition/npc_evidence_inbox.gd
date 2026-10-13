class_name NpcEvidenceInbox
extends RefCounted

## One resident's pending evidence. Items leave the inbox only through `complete`; their ids then
## become receipts so a replayed observation can never be appraised twice.
enum Status { PENDING, CLAIMED, DEFERRED }

const READY_WINDOW: int = 32
const INCIDENT_WINDOW_MINUTES: float = 10.0
const RETRY_DELAY_MINUTES: float = 2.0
const MAX_ITEMS: int = 512
const MAX_RECEIPTS: int = 1024
const MAX_DIAGNOSTICS: int = 64
const MAX_INCIDENTS: int = 64
const MAX_SERIALIZED_ITEMS: int = 8192
const MAX_ERROR_LENGTH: int = 200
const SCHEMA_VERSION: int = 1
const _COMBAT_FAMILY: Array[StringName] = [&"actor_hurt", &"actor_died", &"combat_noise"]
const _DATA_KEYS: Array[String] = ["version", "incident_counter", "items", "receipts",
	"incidents", "diagnostics"]
const _ITEM_KEYS: Array[String] = ["observation", "status", "attempts", "retry_after", "count",
	"first_minute", "last_minute", "last_error"]
const _INCIDENT_KEYS: Array[String] = ["incident_id", "observer_id", "space_id", "family",
	"participant_ids", "last_minute"]

class _Item extends RefCounted:
	var observation: NpcObservation
	var status: int = NpcEvidenceInbox.Status.PENDING
	var attempts: int = 0
	var retry_after: float = 0.0
	var count: int = 1
	var first_minute: float = 0.0
	var last_minute: float = 0.0
	var last_error: String = ""
	var protected: bool = false

	func is_eligible(now_minute: float) -> bool:
		return status == NpcEvidenceInbox.Status.PENDING \
			or (status == NpcEvidenceInbox.Status.DEFERRED and retry_after <= now_minute)

## Increments on every accepted mutation.
var version: int = 0

var _items: Array[_Item] = []
var _by_id: Dictionary[String, _Item] = {}
var _receipts: Array[String] = []
var _receipt_ids: Dictionary[String, bool] = {}
var _incidents: Array[Dictionary] = []
var _diagnostics: Array[Dictionary] = []
var _incident_counter: int = 0

func enqueue(observation: NpcObservation) -> bool:
	if observation == null or not observation.is_valid():
		return false
	var id: String = observation.observation_id
	if _by_id.has(id) or _receipt_ids.has(id):
		return false
	var stored: NpcObservation = observation.copy()
	if stored.incident_id.is_empty():
		stored.incident_id = _assign_incident(stored)
	var protected: bool = stored.is_protected()
	if stored.modality == NpcObservation.Modality.NOISE and not protected:
		var target: _Item = _coalesce_target(stored)
		if target != null:
			target.count += 1
			target.last_minute = maxf(target.last_minute, stored.observed_minute)
			_record({"incident_id": stored.incident_id, "coalesced_id": id,
				"minute": stored.observed_minute})
			version += 1
			return true
	_make_room()
	var entry := _Item.new()
	entry.observation = stored
	entry.first_minute = stored.observed_minute
	entry.last_minute = stored.observed_minute
	entry.protected = protected
	_items.append(entry)
	_by_id[id] = entry
	version += 1
	return true

func contains_pending(observation_id: String) -> bool:
	return _by_id.has(observation_id)

func has_receipt(observation_id: String) -> bool:
	return _receipt_ids.has(observation_id)

## Size of the dispatch window: eligible items, capped at READY_WINDOW.
func ready_count(now_minute: float = INF) -> int:
	var eligible: int = 0
	for entry: _Item in _items:
		if entry.is_eligible(now_minute):
			eligible += 1
	return mini(eligible, READY_WINDOW)

func next_ready(now_minute: float) -> NpcObservation:
	var best: _Item = null
	for entry: _Item in _items:
		if entry.is_eligible(now_minute) and (best == null or _precedes(entry, best)):
			best = entry
	return best.observation.copy() if best != null else null

func claim(observation_id: String, now_minute: float) -> NpcObservation:
	var entry: _Item = _by_id.get(observation_id)
	if entry == null or not entry.is_eligible(now_minute):
		return null
	entry.status = Status.CLAIMED
	version += 1
	return entry.observation.copy()

func complete(observation_id: String) -> bool:
	var entry: _Item = _by_id.get(observation_id)
	if entry == null or entry.status != Status.CLAIMED:
		return false
	_items.erase(entry)
	_by_id.erase(observation_id)
	_receipts.append(observation_id)
	_receipt_ids[observation_id] = true
	while _receipts.size() > MAX_RECEIPTS:
		_receipt_ids.erase(_receipts[0])
		_receipts.remove_at(0)
	version += 1
	return true

func fail(observation_id: String, reason: String, now_minute: float) -> bool:
	var entry: _Item = _by_id.get(observation_id)
	if entry == null or entry.status != Status.CLAIMED or not is_finite(now_minute):
		return false
	entry.status = Status.DEFERRED
	entry.attempts += 1
	entry.retry_after = now_minute + RETRY_DELAY_MINUTES
	entry.last_error = reason.substr(0, MAX_ERROR_LENGTH)
	version += 1
	return true

## Returns a claimed item to PENDING without counting an attempt.
func release(observation_id: String) -> bool:
	var entry: _Item = _by_id.get(observation_id)
	if entry == null or entry.status != Status.CLAIMED:
		return false
	entry.status = Status.PENDING
	entry.retry_after = 0.0
	version += 1
	return true

func defer(observation_id: String, until_minute: float) -> bool:
	var entry: _Item = _by_id.get(observation_id)
	if entry == null or entry.status == Status.DEFERRED or not is_finite(until_minute):
		return false
	entry.status = Status.DEFERRED
	entry.retry_after = until_minute
	version += 1
	return true

func item(observation_id: String) -> Dictionary:
	var entry: _Item = _by_id.get(observation_id)
	if entry == null:
		return {}
	return {"observation": entry.observation.to_data(), "status": Status.keys()[entry.status],
		"attempts": entry.attempts, "retry_after": entry.retry_after, "count": entry.count,
		"first_minute": entry.first_minute, "last_minute": entry.last_minute,
		"last_error": entry.last_error}

func pending_observations() -> Array[NpcObservation]:
	var result: Array[NpcObservation] = []
	for entry: _Item in _items:
		result.append(entry.observation.copy())
	return result

func diagnostics() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _diagnostics:
		result.append(entry.duplicate(true))
	return result

## Claims are runtime-only, so a CLAIMED item is saved as PENDING.
func to_data() -> Dictionary:
	var items: Array[Dictionary] = []
	for entry: _Item in _items:
		var claimed: bool = entry.status == Status.CLAIMED
		items.append({"observation": entry.observation.to_data(),
			"status": Status.keys()[Status.PENDING if claimed else entry.status],
			"attempts": entry.attempts, "retry_after": 0.0 if claimed else entry.retry_after,
			"count": entry.count, "first_minute": entry.first_minute,
			"last_minute": entry.last_minute, "last_error": entry.last_error})
	return {"version": SCHEMA_VERSION, "incident_counter": _incident_counter, "items": items,
		"receipts": _receipts.duplicate(), "incidents": _incidents.duplicate(true),
		"diagnostics": _diagnostics.duplicate(true)}

static func is_valid_data(data: Variant) -> bool:
	return not _parse(data).is_empty()

## Replaces the whole inbox, or changes nothing and returns false.
func from_data(data: Variant) -> bool:
	var parsed: Dictionary = _parse(data)
	if parsed.is_empty():
		return false
	_items.clear()
	_by_id.clear()
	for entry: _Item in parsed["items"]:
		_items.append(entry)
		_by_id[entry.observation.observation_id] = entry
	_receipts = parsed["receipts"]
	_receipt_ids.clear()
	for id: String in _receipts:
		_receipt_ids[id] = true
	_incidents = parsed["incidents"]
	_diagnostics = parsed["diagnostics"]
	_incident_counter = parsed["incident_counter"]
	version += 1
	return true

# Protected evidence first, then oldest observation. Ties keep insertion order because callers
# iterate `_items` in order and only replace the best entry on a strict win.
func _precedes(candidate: _Item, best: _Item) -> bool:
	if candidate.protected != best.protected:
		return candidate.protected
	return candidate.observation.observed_minute < best.observation.observed_minute

func _coalesce_target(observation: NpcObservation) -> _Item:
	for entry: _Item in _items:
		if entry.status != Status.CLAIMED and entry.observation.modality == NpcObservation.Modality.NOISE \
				and not entry.protected and entry.observation.incident_id == observation.incident_id:
			return entry
	return null

func _make_room() -> void:
	if _items.size() < MAX_ITEMS:
		return
	for entry: _Item in _items:
		if entry.status != Status.CLAIMED and not entry.protected:
			_items.erase(entry)
			_by_id.erase(entry.observation.observation_id)
			_record({"dropped_id": entry.observation.observation_id, "reason": "capacity"})
			return

func _record(diagnostic: Dictionary) -> void:
	_diagnostics.append(diagnostic)
	while _diagnostics.size() > MAX_DIAGNOSTICS:
		_diagnostics.remove_at(0)

# A death or a different participant set (a new identified victim) never joins an older incident.
func _assign_incident(observation: NpcObservation) -> String:
	var ids: Array[String] = observation.participant_ids()
	ids.sort()
	var family: String = _family(observation.kind)
	var space: String = String(observation.space_id)
	if observation.kind != &"actor_died":
		for index: int in range(_incidents.size() - 1, -1, -1):
			var incident: Dictionary = _incidents[index]
			if incident["observer_id"] == observation.observer_id and incident["space_id"] == space \
					and incident["family"] == family and incident["participant_ids"] == ids \
					and absf(observation.observed_minute - float(incident["last_minute"])) \
						<= INCIDENT_WINDOW_MINUTES:
				incident["last_minute"] = maxf(float(incident["last_minute"]), observation.observed_minute)
				_incidents.remove_at(index)
				_incidents.append(incident)
				return incident["incident_id"]
	_incident_counter += 1
	var incident_id: String = "incident:%s:%d" % [observation.observer_id, _incident_counter]
	_incidents.append({"incident_id": incident_id, "observer_id": observation.observer_id,
		"space_id": space, "family": family, "participant_ids": ids,
		"last_minute": observation.observed_minute})
	while _incidents.size() > MAX_INCIDENTS:
		_incidents.remove_at(0)
	return incident_id

static func _family(kind: StringName) -> String:
	return "combat" if kind in _COMBAT_FAMILY else String(kind)

# Validates everything and builds the replacement state; empty when `data` is invalid.
static func _parse(data: Variant) -> Dictionary:
	if not data is Dictionary or (data as Dictionary).size() != _DATA_KEYS.size():
		return {}
	var source: Dictionary = data
	for key: String in _DATA_KEYS:
		if not source.has(key):
			return {}
	if not _is_count(source["version"]) or int(source["version"]) != SCHEMA_VERSION \
			or not _is_count(source["incident_counter"]):
		return {}
	if not source["items"] is Array or (source["items"] as Array).size() > MAX_SERIALIZED_ITEMS \
			or not source["receipts"] is Array or (source["receipts"] as Array).size() > MAX_RECEIPTS \
			or not source["incidents"] is Array or (source["incidents"] as Array).size() > MAX_INCIDENTS \
			or not source["diagnostics"] is Array \
			or (source["diagnostics"] as Array).size() > MAX_DIAGNOSTICS:
		return {}
	var receipts: Array[String] = []
	var receipt_ids: Dictionary[String, bool] = {}
	for entry: Variant in source["receipts"]:
		if not entry is String or (entry as String).is_empty() \
				or (entry as String).length() > NpcObservation.MAX_OBSERVATION_ID_LENGTH \
				or receipt_ids.has(entry):
			return {}
		receipts.append(entry)
		receipt_ids[entry] = true
	var items: Array[_Item] = []
	var item_ids: Dictionary[String, bool] = {}
	for raw: Variant in source["items"]:
		var entry: _Item = _parse_item(raw)
		var id: String = entry.observation.observation_id if entry != null else ""
		if entry == null or item_ids.has(id) or receipt_ids.has(id):
			return {}
		item_ids[id] = true
		items.append(entry)
	var incidents: Array[Dictionary] = []
	for raw: Variant in source["incidents"]:
		var incident: Dictionary = _parse_incident(raw)
		if incident.is_empty():
			return {}
		incidents.append(incident)
	var diagnostics: Array[Dictionary] = []
	for raw: Variant in source["diagnostics"]:
		var diagnostic: Dictionary = _parse_diagnostic(raw)
		if diagnostic.is_empty():
			return {}
		diagnostics.append(diagnostic)
	return {"items": items, "receipts": receipts, "incidents": incidents,
		"diagnostics": diagnostics, "incident_counter": int(source["incident_counter"])}

static func _parse_item(raw: Variant) -> _Item:
	if not raw is Dictionary or (raw as Dictionary).size() != _ITEM_KEYS.size():
		return null
	var source: Dictionary = raw
	for key: String in _ITEM_KEYS:
		if not source.has(key):
			return null
	var observation: NpcObservation = NpcObservation.from_data(source["observation"])
	if observation == null or observation.incident_id.is_empty():
		return null
	var status: Variant = source["status"]
	if not status is String or not (status as String) in ["PENDING", "DEFERRED"]:
		return null
	if not _is_count(source["attempts"]) or not _is_count(source["count"]) or int(source["count"]) < 1 \
			or not _is_number(source["retry_after"]) or not _is_number(source["first_minute"]) \
			or not _is_number(source["last_minute"]) \
			or float(source["first_minute"]) > float(source["last_minute"]) \
			or not source["last_error"] is String \
			or (source["last_error"] as String).length() > MAX_ERROR_LENGTH:
		return null
	if int(source["count"]) > 1 and observation.modality != NpcObservation.Modality.NOISE:
		return null
	var entry := _Item.new()
	entry.observation = observation
	entry.status = Status[status]
	entry.attempts = int(source["attempts"])
	entry.retry_after = float(source["retry_after"])
	entry.count = int(source["count"])
	entry.first_minute = float(source["first_minute"])
	entry.last_minute = float(source["last_minute"])
	entry.last_error = source["last_error"]
	entry.protected = observation.is_protected()
	return entry

static func _parse_incident(raw: Variant) -> Dictionary:
	if not raw is Dictionary or (raw as Dictionary).size() != _INCIDENT_KEYS.size():
		return {}
	var source: Dictionary = raw
	for key: String in _INCIDENT_KEYS:
		if not source.has(key):
			return {}
	for key: String in ["incident_id", "observer_id", "family"]:
		if not source[key] is String or (source[key] as String).is_empty() \
				or (source[key] as String).length() > NpcObservation.MAX_ID_LENGTH:
			return {}
	if not source["space_id"] is String \
			or (source["space_id"] as String).length() > NpcObservation.MAX_ID_LENGTH \
			or not _is_number(source["last_minute"]) \
			or not source["participant_ids"] is Array \
			or (source["participant_ids"] as Array).size() > NpcObservation.MAX_PARTICIPANTS:
		return {}
	var ids: Array[String] = []
	for id: Variant in source["participant_ids"]:
		if not id is String or (id as String).is_empty() \
				or (id as String).length() > NpcObservation.MAX_ID_LENGTH:
			return {}
		ids.append(id)
	return {"incident_id": source["incident_id"], "observer_id": source["observer_id"],
		"space_id": source["space_id"], "family": source["family"], "participant_ids": ids,
		"last_minute": float(source["last_minute"])}

static func _parse_diagnostic(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var source: Dictionary = raw
	if source.size() == 3 and source.get("incident_id") is String \
			and source.get("coalesced_id") is String and _is_number(source.get("minute")):
		return {"incident_id": source["incident_id"], "coalesced_id": source["coalesced_id"],
			"minute": float(source["minute"])}
	if source.size() == 2 and source.get("dropped_id") is String and source.get("reason") is String:
		return {"dropped_id": source["dropped_id"], "reason": source["reason"]}
	return {}

static func _is_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _is_count(value: Variant) -> bool:
	return NpcMemory.is_integer(value) and float(value) >= 0.0 and float(value) <= 9007199254740992.0
