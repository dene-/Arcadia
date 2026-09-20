class_name NpcMemoryStore
extends RefCounted

## Save-owned cognition. Profiles are copied on first encounter, never mutated.
const SAVE_VERSION: int = 1
const MAX_HISTORY: int = 12
const SAVE_PATH: String = "user://npc_memory.json"

var turn: int = 0
var _states: Dictionary = {}
var _next_memory_id: int = 1
var _save_allowed: bool = true

func ensure_npc(profile: NpcProfile) -> void:
	var id: String = String(profile.npc_id)
	if id.is_empty() or _states.has(id):
		return
	var memories: Array[Dictionary] = []
	var ids: Dictionary = {}
	for authored: NpcCoreMemory in profile.core_memories:
		if authored == null or authored.memory_id.is_empty():
			continue
		var memory: Dictionary = authored.to_memory()
		if NpcMemory.is_valid(memory) and not ids.has(memory.id):
			memories.append(memory)
			ids[memory.id] = true
	# Preserve old authored strings without putting the whole archive into the prompt.
	for index: int in range(profile.memories.size()):
		var legacy: Dictionary = NpcMemory.create("legacy:%d" % index, "episodic",
			profile.memories[index], "authored", 0)
		if NpcMemory.is_valid(legacy):
			memories.append(legacy)
	_states[id] = {"recent_dialogue": [], "memories": memories,
		"relationship": NpcRelationshipState.initial(), "recent_events": [],
		"observations": [], "next_observation_id": 1}

func snapshot(npc_id: String) -> Dictionary:
	return _states.get(npc_id, {}).duplicate(true)

func advance_time(turns: int = 1) -> void:
	turn += maxi(turns, 0)

## Call only for events this NPC actually perceived, never for unverified player claims.
func record_event(profile: NpcProfile, event: String) -> void:
	ensure_npc(profile)
	var id: String = String(profile.npc_id)
	if not _states.has(id) or event.strip_edges().is_empty():
		return
	var events: Array = _states[id].recent_events
	events.append(event.substr(0, 500))
	if events.size() > 8:
		events.pop_front()

## Every perceived event enters short-term memory, independently of dialogue.
func record_observation(profile: NpcProfile, event: Dictionary) -> void:
	if profile == null or profile.npc_id.is_empty():
		return
	if not event.get("text") is String or event.text.is_empty() or event.text.length() > 500 \
		or not event.get("sense") in ["sight", "hearing", "touch"] \
		or not event.get("player_involved") is bool:
		return
	ensure_npc(profile)
	var state: Dictionary = _states[String(profile.npc_id)]
	var observation: Dictionary = event.duplicate(true)
	observation.id = state.next_observation_id
	observation.created_at = int(Time.get_unix_time_from_system())
	observation.status = "pending"
	observation.decision = {}
	state.next_observation_id += 1
	state.observations.append(observation)
	while state.observations.size() > 8:
		state.observations.pop_front()

func pending_observations(npc_id: String) -> Array[Dictionary]:
	var pending: Array[Dictionary] = []
	for observation: Dictionary in _states.get(npc_id, {}).get("observations", []):
		if observation.status == "pending":
			pending.append(observation.duplicate(true))
	return pending

func commit_observation(npc_id: String, observation_id: int, policy: Dictionary) -> bool:
	var state: Dictionary = _states.get(npc_id, {})
	for observation: Dictionary in state.get("observations", []):
		if observation.id != observation_id or observation.status != "pending":
			continue
		if not is_valid_policy(policy):
			observation.status = "unavailable"
			return false
		observation.status = "classified"
		observation.decision = policy.duplicate(true)
		advance_time()
		# Hearing noise alone cannot identify or change feelings toward the player.
		if observation.player_involved and observation.sense != "hearing":
			state.relationship = NpcRelationshipState.changed(state.relationship, policy.relationship_delta)
		if policy.remember:
			_admit(state.memories, {"type": "episodic", "source": "observed_event",
				"gist": observation.text, "topics": observation.get("topics", ["combat"]),
				"people": ["player"] if observation.player_involved else [],
				"sensory_cues": ["sounds of fighting"] if observation.sense == "hearing" else []}, policy)
		return true
	return false

