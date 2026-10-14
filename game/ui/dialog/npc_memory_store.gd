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
		NpcMemory.anchor_legacy(memory, world_minute)
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
	# Listening dispositions (NpcDecisionPolicy.listening) pass through the listener's incident
	# budget; every retelling of one origin shares that origin's budget and receipts. A weak
	# account can change how the listener sees the messenger, never the people it is about.
	var dispositions: Dictionary = policy.get("dispositions", {})
	if not dispositions.is_empty():
		var heard := NpcObservation.new()
		heard.observation_id = "hearsay:%s:%s" % [profile.npc_id, account.origin_id]
		heard.origin_id = account.origin_id
		heard.incident_id = account.origin_id
		heard.observer_id = String(profile.npc_id)
		heard.kind = &"hearsay"
		heard.modality = NpcObservation.Modality.SPOKEN_REPORT
		heard.observed_minute = world_minute
		heard.source_id = account.source_id
		heard.text = String(account.text).substr(0, NpcObservation.MAX_TEXT_LENGTH)
		var mind: NpcMindState = minds.get_mind(String(profile.npc_id))
		for subject: String in dispositions:
			if subject != account.source_id and float(account.confidence) < 0.7:
				continue
			mind.apply_evidence_delta(subject, heard, dispositions[subject],
				"%s:%s" % [heard.observation_id, subject])
	if not policy.remember:
		return
	var gist: String = "%s told me that %s reported: %s" % [account.source_name,
		account.originator_name, account.text]
	var memory: Dictionary = NpcMemory.create(id, "episodic", gist.substr(0, 500), "hearsay", turn)
	memory.created_minute = world_minute
	memory.date_known = true
	memory.confidence = account.confidence
	memory.importance = policy.importance
	memory.topics = ["town", "news"]
	memory.people = ["player"] if account.player_involved else []
	memory.observation_kind = "rumor"
	memory.modality = "speech"
	memory.incident_id = ""
	memory.origin_id = account.origin_id
	memory.evidence_ids = []
	memory.observed_minute = NpcMemory.UNKNOWN_MINUTE
	memory.chain = _speakers(account.get("chain", []), String(profile.npc_id))
	if NpcMemory.is_valid(memory):
		state.memories.append(memory)

# Rumor chain (originator first, listener last) as the speakers before `listener`, newest first.
static func _speakers(chain: Variant, listener: String) -> Array[String]:
	var speakers: Array[String] = []
	if not chain is Array:
		return speakers
	for index: int in range((chain as Array).size() - 1, -1, -1):
		var speaker: Variant = chain[index]
		if speaker is String and not (speaker as String).is_empty() and speaker != listener \
				and speakers.size() < NpcMemory.MAX_CHAIN:
			speakers.append(speaker)
	return speakers

## Bounded archive and receipt upkeep, run on the world schedule. `live_origins` are the rumor
## origins anyone can still retell (TownRumors.live_origins): while an origin is live its receipts
## and `heard_origins` entry are kept, so a retold story can never be admitted twice. A receipt is
## also kept while an inbox item, open commitment or running duty references it or its origin.
## Returns counts of the memories merged away, receipts pruned and heard origins forgotten.
func maintain(live_origins: Dictionary, minute: float) -> Dictionary:
	var result: Dictionary = {"memories_merged": 0, "receipts_pruned": 0, "origins_pruned": 0}
	var ids: Array[String] = minds.ids()
	for npc_id: String in _states:
		if not npc_id in ids:
			ids.append(npc_id)
	ids.sort()
	for npc_id: String in ids:
		var mind: NpcMindState = minds.get_mind(npc_id)
		var references: Dictionary = live_origins.duplicate()
		for observation: NpcObservation in mind.evidence.pending_observations():
			references[observation.observation_id] = true
			references[observation.origin_id] = true
		var cited: Array = mind.task_checkpoint().get("evidence_ids", []).duplicate()
		for commitment: Dictionary in mind.commitments.open_commitments():
			cited.append_array(commitment["evidence_ids"])
		for evidence_id: Variant in cited:
			references[evidence_id] = true
			var origin: String = mind.evidence.receipt_origin(evidence_id)
			if not origin.is_empty():
				references[origin] = true
		result.receipts_pruned += mind.evidence.compact(references) \
			+ mind.relationships.compact(references)
		if not _states.has(npc_id):
			continue
		var state: Dictionary = _states[npc_id]
		for origin: String in state.heard_origins.keys():
			if not live_origins.has(origin):
				state.heard_origins.erase(origin)
				result.origins_pruned += 1
		var merged: int = NpcMemoryConsolidator.consolidate(state.memories,
			_protected_refs(mind, cited), minute)
		result.memories_merged += merged
		# Only the archive feeds responses; forgotten receipts cannot invalidate one.
		if merged > 0:
			_changed(npc_id)
	return result

