class_name NpcMemoryStore
extends RefCounted

signal memories_admitted(npc_id: String, memories: Array)

## Save-owned cognition. Profiles are copied on first encounter, never mutated.
const SAVE_VERSION: int = 2
const MAX_HISTORY: int = 12
const _STATE_KEYS: Array[String] = ["recent_dialogue", "memories", "recent_events",
	"observations", "next_observation_id", "heard_origins"]

var turn: int = 0
var world_minute: float = 480.0
var _states: Dictionary = {}
var _next_memory_id: int = 1
var _revisions: Dictionary[String, int] = {}
## Owner of directed relationships; NpcWorldSave shares one instance with TownLifeState.
var minds: NpcMindStore = NpcMindStore.new()

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
	for memory: Dictionary in memories:
		NpcMemory.anchor_legacy(memory, world_minute, 0)
	_states[id] = {"recent_dialogue": [], "memories": memories, "recent_events": [],
		"observations": [], "next_observation_id": 1, "heard_origins": {}}
	_changed(id)

## Relationship is a read adapter over the mind store; it is never stored in memory state.
func snapshot(npc_id: String) -> Dictionary:
	if not _states.has(npc_id):
		return {}
	var state: Dictionary = _states[npc_id].duplicate(true)
	state["relationship"] = minds.get_mind(npc_id).relationships.get_relationship("player")
	return state

## Runtime invalidation token. Diagnostics and other NPCs cannot invalidate a response.
func revision(npc_id: String) -> int:
	return _revisions.get(npc_id, 0)

func _changed(npc_id: String) -> void:
	_revisions[npc_id] = revision(npc_id) + 1

## Called only after an actual social transfer. Repeated origin IDs cannot alter belief or trust.
func record_hearsay(profile: NpcProfile, account: Dictionary, policy: Dictionary) -> void:
	ensure_npc(profile)
	var state: Dictionary = _states[String(profile.npc_id)]
	var id: String = "rumor:" + account.origin_id
	if state.heard_origins.has(account.origin_id):
		return
	for existing: Dictionary in state.memories:
		if existing.id == id:
			return
	# Receipts survive even when the story itself is not retained. Retelling is not evidence.
	state.heard_origins[account.origin_id] = true
	_changed(String(profile.npc_id))
	if account.player_involved and account.confidence >= 0.7:
		minds.get_mind(String(profile.npc_id)).relationships.apply_delta("player",
			{"trust": clampf(policy.trust_player, -0.03, 0.03)},
			"hearsay:%s:%s" % [profile.npc_id, account.origin_id])
	if not policy.remember:
		return
	var gist: String = "%s told me that %s reported: %s" % [account.source_name,
		account.originator_name, account.text]
	var memory: Dictionary = NpcMemory.create(id, "episodic", gist.substr(0, 500), "hearsay", turn)
	memory.created_minute = world_minute
	memory.confidence = account.confidence
	memory.importance = policy.importance
	memory.topics = ["town", "news"]
	memory.people = ["player"] if account.player_involved else []
	state.memories.append(memory)

func advance_time(turns: int = 1) -> void:
	turn += maxi(turns, 0)

## The world clock owns elapsed time. The turn counter is only an exchange/event sequence.
func set_world_minute(minute: float) -> void:
	if is_finite(minute) and minute >= 0.0:
		world_minute = minute

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
	_changed(id)

## Every perceived event enters the short-term display window, independently of dialogue. The
## window is context only: evidence awaiting appraisal lives in the mind's NpcEvidenceInbox.
func record_observation(profile: NpcProfile, event: Dictionary, world_minute: float = -1.0) -> void:
	if profile == null or profile.npc_id.is_empty():
		return
	if not event.get("text") is String or event.text.is_empty() or event.text.length() > 500 \
		or not event.get("sense") in ["sight", "hearing", "touch"] \
		or not event.get("player_involved") is bool or not _valid_evidence_fields(event):
		return
	ensure_npc(profile)
	var state: Dictionary = _states[String(profile.npc_id)]
	var observation: Dictionary = event.duplicate(true)
	observation.id = state.next_observation_id
	observation.created_at = int(Time.get_unix_time_from_system())
	if is_finite(world_minute) and world_minute >= 0.0:
		observation["world_minute"] = world_minute
	observation.status = "pending"
	observation.decision = {}
	state.next_observation_id += 1
	state.observations.append(observation)
	while state.observations.size() > 8:
		state.observations.pop_front()
	_changed(String(profile.npc_id))