## Diagnostics belong to the observation, never to model input or authored profiles.
func annotate_observation(npc_id: String, id: int, diagnostics: Dictionary) -> void:
	for record: Dictionary in _states.get(npc_id, {}).get("observations", []):
		if record.id == id:
			record["diagnostics"] = diagnostics.duplicate(true)
			return

func record_spoken_reaction(npc_id: String, text: String) -> void:
	if not _states.has(npc_id):
		return
	var history: Array = _states[npc_id].recent_dialogue
	history.append({"speaker": "npc", "text": text})
	while history.size() > MAX_HISTORY:
		history.pop_front()

## Game code resolves intentions; model prose never completes world objectives.
func complete_intention(npc_id: String, memory_id: String) -> bool:
	if not _states.has(npc_id):
		return false
	for memory: Dictionary in _states[npc_id].memories:
		if memory.id == memory_id and memory.type == "prospective":
			memory.completed = true
			return true
	return false

func commit_exchange(npc_id: String, message: String, result: Dictionary,
		policy: Dictionary, recalled: Array, consumed_events: Array) -> bool:
	if message.length() > 2000 or not _states.has(npc_id) \
		or not is_valid_result(result) or not is_valid_policy(policy):
		return false
	var state: Dictionary = _states[npc_id]
	advance_time()
	state.relationship = NpcRelationshipState.changed(state.relationship, policy.relationship_delta)
	var history: Array = state.recent_dialogue
	if not message.is_empty():
		history.append({"speaker": "player", "text": message})
	history.append({"speaker": "npc", "text": result.response})
	while history.size() > MAX_HISTORY:
		history.pop_front()
	var recalled_ids: Array = result.get("recalled_memory_ids", [])
	for memory: Dictionary in state.memories:
		if memory.id in recalled_ids and recalled.any(func(view: Dictionary) -> bool:
			return view.id == memory.id):
			memory.recall_count += 1
			memory.last_recalled_turn = turn
	if policy.remember:
		for proposal: Variant in result.get("memory_writes", []):
			_admit(state.memories, proposal, policy)
	# Only consume the events included in this exchange, preserving any arriving in flight.
	for event: Variant in consumed_events:
		state.recent_events.erase(event)
	return true

func to_save_data() -> Dictionary:
	return {"version": SAVE_VERSION, "turn": turn,
		"next_memory_id": _next_memory_id, "npcs": _states.duplicate(true)}

func from_save_data(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != SAVE_VERSION:
		return false
	if not NpcMemory.is_integer(data.get("turn")) or data.turn < 0 \
		or not NpcMemory.is_integer(data.get("next_memory_id")) or data.next_memory_id < 1:
		return false
	if not data.get("npcs") is Dictionary:
		return false
	for id: Variant in data.npcs:
		if not id is String or id.is_empty():
			return false
		var state: Variant = data.npcs[id]
		if not state is Dictionary or not NpcRelationshipState.is_valid(state.get("relationship")):
			return false
		if not _valid_history(state.get("recent_dialogue")) \
			or not state.get("memories") is Array or not _valid_events(state.get("recent_events")):
			return false
		if not _valid_observations(state.get("observations", []), state.get("next_observation_id", 1)):
			return false
		var ids: Dictionary = {}
		for memory: Variant in state.memories:
			if not NpcMemory.is_valid(memory) or ids.has(memory.id):
				return false
			ids[memory.id] = true
			if memory.id.begins_with("mem:") and int(memory.id.trim_prefix("mem:")) >= int(data.next_memory_id):
				return false
	_states = data.npcs.duplicate(true)
	# Existing version-1 saves gain the optional observation fields without losing memories.
	for state: Dictionary in _states.values():
		if not state.has("observations"):
			state.observations = []
		if not state.has("next_observation_id"):
			state.next_observation_id = 1
	turn = int(data.turn)
	_next_memory_id = int(data.next_memory_id)
	return true

func load_file(path: String = SAVE_PATH) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_save_allowed = false
		return FileAccess.get_open_error()
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not from_save_data(parser.data):
		_save_allowed = false
		return ERR_FILE_CORRUPT
	_save_allowed = true
	return OK

func save_file(path: String = SAVE_PATH) -> Error:
	# An unreadable/unsupported save must not be replaced by an empty new save.
	if not _save_allowed:
		return ERR_FILE_CORRUPT
	var temporary: String = path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_save_data()))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		return error
	return DirAccess.rename_absolute(temporary, path)