# Evidence and origins whose episodes must stay as they are: cited by an open commitment or
# running duty, or behind a contested belief.
static func _protected_refs(mind: NpcMindState, cited: Array) -> Dictionary:
	var refs: Dictionary = {}
	for evidence_id: Variant in cited:
		refs[evidence_id] = true
	for fact: Dictionary in mind.knowledge.to_data().get("facts", []):
		if fact.get("status") == "CONTESTED":
			for ref: Variant in fact.get("evidence_ids", []) + fact.get("origin_ids", []):
				refs[ref] = true
	return refs

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

## Applies an appraisal (NpcDecisionPolicy.appraisal) to evidence the mind's inbox has claimed.
## The inbox claim is completed first and its receipt is what makes the appraisal happen once:
## when completion fails nothing changes, and a completed claim always carries its effects.
## Returns "" on success (re-committing an already receipted observation is a successful no-op)
## or why nothing was committed: "invalid_observation", "store_unavailable" (this NPC has no
## memory state), "invalid_appraisal", "receipts_full" (every stored receipt is still
## replayable; upkeep frees room once origins expire) or "not_claimed".
func commit_evidence(npc_id: String, observation: NpcObservation,
		appraisal: NpcDecisionPolicy.Appraisal) -> String:
	if observation == null or observation.observation_id.is_empty():
		return "invalid_observation"
	if not _states.has(npc_id):
		return "store_unavailable"
	var record: Dictionary = appraisal_record(appraisal) if appraisal != null else {}
	if not is_valid_appraisal_record(record):
		return "invalid_appraisal"
	var mind: NpcMindState = minds.get_mind(npc_id)
	if mind.evidence.has_receipt(observation.observation_id):
		return ""
	if mind.evidence.receipt_count() >= NpcEvidenceInbox.MAX_RECEIPTS:
		return "receipts_full"
	if not mind.evidence.complete(observation.observation_id):
		return "not_claimed"
	var state: Dictionary = _states[npc_id]
	_changed(npc_id)
	for entry: Dictionary in state.observations:
		if entry.get("observation_id") == observation.observation_id:
			entry.status = "classified"
			entry.decision = record.duplicate(true)
	advance_time()
	# Only direct evidence about an evidenced participant changes feelings; hearing noise or a
	# report cannot identify anyone. Each subject spends through the M6 incident budget.
	if observation.modality in [NpcObservation.Modality.SIGHT, NpcObservation.Modality.TOUCH]:
		var evidenced: Array[String] = observation.participant_ids()
		for subject: String in appraisal.dispositions:
			if subject in evidenced and subject != npc_id:
				mind.apply_evidence_delta(subject, observation, appraisal.dispositions[subject],
					"observation:%s:%s:%s" % [npc_id, observation.observation_id, subject])
	if appraisal.remember:
		var people: Array[String] = observation.participant_ids()
		if not observation.source_id.is_empty() and not observation.source_id in people:
			people.append(observation.source_id)
		var topics: Array[String] = observation.topics.slice(0, 8)
		if topics.is_empty():
			topics.append(String(observation.kind) if observation.kind != &"unknown" else "event")
		var report: bool = observation.modality == NpcObservation.Modality.SPOKEN_REPORT
		_admit(state.memories, {"type": "episodic",
			"source": "hearsay" if report else "observed_event",
			"gist": observation.text, "topics": topics, "people": people.slice(0, 8),
			"sensory_cues": observation.cues.slice(0, 8)},
			{"importance": record.importance, "emotional_intensity": record.emotional_intensity,
				"update_belief": false}, _evidence_of(observation))
	return ""

## The saved, display-only summary of an appraisal on its observation entry.
static func appraisal_record(appraisal: NpcDecisionPolicy.Appraisal) -> Dictionary:
	var intensity: float = 0.0
	for emotion: String in appraisal.emotions:
		intensity = maxf(intensity, appraisal.emotions[emotion])
	return {"immediate_danger": appraisal.immediate_danger, "remember": appraisal.remember,
		"importance": appraisal.importance, "emotional_intensity": intensity,
		"emotions": appraisal.emotions.duplicate(), "dispositions": appraisal.dispositions.duplicate(true)}

static func is_valid_appraisal_record(record: Variant) -> bool:
	if not record is Dictionary or not record.get("immediate_danger") is bool \
			or not record.get("remember") is bool or not NpcMemory.is_unit(record.get("importance")) \
			or not NpcMemory.is_unit(record.get("emotional_intensity")) \
			or not record.get("emotions") is Dictionary or not record.get("dispositions") is Dictionary:
		return false
	for emotion: Variant in record.emotions:
		if not emotion is String or not NpcMemory.is_unit(record.emotions[emotion]):
			return false
	for subject: Variant in record.dispositions:
		if not subject is String or not record.dispositions[subject] is Dictionary:
			return false
		for dimension: Variant in record.dispositions[subject]:
			var delta: Variant = record.dispositions[subject][dimension]
			if not dimension is String or not (delta is int or delta is float) \
					or not is_finite(float(delta)):
				return false
	return true