## Appraises evidence the inbox has claimed. Returns false and changes nothing for an invalid
## policy, so the caller can defer the evidence. The caller completes the inbox item; the
## inbox receipt (not this method) prevents a second appraisal of the same observation.
func commit_evidence(npc_id: String, observation: NpcObservation, policy: Dictionary) -> bool:
	if observation == null or not _states.has(npc_id) or not is_valid_policy(policy):
		return false
	var state: Dictionary = _states[npc_id]
	_changed(npc_id)
	for entry: Dictionary in state.observations:
		if entry.get("observation_id") == observation.observation_id:
			entry.status = "classified"
			entry.decision = policy.duplicate(true)
	advance_time()
	# Hearing noise alone cannot identify or change feelings toward the player.
	if observation.facts.get("player_involved") == true \
			and observation.modality in [NpcObservation.Modality.SIGHT, NpcObservation.Modality.TOUCH]:
		minds.get_mind(npc_id).relationships.apply_delta("player", policy.relationship_delta,
			"observation:%s:%s" % [npc_id, observation.observation_id])
	if policy.remember:
		var people: Array[String] = observation.participant_ids()
		if not observation.source_id.is_empty() and not observation.source_id in people:
			people.append(observation.source_id)
		var topics: Array[String] = observation.topics.slice(0, 8)
		if topics.is_empty():
			topics.append(String(observation.kind) if observation.kind != &"unknown" else "event")
		_admit(state.memories, {"type": "episodic",
			"source": "hearsay" if observation.modality == NpcObservation.Modality.SPOKEN_REPORT \
				else "observed_event",
			"gist": observation.text, "topics": topics, "people": people.slice(0, 8),
			"sensory_cues": observation.cues.slice(0, 8)}, policy)
	return true

## Diagnostics belong to the display entry, never to model input or authored profiles.
func annotate_observation(npc_id: String, observation_id: String, diagnostics: Dictionary) -> void:
	for record: Dictionary in _states.get(npc_id, {}).get("observations", []):
		if record.get("observation_id") == observation_id:
			record["diagnostics"] = diagnostics.duplicate(true)
			return

## Game code resolves intentions; model prose never completes world objectives.
func complete_intention(npc_id: String, memory_id: String) -> bool:
	if not _states.has(npc_id):
		return false
	for memory: Dictionary in _states[npc_id].memories:
		if memory.id == memory_id and memory.type == "prospective":
			memory.completed = true
			_changed(npc_id)
			return true
	return false

func commit_exchange(npc_id: String, message: String, result: Dictionary,
		policy: Dictionary, recalled: Array, consumed_events: Array) -> bool:
	if message.length() > 2000 or not _states.has(npc_id) \
		or not is_valid_result(result) or not is_valid_policy(policy):
		return false
	var state: Dictionary = _states[npc_id]
	_changed(npc_id)
	advance_time()
	minds.get_mind(npc_id).relationships.apply_delta("player", policy.relationship_delta,
		"exchange:%s:%d" % [npc_id, turn])
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
			memory.last_recalled_minute = world_minute
	var previous_count: int = state.memories.size()
	if policy.remember:
		for proposal: Variant in result.get("memory_writes", []):
			_admit(state.memories, proposal, policy)
	# Only consume the events included in this exchange, preserving any arriving in flight.
	for event: Variant in consumed_events:
		state.recent_events.erase(event)
	if state.memories.size() > previous_count:
		memories_admitted.emit(npc_id, state.memories.slice(previous_count).duplicate(true))
	return true

func to_save_data() -> Dictionary:
	return {"version": SAVE_VERSION, "turn": turn, "world_minute": world_minute,
		"next_memory_id": _next_memory_id, "npcs": _states.duplicate(true)}

