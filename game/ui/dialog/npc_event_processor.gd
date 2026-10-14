class_name NpcEventProcessor
extends Node

## Independent evidence appraisal through NpcDecisionService (v2 `appraise`). Each NPC turn
## appraises one batch (one observation or one coalesced incident) and then yields to the other
## NPCs, which are served round-robin. Failed appraisals stay in the resident's NpcEvidenceInbox
## on its real-time retry ladder, so provider failures defer evidence instead of dropping it.
## Optional speech asks v2 `utterance` first and only then generates text on `/react`.
signal progressed
signal observation_assessed
## `policy` is the safety/rumor view of the appraisal: {safety_response, remember, importance}.
signal perception_classified(npc_id: String, event: Dictionary, policy: Dictionary)

const MAX_WORKERS: int = 2
const MAX_SPEECH_WORKERS: int = 2
## Speech must be displayed within this many simulation minutes of the evidence.
const REACTION_MAX_AGE_MINUTES: float = 30.0
const MAX_ARRIVALS: int = 256
## Dialogue waits at most this long (real time) for pending appraisals.
const ASSESSMENT_WAIT_MSEC: int = 2000
const MAX_STATE_BYTES: int = 16000
const MAX_SUBJECTS: int = 3
const SILENCE: String = "silence"
const _DANGER_KINDS: Array[StringName] = [&"actor_hurt", &"actor_died", &"combat_noise"]

var store: NpcMemoryStore
var decisions: NpcDecisionService
var tuning := NpcBehaviorTuning.new()
var persist: bool = true
var save_callback: Callable
## Monotonic milliseconds for the inbox retry ladder; replaceable in tests.
var clock: Callable = Callable(Time, "get_ticks_msec")
## NPC id -> {profile, current, source}: residents with evidence to appraise.
var _jobs: Dictionary = {}
## Round-robin order of residents waiting for their next turn.
var _order: Array[String] = []
var _active: Dictionary = {}
var _speaking: Dictionary = {}
var _active_speech: int = 0
## Evidence being appraised right now, per NPC (claimed in the inbox, not yet completed or failed).
var _inflight: Dictionary = {}
## Live arrivals, the only evidence that may provoke speech. Never saved: retried or loaded
## evidence has no entry here and never produces speech.
var _arrivals: Dictionary[String, bool] = {}
var _watched: Dictionary[int, bool] = {}

func observe(profile: NpcProfile, current: Dictionary, observation: NpcObservation,
		source: BaseNpc = null) -> void:
	var id: String = String(profile.npc_id)
	var inbox: NpcEvidenceInbox = store.minds.get_mind(id).evidence
	if not inbox.enqueue(observation):
		return # Invalid or already known: a replay must not appraise or display twice.
	if not inbox.contains_pending(observation.observation_id):
		_save() # Counted into an earlier noise item of the same incident; nothing to appraise.
		return
	_remember_arrival(observation.observation_id)
	store.record_observation(profile, observation.to_event(), observation.observed_minute)
	_save()
	resume(profile, current, source)

func resume(profile: NpcProfile, current: Dictionary, source: BaseNpc = null) -> void:
	var id: String = String(profile.npc_id)
	if id.is_empty() or store.minds.get_mind(id).evidence.ready_count(_now()) == 0:
		return
	_jobs[id] = {"profile": profile, "current": current.duplicate(true),
		"source": weakref(source) if source != null else null}
	if source != null and not _watched.has(source.get_instance_id()):
		_watched[source.get_instance_id()] = true
		source.tree_exiting.connect(_on_source_exiting.bind(id, source.get_instance_id()),
			CONNECT_ONE_SHOT)
	if not id in _order and not _active.has(id):
		_order.append(id)
	_drain.call_deferred()