static func is_valid_policy(policy: Variant) -> bool:
	if not policy is Dictionary:
		return false
	if policy.has("speak") and not policy.speak is bool:
		return false
	if policy.has("end_conversation") and not policy.end_conversation is bool:
		return false
	for key: String in ["remember", "retrieve", "update_belief"]:
		if not policy.get(key) is bool:
			return false
	for key: String in ["importance", "emotional_intensity"]:
		if not NpcMemory.is_unit(policy.get(key)):
			return false
	if not policy.get("relationship_delta") is Dictionary:
		return false
	for key: String in NpcRelationshipState.KEYS:
		var value: Variant = policy.relationship_delta.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) \
			or absf(float(value)) > 0.100001:
			return false
	return policy.get("response_mode") in ["NEUTRAL", "WARM", "GUARDED", "DEFENSIVE", "REFUSE", "UNCERTAIN"]

static func is_valid_result(result: Dictionary) -> bool:
	if not result.get("response") is String or result.response.strip_edges().is_empty() \
		or result.response.length() > 6000:
		return false
	if not result.get("replies") is Array or result.replies.size() != 3:
		return false
	var unique: Array[String] = []
	for reply: Variant in result.replies:
		if not reply is String or reply.strip_edges().is_empty() or reply.length() > 500 \
			or reply in unique:
			return false
		unique.append(reply)
	return result.get("memory_writes") is Array and result.memory_writes.size() <= 3 \
		and NpcMemory.is_text_list(result.get("recalled_memory_ids"))

func _admit(memories: Array, proposal: Variant, policy: Dictionary) -> void:
	if not proposal is Dictionary:
		return
	var memory: Dictionary = NpcMemory.create("mem:%d" % _next_memory_id,
		str(proposal.get("type", "")), str(proposal.get("gist", "")),
		str(proposal.get("source", "")), turn)
	if memory.source == "authored":
		return
	if memory.type == "semantic" and (not policy.update_belief or memory.source == "npc_statement"):
		return
	memory.importance = policy.importance
	memory.emotional_intensity = policy.emotional_intensity
	memory.vividness = clampf(0.3 + policy.importance * 0.4 + policy.emotional_intensity * 0.3, 0.0, 1.0)
	# Confidence in claims is not certainty about the world, even after belief admission.
	memory.confidence = 0.6 if memory.source == "player_claim" else 0.9
	for key: String in NpcMemory.TEXT_LISTS:
		memory[key] = proposal.get(key, [])
	if not NpcMemory.is_valid(memory):
		return
	for existing: Dictionary in memories:
		if existing.gist.to_lower() == memory.gist.to_lower() and existing.source == memory.source:
			return # Repetition is not independent evidence or a new memory.
	memories.append(memory)
	_next_memory_id += 1

func _valid_history(value: Variant) -> bool:
	if not value is Array or value.size() > MAX_HISTORY:
		return false
	for entry: Variant in value:
		if not entry is Dictionary or not entry.get("speaker") in ["npc", "player"] \
			or not entry.get("text") is String or entry.text.length() > 6000:
			return false
	return true

func _valid_events(value: Variant) -> bool:
	if not value is Array or value.size() > 8:
		return false
	for event: Variant in value:
		if not event is String or event.length() > 500:
			return false
	return true

func _valid_observations(value: Variant, next_id: Variant) -> bool:
	if not value is Array or value.size() > 8 or not NpcMemory.is_integer(next_id) or next_id < 1:
		return false
	var ids: Array[int] = []
	for observation: Variant in value:
		if not observation is Dictionary or not NpcMemory.is_integer(observation.get("id")):
			return false
		if observation.id < 1 or observation.id >= next_id or int(observation.id) in ids:
			return false
		ids.append(int(observation.id))
		if not observation.get("text") is String or observation.text.is_empty() \
			or observation.text.length() > 500 or not observation.get("player_involved") is bool \
			or not observation.get("sense") in ["sight", "hearing", "touch"] \
			or not observation.get("status") in ["pending", "classified", "unavailable"]:
			return false
		var timestamp: Variant = observation.get("created_at")
		if not (timestamp is float or timestamp is int) or not is_finite(float(timestamp)):
			return false
		if not observation.get("decision") is Dictionary or \
			(observation.status == "classified" and not is_valid_policy(observation.decision)):
			return false
	return true