func from_save_data(data: Variant, at_minute: float = -1.0) -> bool:
	if not data is Dictionary or data.get("version") != SAVE_VERSION:
		return false
	if not NpcMemory.is_integer(data.get("turn")) or data.turn < 0 \
		or not NpcMemory.is_integer(data.get("next_memory_id")) or data.next_memory_id < 1:
		return false
	if not data.get("npcs") is Dictionary:
		return false
	var saved_minute: Variant = data.get("world_minute", 480.0)
	if not (saved_minute is float or saved_minute is int) \
		or not is_finite(float(saved_minute)) or saved_minute < 0:
		return false
	var load_minute: float = at_minute if at_minute >= 0.0 else float(saved_minute)
	if not is_finite(load_minute):
		return false
	for id: Variant in data.npcs:
		if not id is String or id.is_empty():
			return false
		var state: Variant = data.npcs[id]
		if not state is Dictionary or state.size() != _STATE_KEYS.size():
			return false
		for key: String in _STATE_KEYS:
			if not state.has(key):
				return false
		if not _valid_history(state.get("recent_dialogue")) \
			or not state.get("memories") is Array or not _valid_events(state.get("recent_events")):
			return false
		if not _valid_observations(state.get("observations"), state.get("next_observation_id")):
			return false
		var origins: Variant = state.get("heard_origins")
		if not origins is Dictionary:
			return false
		for origin: Variant in origins:
			if not origin is String or origin.is_empty() or origin.length() > 500 \
				or not origins[origin] is bool or not origins[origin]:
				return false
		var ids: Dictionary = {}
		for memory: Variant in state.memories:
			if not NpcMemory.is_valid(memory) or ids.has(memory.id):
				return false
			ids[memory.id] = true
			if memory.id.begins_with("mem:") and int(memory.id.trim_prefix("mem:")) >= int(data.next_memory_id):
				return false
	_states = data.npcs.duplicate(true)
	for id: String in _revisions.keys():
		_changed(id)
	# Memory shapes are strict: saves from older versions are upgraded by NpcSaveMigration.
	for state: Dictionary in _states.values():
		for memory: Dictionary in state.memories:
			NpcMemory.anchor_legacy(memory, load_minute, int(data.turn))
	turn = int(data.turn)
	world_minute = load_minute
	_next_memory_id = int(data.next_memory_id)
	return true

static func is_valid_policy(policy: Variant) -> bool:
	if not policy is Dictionary:
		return false
	if policy.has("speak") and not policy.speak is bool:
		return false
	if policy.has("end_conversation") and not policy.end_conversation is bool:
		return false
	if policy.has("safety_response") and not policy.safety_response in NpcSafetyState.RESPONSES:
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
	memory.created_minute = world_minute
	if memory.source == "authored":
		return
	if memory.type == "semantic" and (not policy.update_belief or memory.source == "npc_statement"):
		return
	memory.importance = policy.importance
	memory.emotional_intensity = policy.emotional_intensity
	memory.vividness = clampf(0.3 + policy.importance * 0.4 + policy.emotional_intensity * 0.3, 0.0, 1.0)
	# Confidence in claims is not certainty about the world, even after belief admission.
	memory.confidence = 0.6 if memory.source == "player_claim" else 0.9
	if proposal.has("evidence"):
		memory.evidence = proposal.evidence
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
			or not observation.get("status") in ["pending", "classified"] \
			or not _valid_evidence_fields(observation):
			return false
		var timestamp: Variant = observation.get("created_at")
		if not (timestamp is float or timestamp is int) or not is_finite(float(timestamp)):
			return false
		if observation.has("world_minute"):
			var minute: Variant = observation.world_minute
			if not (minute is float or minute is int) or not is_finite(float(minute)) or minute < 0:
				return false
		if not observation.get("decision") is Dictionary or \
			(observation.status == "classified" and not is_valid_policy(observation.decision)):
			return false
	return true

## Optional links from a display entry to the evidence it was built from.
static func _valid_evidence_fields(entry: Dictionary) -> bool:
	if entry.has("observation_id") and (not entry["observation_id"] is String \
			or (entry["observation_id"] as String).is_empty() \
			or (entry["observation_id"] as String).length() > NpcObservation.MAX_OBSERVATION_ID_LENGTH):
		return false
	for key: String in ["source_id", "incident_id"]:
		if entry.has(key) and (not entry[key] is String \
				or (entry[key] as String).length() > NpcObservation.MAX_ID_LENGTH):
			return false
	if entry.has("modality") and (not entry["modality"] is String \
			or not NpcObservation.Modality.has(entry["modality"])):
		return false
	if entry.has("cues"):
		var cues: Variant = entry["cues"]
		if not cues is Array or (cues as Array).size() > NpcObservation.MAX_TAGS:
			return false
		for cue: Variant in cues:
			if not cue is String or (cue as String).length() > NpcObservation.MAX_TAG_LENGTH:
				return false
	return true