## Stops all work for one NPC (death or removal). In-flight requests settle as cancelled and
## commit nothing; their evidence stays in the inbox for the next resume.
func cancel(npc_id: String) -> void:
	_jobs.erase(npc_id)
	_order.erase(npc_id)
	if decisions != null:
		decisions.cancel_owner(npc_id)

## True while a turn is queued or running for this NPC.
func is_busy(npc_id: String) -> bool:
	return _jobs.has(npc_id) or _active.has(npc_id)

func flush(npc_id: String) -> void:
	while _jobs.has(npc_id) or _active.has(npc_id) or _speaking.has(npc_id):
		await progressed

## Dialogue needs the updated feelings, not a pending optional speech generation, and waits at
## most ASSESSMENT_WAIT_MSEC. Evidence still pending afterwards stays in the conversation context
## as unassessed; deferred evidence is waiting for a retry and does not hold dialogue.
func wait_for_assessment(npc_id: String) -> void:
	var deadline: int = Time.get_ticks_msec() + ASSESSMENT_WAIT_MSEC
	var tree := Engine.get_main_loop() as SceneTree
	while (_inflight.has(npc_id) or store.minds.get_mind(npc_id).evidence.ready_count(-INF) > 0) \
			and Time.get_ticks_msec() < deadline and tree != null:
		await tree.process_frame

func _drain() -> void:
	while _active.size() < MAX_WORKERS and not _order.is_empty():
		var id: String = _order.pop_front()
		if _jobs.has(id) and not _active.has(id):
			_turn(id)

# One batch for one NPC; afterwards the NPC queues behind every other waiting NPC.
func _turn(id: String) -> void:
	_active[id] = true
	var inbox: NpcEvidenceInbox = store.minds.get_mind(id).evidence
	var next: NpcObservation = inbox.next_ready(_now())
	var observation: NpcObservation = inbox.claim(next.observation_id, _now()) if next != null else null
	if observation != null:
		_inflight[id] = true
		await _appraise(id, _jobs[id], observation)
		_inflight.erase(id)
	_active.erase(id)
	if _jobs.has(id):
		if inbox.ready_count(_now()) > 0:
			_order.append(id)
		else:
			_jobs.erase(id)
	progressed.emit()
	observation_assessed.emit()
	_drain.call_deferred()