# Memory evidence fields of one observation.
func _evidence_of(observation: NpcObservation) -> Dictionary:
	var chain: Array[String] = []
	if observation.modality == NpcObservation.Modality.SPOKEN_REPORT \
			and not observation.source_id.is_empty():
		chain.append(observation.source_id)
	var observed: float = observation.observed_minute
	return {"observation_kind": String(observation.kind).substr(0, NpcMemory.MAX_ID_LENGTH),
		"modality": NpcMemory.modality_of(observation), "incident_id": observation.incident_id,
		"origin_id": observation.origin_id if not observation.origin_id.is_empty()
			else observation.observation_id,
		"evidence_ids": [observation.observation_id],
		"observed_minute": observed if is_finite(observed) and observed >= 0.0
			else NpcMemory.UNKNOWN_MINUTE,
		"chain": chain}

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

## Commits one delivered player exchange of conversation session `session_id`.
func commit_exchange(npc_id: String, message: String, result: Dictionary,
		policy: Dictionary, recalled: Array, consumed_events: Array, session_id: String) -> bool:
	if message.length() > 2000 or not _states.has(npc_id) or session_id.is_empty() \
		or not is_valid_result(result) or not is_valid_policy(policy):
		return false
	var state: Dictionary = _states[npc_id]
	_changed(npc_id)
	advance_time()
	minds.get_mind(npc_id).relationships.apply_delta("player", policy.relationship_delta,
		"exchange:%s:%d" % [npc_id, turn])
	var history: Array = state.recent_dialogue
	if not message.is_empty():
		history.append({"speaker": "player", "text": message, "session_id": session_id,
			"minute": world_minute, "delivered": true})
	history.append({"speaker": "npc", "text": result.response, "session_id": session_id,
		"minute": world_minute, "delivered": true})
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
			NpcMemory.anchor_legacy(memory, load_minute)
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

## `evidence` holds the NpcMemory evidence fields of perceived evidence, never model output.
func _admit(memories: Array, proposal: Variant, policy: Dictionary, evidence: Dictionary = {}) -> void:
	if not proposal is Dictionary:
		return
	var memory: Dictionary = NpcMemory.create("mem:%d" % _next_memory_id,
		str(proposal.get("type", "")), str(proposal.get("gist", "")),
		str(proposal.get("source", "")), turn)
	var observed: float = float(evidence.get("observed_minute", NpcMemory.UNKNOWN_MINUTE))
	memory.created_minute = observed if observed >= 0.0 and observed <= world_minute else world_minute
	memory.date_known = true
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
	memory.merge(evidence.duplicate(true), true)
	if not NpcMemory.is_valid(memory):
		return
	# Hearing a report and seeing the event stay distinct memories, as do separate incidents.
	for existing: Dictionary in memories:
		if existing.gist.to_lower() == memory.gist.to_lower() and existing.source == memory.source \
				and existing.get("modality", "") == memory.get("modality", "") \
				and existing.get("incident_id", "") == memory.get("incident_id", ""):
			# Repetition is not a new memory; it only records which evidence it rests on.
			for evidence_id: String in memory.get("evidence_ids", []):
				var ids: Array = existing.get("evidence_ids", [])
				if not evidence_id in ids and ids.size() < NpcMemory.MAX_EVIDENCE_IDS:
					ids.append(evidence_id)
					existing.evidence_ids = ids
			return
	memories.append(memory)
	_next_memory_id += 1

func _valid_history(value: Variant) -> bool:
	if not value is Array or value.size() > MAX_HISTORY:
		return false
	for entry: Variant in value:
		if not entry is Dictionary or not entry.get("speaker") in ["npc", "player"] \
			or not entry.get("text") is String or entry.text.length() > 6000 \
			or not is_valid_session_entry(entry):
			return false
	return true

static func is_valid_session_entry(entry: Dictionary) -> bool:
	var minute: Variant = entry.get("minute")
	return entry.get("session_id") is String and not (entry.session_id as String).is_empty() \
		and (minute is float or minute is int) and is_finite(float(minute)) \
		and (float(minute) >= 0.0 or float(minute) == -1.0) and entry.get("delivered") is bool

## Prompt view of dialogue or social history: each entry's minute becomes `age_game_minutes`
## ("unknown" when it was never recorded) and `session` says whether it belongs to `current_session`
## (started at `session_start`), an earlier session, or the pre-session legacy history.
static func history_for_prompt(entries: Array, now: float, current_session: String = "",
		session_start: float = -1.0) -> Array[Dictionary]:
	var view: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var shown: Dictionary = entry.duplicate()
		var minute: float = float(entry.get("minute", -1.0))
		shown.erase("minute")
		shown["age_game_minutes"] = "unknown" if minute < 0.0 else maxf(0.0, now - minute)
		if entry.get("session_id") == NpcSaveMigration.LEGACY_SESSION:
			shown["session"] = "legacy"
		elif not current_session.is_empty() and entry.get("session_id") == current_session \
				and minute >= session_start:
			shown["session"] = "current"
		else:
			shown["session"] = "earlier"
		view.append(shown)
	return view

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
		# Saves written before M7 hold the v1 observation policy as the display decision.
		if not observation.get("decision") is Dictionary or (observation.status == "classified" \
				and not is_valid_appraisal_record(observation.decision) \
				and not is_valid_policy(observation.decision)):
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
