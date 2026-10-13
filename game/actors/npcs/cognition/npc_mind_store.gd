class_name NpcMindStore
extends RefCounted

const SCHEMA_VERSION: int = 1
const MAX_MINDS: int = 1024

var _minds: Dictionary = {}

func get_mind(npc_id: String) -> NpcMindState:
	if npc_id.is_empty():
		return null
	if not _minds.has(npc_id):
		_minds[npc_id] = NpcMindState.new(npc_id)
	return _minds[npc_id]

func has_mind(npc_id: String) -> bool:
	return _minds.has(npc_id)

func ids() -> Array[String]:
	var result: Array[String] = []
	for key: Variant in _minds:
		result.append(key as String)
	result.sort()
	return result

func to_data() -> Dictionary:
	var minds: Dictionary = {}
	for id: String in ids():
		minds[id] = (_minds[id] as NpcMindState).to_data()
	return {"version": SCHEMA_VERSION, "minds": minds}

static func is_valid_data(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var source: Dictionary = data
	if source.size() != 2 or not NpcMemory.is_integer(source.get("version")) \
			or int(source["version"]) != SCHEMA_VERSION or not source.get("minds") is Dictionary:
		return false
	var minds: Dictionary = source["minds"]
	if minds.size() > MAX_MINDS:
		return false
	for key: Variant in minds:
		if not key is String or (key as String).is_empty() \
				or not NpcMindState.is_valid_data(minds[key], key):
			return false
	return true

# Validates every mind first. Existing instances for surviving ids keep their identity so
# holders of a NpcMindState reference stay connected; ids absent from the data are dropped.
func from_data(data: Variant) -> bool:
	if not is_valid_data(data):
		return false
	var minds: Dictionary = (data as Dictionary)["minds"]
	var restored: Dictionary = {}
	for key: Variant in minds:
		var id: String = key
		var mind: NpcMindState = _minds.get(id, NpcMindState.new(id))
		if not mind.from_data(minds[id]):
			return false
		restored[id] = mind
	_minds = restored
	return true