func _appraise(id: String, job: Dictionary, observation: NpcObservation) -> void:
	var mind: NpcMindState = store.minds.get_mind(id)
	var source: BaseNpc = _source(job)
	var current: Dictionary = job.current.duplicate(true)
	if source != null:
		current = source.get_cognitive_context()
	var state: Dictionary = store.snapshot(id)
	current.recent_events = []
	current.past_observations = NpcCognitiveContext.observations(
		state.get("observations", []).filter(func(item: Dictionary) -> bool:
			return item.get("observation_id") != observation.observation_id \
				and item.status != "pending"), current)
	var reason: String = _speech_block(source, observation)
	var diagnostic: Dictionary = {"speech_eligibility": reason if not reason.is_empty() else
		("already_speaking" if _speaking.has(id) else "allowed")}
	var started: int = Time.get_ticks_msec()
	var evidence: Dictionary = _evidence(observation)
	var subjects: Array[String] = _subjects(id, observation)
	var ticket := NpcDecisionTicket.create(id, NpcDecisionTicket.APPRAISE, _urgency(observation))
	ticket.evidence_ids.append(evidence.id)
	ticket.created_minute = int(store.world_minute)
	var versions: Dictionary = mind.versions()
	ticket.read_versions = {"knowledge": versions.knowledge,
		"relationships": versions.relationships, "condition": versions.condition}
	var memories: Array = NpcMemoryRetriever.new().retrieve(state.get("memories", []),
		observation.text, current, job.profile.get_cognition(), store.world_minute,
		NpcMemoryRetriever.links_for(current))
	var result: NpcDecisionResult = await decisions.evaluate(ticket, {"evidence": [evidence],
		"subjects": subjects, "state": _bounded_state({"npc": job.profile.to_backend_profile(),
			"relationships": _relationships(mind, subjects), "current": current,
			"memories": memories})})
	store.ensure_npc(job.profile)
	diagnostic.assessment_ms = Time.get_ticks_msec() - started
	diagnostic.assessment = NpcDecisionResult.Outcome.keys()[result.outcome]
	if result.outcome == NpcDecisionResult.Outcome.CANCELLED:
		# The owner is gone; nothing is committed and no attempt is counted.
		mind.evidence.release(observation.observation_id)
		_arrivals.erase(observation.observation_id)
		return
	if store.minds.get_mind(id) != mind or mind.evidence.item(observation.observation_id) \
			.get("status") != "CLAIMED":
		# Stale: the mind was reloaded or the claim evicted while appraising; commit nothing.
		_arrivals.erase(observation.observation_id)
		return
	var appraisal: NpcDecisionPolicy.Appraisal = NpcDecisionPolicy.appraisal(result, tuning) \
		if result.is_success() else null
	# Committing completes the inbox claim; a failure defers it along the retry ladder.
	var failure: String = "provider_" + diagnostic.assessment.to_lower() if appraisal == null \
		else store.commit_evidence(id, observation, appraisal)
	var committed: bool = failure.is_empty()
	if committed:
		_wake_backoff()
	else:
		mind.evidence.fail(observation.observation_id, failure, _now())
	diagnostic.speech_result = "not_selected" if committed else "assessment_failed_or_evicted"
	store.annotate_observation(id, observation.observation_id, diagnostic)
	if committed:
		perception_classified.emit(id, observation.to_event(), _safety_view(appraisal))
	var speaks: bool = committed and _speech_block(_source(job), observation).is_empty() \
		and not _speaking.has(id)
	if not speaks:
		_arrivals.erase(observation.observation_id)
	_save()
	observation_assessed.emit()
	if speaks:
		# Optional speech must not hold up any NPC's memory assessment.
		_speaking[id] = true
		_deliver_speech(id, job, observation, appraisal, diagnostic)

func _deliver_speech(id: String, job: Dictionary, observation: NpcObservation,
		appraisal: NpcDecisionPolicy.Appraisal, diagnostic: Dictionary) -> void:
	diagnostic.speech_result = await _speak(id, job, observation, appraisal)
	store.annotate_observation(id, observation.observation_id, diagnostic)
	_save()
	_speaking.erase(id)
	_arrivals.erase(observation.observation_id)
	progressed.emit()

func _speak(id: String, job: Dictionary, observation: NpcObservation,
		appraisal: NpcDecisionPolicy.Appraisal) -> String:
	var permitted: Array[String] = permitted_intents(observation, appraisal)
	var evidence: Dictionary = _evidence(observation)
	var ticket := _speech_ticket(id, evidence.id)
	var source: BaseNpc = _source(job)
	var current: Dictionary = source.get_cognitive_context()
	var intents: Array[String] = permitted.duplicate()
	intents.append(SILENCE)
	var judged: NpcDecisionResult = await decisions.evaluate(ticket, {"evidence": [evidence],
		"intents": intents, "state": _bounded_state({"npc": job.profile.to_backend_profile(),
			"current": current, "immediate_danger": appraisal.immediate_danger})})
	if judged.outcome == NpcDecisionResult.Outcome.CANCELLED:
		return "cancelled"
	if not judged.is_success():
		return "utterance_failed"
	var utterance: NpcDecisionPolicy.Utterance = NpcDecisionPolicy.utterance(judged, permitted, tuning)
	if not utterance.speak:
		return "not_selected"
	source = _source(job)
	var blocked: String = _speech_block(source, observation)
	if not blocked.is_empty():
		return blocked
	while _active_speech >= MAX_SPEECH_WORKERS:
		await progressed
	source = _source(job)
	blocked = _speech_block(source, observation)
	if not blocked.is_empty():
		return blocked
	if not source.reserve_spoken_reaction():
		return "cooldown"
	_active_speech += 1
	var outcome: String = await _generate(id, job, source, observation, utterance.intent)
	_active_speech -= 1
	source = _source(job)
	if outcome != "displayed" and source != null:
		source.release_spoken_reaction()
	return outcome

