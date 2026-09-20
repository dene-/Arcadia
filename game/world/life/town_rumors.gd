class_name TownRumors
extends RefCounted

## Subjective accounts, kept separately for each person. Repetition never creates corroboration.
const MAX_KNOWN: int = 32
const MAX_HOPS: int = 4
var _known: Dictionary = {}

func observe(id: String, name: String, event: Dictionary, policy: Dictionary, minute: float) -> void:
	var origin: String = event.get("origin_id", "")
	if origin.is_empty():
		return
	if name.is_empty():
		name = id
	var account: Dictionary = {
		"origin_id": origin, "text": event.text, "originator": id,
		"originator_name": name, "source_id": id, "source_name": name,
		"sense": event.sense, "hops": 0, "chain": [id],
		"basis": event.get("basis", "perception"),
		"player_involved": event.player_involved, "confidence": 0.9,
		"importance": policy.importance, "learned_at": minute,
		"expires_at": minute + (10080.0 if policy.remember else 180.0),
	}
	_put(id, account, minute)

func candidates(speaker: String, listener: String, minute: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for account: Dictionary in get_known(speaker, minute):
		if account.hops >= MAX_HOPS or listener in account.chain or knows(listener, account.origin_id, minute):
			continue
		result.append(account)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.importance == b.importance:
			return a.learned_at > b.learned_at
		return a.importance > b.importance)
	return result.slice(0, 4)

func hear(listener: String, speaker: String, speaker_name: String, account: Dictionary,
		policy: Dictionary, minute: float) -> Dictionary:
	if not is_valid_account(account) or not policy.get("remember") is bool \
		or not NpcMemory.is_unit(policy.get("belief")) or not NpcMemory.is_unit(policy.get("importance")):
		return {}
	# Resolve against current speaker knowledge so a stale or altered candidate cannot introduce facts.
	var original: Dictionary = {}
	for known: Dictionary in get_known(speaker, minute):
		if known.origin_id == account.origin_id:
			original = known
	if original.is_empty() or original.hops >= MAX_HOPS or listener in original.chain \
		or knows(listener, original.origin_id, minute):
		return {}
	var heard: Dictionary = original.duplicate(true)
	heard.source_id = speaker
	heard.source_name = speaker_name
	heard.hops += 1
	heard.chain.append(listener)
	heard.learned_at = minute
	heard.confidence = minf(float(original.confidence), float(policy.belief))
	heard.importance = policy.importance
	heard.expires_at = minf(original.expires_at, minute + (10080.0 if policy.remember else 180.0))
	_put(listener, heard, minute)
	return heard.duplicate(true)

func knows(id: String, origin: String, _minute: float) -> bool:
	return _known.get(id, []).any(func(item: Dictionary) -> bool: return item.origin_id == origin)

func get_known(id: String, minute: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in _known.get(id, []):
		if item.expires_at > minute:
			result.append(item.duplicate(true))
	return result

func _put(id: String, account: Dictionary, minute: float) -> void:
	var known: Array[Dictionary] = get_known(id, minute)
	# Direct perception supersedes hearsay, but never combines confidence from repeated tellings.
	known = known.filter(func(item: Dictionary) -> bool: return item.origin_id != account.origin_id)
	known.append(account.duplicate(true))
	while known.size() > MAX_KNOWN:
		known.pop_front()
	_known[id] = known

func to_data() -> Dictionary:
	return _known.duplicate(true)

func from_data(data: Variant) -> bool:
	if not data is Dictionary or data.size() > 512:
		return false
	for id: Variant in data:
		if not id is String or id.is_empty() or not data[id] is Array or data[id].size() > MAX_KNOWN:
			return false
		var seen: Array[String] = []
		for item: Variant in data[id]:
			if not is_valid_account(item) or item.origin_id in seen:
				return false
			seen.append(item.origin_id)
	_known = data.duplicate(true)
	return true

static func is_valid_account(item: Variant) -> bool:
	if not item is Dictionary:
		return false
	for key: String in ["origin_id", "text", "originator", "originator_name", "source_id", "source_name"]:
		if not item.get(key) is String or item[key].is_empty() or item[key].length() > 500:
			return false
	if not item.get("sense") in ["sight", "hearing", "touch"] or not item.get("player_involved") is bool:
		return false
	if not NpcMemory.is_integer(item.get("hops")) or item.hops < 0 or item.hops > MAX_HOPS:
		return false
	if not NpcMemory.is_text_list(item.get("chain"), MAX_HOPS + 1) or item.chain.size() != item.hops + 1:
		return false
	for key: String in ["confidence", "importance"]:
		if not NpcMemory.is_unit(item.get(key)):
			return false
	for key: String in ["learned_at", "expires_at"]:
		if not (item.get(key) is int or item.get(key) is float) or not is_finite(item[key]) or item[key] < 0:
			return false
	return item.expires_at >= item.learned_at
