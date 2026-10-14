class_name NpcEventProcessor
extends Node

## Independent evidence appraisal, with one worker per NPC and two requests at a time. Evidence
## waits in the resident's NpcEvidenceInbox, so provider failures defer it instead of dropping it.
signal progressed
signal observation_assessed
signal perception_classified(npc_id: String, event: Dictionary, policy: Dictionary)

const MAX_WORKERS: int = 2
const MAX_SPEECH_WORKERS: int = 2
const REACTION_MAX_AGE: float = 20.0
const MAX_ARRIVALS: int = 256

var store: NpcMemoryStore
var backend: DialogBackendClient
var persist: bool = true
var save_callback: Callable
var _queued: Dictionary = {}
var _active: Dictionary = {}
var _speaking: Dictionary = {}
var _active_speech: int = 0
## Evidence being appraised right now, per NPC (claimed in the inbox, not yet completed or failed).
var _inflight: Dictionary = {}
## Real-time arrival of each observation, only for reaction freshness. Never saved: evidence
## that was retried or loaded from a save has no entry here and never produces speech.
var _arrivals: Dictionary[String, float] = {}

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
	if id.is_empty() or store.minds.get_mind(id).evidence.ready_count(store.world_minute) == 0:
		return
	_queued[id] = {"profile": profile, "current": current.duplicate(true),
		"source": weakref(source) if source != null else null}
	_drain.call_deferred()

## True while a worker is queued or running for this NPC.
func is_busy(npc_id: String) -> bool:
	return _queued.has(npc_id) or _active.has(npc_id)

func flush(npc_id: String) -> void:
	while _queued.has(npc_id) or _active.has(npc_id) or _speaking.has(npc_id):
		await progressed

## Dialogue needs the updated feelings, not a pending optional speech generation. Deferred
## evidence is waiting for a retry, not for this assessment, so it does not hold dialogue.
func wait_for_assessment(npc_id: String) -> void:
	while _inflight.has(npc_id) \
			or store.minds.get_mind(npc_id).evidence.ready_count(-INF) > 0:
		await observation_assessed

func _drain() -> void:
	for id: String in _queued.keys():
		if _active.size() >= MAX_WORKERS:
			break
		if _active.has(id):
			continue
		var job: Dictionary = _queued[id]
		_queued.erase(id)
		_active[id] = true
		_process_npc(id, job)

func _process_npc(id: String, job: Dictionary) -> void:
	var inbox: NpcEvidenceInbox = store.minds.get_mind(id).evidence
	while true:
		if _queued.has(id):
			job = _queued[id]
			_queued.erase(id)
		var next: NpcObservation = inbox.next_ready(store.world_minute)
		var observation: NpcObservation = \
			inbox.claim(next.observation_id, store.world_minute) if next != null else null
		if observation == null:
			break
		_inflight[id] = true
		await _appraise(id, job, observation)
	# New arrivals are included by the loop; remove any redundant scheduling entry.
	_queued.erase(id)
	_active.erase(id)
	progressed.emit()
	# A waiter may have been woken before the worker released this NPC.
	observation_assessed.emit()
	_drain.call_deferred()

func _appraise(id: String, job: Dictionary, observation: NpcObservation) -> void:
	var state: Dictionary = store.snapshot(id)
	var source: BaseNpc = _source(job)
	var current: Dictionary = job.current.duplicate(true)
	if source != null:
		current = source.get_cognitive_context()
	current.recent_events = []
	current.past_observations = NpcCognitiveContext.observations(
		state.get("observations", []).filter(func(item: Dictionary) -> bool:
			return item.get("observation_id") != observation.observation_id \
				and item.status != "pending"), current)
	var event: Dictionary = observation.to_event()
	var reason: String = _speech_block(source, observation.observation_id)
	event.speech_allowed = reason.is_empty() and not _speaking.has(id)
	var started: int = Time.get_ticks_msec()
	var diagnostic: Dictionary = {"speech_eligibility": reason if not reason.is_empty() else
		("already_speaking" if _speaking.has(id) else "allowed"),
		"queue_age_seconds": _age(observation.observation_id)}
	var payload: Dictionary = {"protocol_version": 1,
		"npc": {"id": id, "profile": job.profile.to_backend_profile()},
		"player": {"message": ""}, "event": event,
		"context": {"current": current, "relationship": state.get("relationship", {}),
			"recent_dialogue": NpcMemoryStore.history_for_prompt(
				state.get("recent_dialogue", []), store.world_minute),
			"memories": NpcMemoryRetriever.new().retrieve(state.get("memories", []), event.text,
				current, job.profile.get_cognition(), store.world_minute,
				NpcMemoryRetriever.links_for(current))}}
	var judgment: Dictionary = await backend.request_observation(payload)
	var policy: Variant = judgment.get("policy", {})
	store.ensure_npc(job.profile)
	# Committing completes the inbox claim; a failure leaves the claim for the inbox to retry.
	var failure: String = "provider_unavailable" if judgment.is_empty() or not policy is Dictionary \
		or (policy as Dictionary).is_empty() else store.commit_evidence(id, observation, policy)
	var committed: bool = failure.is_empty()
	if not committed:
		store.minds.get_mind(id).evidence.fail(observation.observation_id, failure, store.world_minute)
	_inflight.erase(id)
	diagnostic.assessment_ms = Time.get_ticks_msec() - started
	var speech_answer: Dictionary = judgment.get("answers", {}).get("should_speak", {})
	diagnostic.speech_probability = speech_answer.get("noul", -1.0)
	diagnostic.speech_result = "not_selected" if committed else "assessment_failed_or_evicted"
	var speaks: bool = committed and policy.get("speak", false)
	if speaks:
		diagnostic.speech_result = "selected"
	store.annotate_observation(id, observation.observation_id, diagnostic)
	if committed:
		perception_classified.emit(id, observation.to_event(), policy)
	if not speaks:
		_arrivals.erase(observation.observation_id)
	_save()
	observation_assessed.emit()
	if speaks and not _speaking.has(id):
		# Optional text generation must not hold up any NPC's memory assessment.
		_speaking[id] = true
		_deliver_speech(job, payload, judgment, diagnostic, observation.observation_id)