func _generate(id: String, job: Dictionary, source: BaseNpc, observation: NpcObservation,
		intent: String) -> String:
	var state: Dictionary = store.snapshot(id)
	var current: Dictionary = source.get_cognitive_context()
	var event: Dictionary = observation.to_event()
	event.speech_allowed = true
	var payload: Dictionary = {"protocol_version": 1,
		"npc": {"id": id, "profile": job.profile.to_backend_profile()},
		"player": {"message": ""}, "event": event, "intent": intent,
		"context": {"current": current, "relationship": state.get("relationship", {}),
			"recent_dialogue": NpcMemoryStore.history_for_prompt(
				state.get("recent_dialogue", []), store.world_minute),
			"memories": NpcMemoryRetriever.new().retrieve(state.get("memories", []), event.text,
				current, job.profile.get_cognition(), store.world_minute,
				NpcMemoryRetriever.links_for(current))}}
	var revision: int = store.revision(id)
	var health: int = source.health
	var space: StringName = source.world_space
	var result: NpcDecisionResult = await decisions.run_text(_speech_ticket(id, _evidence(observation).id),
		"/react", payload)
	source = _source(job)
	if source == null:
		return "source_gone"
	if result.outcome == NpcDecisionResult.Outcome.CANCELLED:
		return "cancelled"
	if store.revision(id) != revision or source.health != health or source.world_space != space:
		return "context_changed"
	if not _is_recent(observation):
		return "expired_during_generation"
	var text: Variant = result.body.get("response") if result.is_success() else null
	if not text is String or text.strip_edges().is_empty() or text.length() > 160:
		return "generation_failed"
	if _repeats_recent_speech(source.get_cognitive_context(), text):
		return "repeated_line"
	if source.show_spoken_reaction(text):
		# WorldEvent.speech records actual listeners in ambient history, not player dialogue.
		return "displayed"
	return "dead_or_in_dialogue"

## Speech intents the evidence itself permits; silence is offered separately and never speaks.
static func permitted_intents(observation: NpcObservation,
		appraisal: NpcDecisionPolicy.Appraisal) -> Array[String]:
	var intents: Array[String] = ["remark"]
	if appraisal.immediate_danger or observation.kind in _DANGER_KINDS:
		intents.append_array(["warn", "call_for_help"])
	if observation.modality == NpcObservation.Modality.TOUCH:
		intents.append("protest")
	if observation.kind == &"actor_died":
		intents.append("grieve")
	return intents

static func _repeats_recent_speech(current: Dictionary, text: String) -> bool:
	var normalized: String = " ".join(text.to_lower().strip_edges().split(" ", false))
	if normalized.length() < 12:
		return false # Brief cries and interjections can naturally recur.
	for line: Dictionary in current.get("recent_ambient", []):
		var previous: String = " ".join(String(line.text).to_lower().strip_edges().split(" ", false))
		if previous == normalized:
			return true
	return false

func _speech_ticket(id: String, evidence_id: String) -> NpcDecisionTicket:
	var ticket := NpcDecisionTicket.create(id, NpcDecisionTicket.UTTERANCE)
	ticket.evidence_ids.append(evidence_id)
	ticket.created_minute = int(store.world_minute)
	ticket.read_versions = {"memory": store.revision(id)}
	return ticket

func _speech_block(source: BaseNpc, observation: NpcObservation) -> String:
	if source == null:
		return "source_gone"
	if not _is_recent(observation):
		return "expired_before_assessment"
	if not source.can_speak_reaction():
		return "dead_dialogue_or_cooldown"
	return ""

func _source(job: Dictionary) -> BaseNpc:
	var reference: WeakRef = job.source
	return reference.get_ref() as BaseNpc if reference != null else null

## Only evidence that arrived live in this session can provoke speech, and only while fresh in
## simulation time.
func _is_recent(observation: NpcObservation) -> bool:
	return _arrivals.has(observation.observation_id) \
		and store.world_minute - observation.observed_minute <= REACTION_MAX_AGE_MINUTES

func _remember_arrival(observation_id: String) -> void:
	if _arrivals.size() >= MAX_ARRIVALS:
		_arrivals.erase(_arrivals.keys()[0])
	_arrivals[observation_id] = true

func _on_source_exiting(npc_id: String, instance_id: int) -> void:
	_watched.erase(instance_id)
	cancel(npc_id)

# A healthy provider releases every resident's evidence waiting past the retry ladder.
func _wake_backoff() -> void:
	for npc_id: String in store.minds.ids():
		store.minds.get_mind(npc_id).evidence.wake_backoff()

func _now() -> float:
	return float(clock.call())

static func _urgency(observation: NpcObservation) -> NpcDecisionTicket.Urgency:
	return NpcDecisionTicket.Urgency.SAFETY if observation.kind in _DANGER_KINDS \
		or observation.modality == NpcObservation.Modality.TOUCH \
		else NpcDecisionTicket.Urgency.BACKGROUND

static func _evidence(observation: NpcObservation) -> Dictionary:
	var participants: Array[String] = []
	for participant: String in observation.participant_ids():
		if _is_id(participant) and participants.size() < 8:
			participants.append(participant)
	return {"id": observation.observation_id if _is_id(observation.observation_id)
			else "ev:%d" % absi(observation.observation_id.hash()),
		"text": observation.text.substr(0, 1000),
		"modality": String(NpcObservation.Modality.keys()[observation.modality]).to_lower(),
		"source_id": observation.source_id.substr(0, 100), "participant_ids": participants}

## The people direct evidence identifies, other than the observer: whose dispositions it may change.
static func _subjects(id: String, observation: NpcObservation) -> Array[String]:
	var subjects: Array[String] = []
	if not observation.modality in [NpcObservation.Modality.SIGHT, NpcObservation.Modality.TOUCH]:
		return subjects
	for participant: String in observation.participant_ids():
		if participant != id and _is_id(participant) and not participant in subjects \
				and subjects.size() < MAX_SUBJECTS:
			subjects.append(participant)
	return subjects

static func _relationships(mind: NpcMindState, subjects: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for subject: String in subjects:
		result[subject] = mind.relationships.get_relationship(subject)
	return result

## Drops the least essential context until the state fits the envelope limit.
static func _bounded_state(state: Dictionary) -> Dictionary:
	for key: String in ["memories", "current", "npc_knowledge"]:
		if JSON.stringify(state).to_utf8_buffer().size() <= MAX_STATE_BYTES:
			break
		if key == "npc_knowledge":
			state.npc.erase("knowledge")
		else:
			state.erase(key)
	return state

static func _safety_view(appraisal: NpcDecisionPolicy.Appraisal) -> Dictionary:
	var response: String = "SHELTER" if appraisal.immediate_danger \
		else "CAUTION" if appraisal.emotions.get("fear", 0.0) >= 0.5 else "NONE"
	return {"safety_response": response, "remember": appraisal.remember,
		"importance": appraisal.importance}

static func _is_id(value: String) -> bool:
	return value.length() >= 1 and value.length() <= 100 \
		and RegEx.create_from_string("^[A-Za-z0-9_:-]+$").search(value) != null

func _save() -> void:
	if not persist:
		return
	if not save_callback.is_valid():
		push_error("NPC event processor cannot persist without a save callback.")
		return
	var error: Error = save_callback.call()
	if error != OK:
		push_warning("NPC observation could not be saved: %s" % error)