func _deliver_speech(job: Dictionary, payload: Dictionary, judgment: Dictionary,
		diagnostic: Dictionary, observation_id: String) -> void:
	while _active_speech >= MAX_SPEECH_WORKERS and _is_recent(observation_id):
		await progressed
	if not _is_recent(observation_id):
		diagnostic.speech_result = "expired_before_generation"
	else:
		_active_speech += 1
		diagnostic.speech_result = await _speak(job, payload, judgment, observation_id)
		_active_speech -= 1
	store.annotate_observation(payload.npc.id, observation_id, diagnostic)
	_save()
	_speaking.erase(payload.npc.id)
	_arrivals.erase(observation_id)
	progressed.emit()

func _speak(job: Dictionary, payload: Dictionary, judgment: Dictionary,
		observation_id: String) -> String:
	var source: BaseNpc = _source(job)
	var blocked: String = _speech_block(source, observation_id)
	if not blocked.is_empty():
		return blocked
	if not source.reserve_spoken_reaction():
		return "cooldown"
	var state: Dictionary = store.snapshot(payload.npc.id)
	payload.context.current.merge(source.get_cognitive_context(), true)
	payload.context.relationship = state.relationship
	payload.context.memories = NpcMemoryRetriever.new().retrieve(state.memories,
		payload.event.text, payload.context.current, job.profile.get_cognition(), store.world_minute,
		NpcMemoryRetriever.links_for(payload.context.current))
	payload.answers = judgment.get("answers", {})
	var revision: int = store.revision(payload.npc.id)
	var health: int = source.health
	var space: StringName = source.world_space
	var result: Dictionary = await backend.request_reaction(payload)
	source = _source(job)
	var text: Variant = result.get("response")
	if source == null:
		return "source_gone"
	if store.revision(payload.npc.id) != revision or source.health != health \
		or source.world_space != space:
		return "context_changed"
	if not _is_recent(observation_id):
		return "expired_during_generation"
	if not text is String or text.strip_edges().is_empty() or text.length() > 160:
		return "generation_failed"
	if _repeats_recent_speech(source.get_cognitive_context(), text):
		return "repeated_line"
	if source.show_spoken_reaction(text):
		# WorldEvent.speech records actual listeners in ambient history, not player dialogue.
		return "displayed"
	return "dead_or_in_dialogue"

static func _repeats_recent_speech(current: Dictionary, text: String) -> bool:
	var normalized: String = " ".join(text.to_lower().strip_edges().split(" ", false))
	if normalized.length() < 12:
		return false # Brief cries and interjections can naturally recur.
	for line: Dictionary in current.get("recent_ambient", []):
		var previous: String = " ".join(String(line.text).to_lower().strip_edges().split(" ", false))
		if previous == normalized:
			return true
	return false

func _speech_block(source: BaseNpc, observation_id: String) -> String:
	if source == null:
		return "source_gone"
	if not _is_recent(observation_id):
		return "expired_before_assessment"
	if not source.can_speak_reaction():
		return "dead_dialogue_or_cooldown"
	return ""

func _source(job: Dictionary) -> BaseNpc:
	var reference: WeakRef = job.source
	return reference.get_ref() as BaseNpc if reference != null else null

## Only evidence that arrived live in this session can provoke speech, and only while fresh.
func _is_recent(observation_id: String) -> bool:
	return _arrivals.has(observation_id) \
		and Time.get_unix_time_from_system() - _arrivals[observation_id] <= REACTION_MAX_AGE

func _age(observation_id: String) -> float:
	return Time.get_unix_time_from_system() - _arrivals[observation_id] \
		if _arrivals.has(observation_id) else -1.0

func _remember_arrival(observation_id: String) -> void:
	var now: float = Time.get_unix_time_from_system()
	if _arrivals.size() >= MAX_ARRIVALS:
		for key: String in _arrivals.keys():
			if now - _arrivals[key] > REACTION_MAX_AGE:
				_arrivals.erase(key)
	if _arrivals.size() < MAX_ARRIVALS:
		_arrivals[observation_id] = now

func _save() -> void:
	if not persist:
		return
	if not save_callback.is_valid():
		push_error("NPC event processor cannot persist without a save callback.")
		return
	var error: Error = save_callback.call()
	if error != OK:
		push_warning("NPC observation could not be saved: %s" % error)
