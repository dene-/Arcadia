class_name NpcEventProcessor
extends Node

## Independent event classification, with one worker per NPC and two requests at a time.
signal progressed
signal observation_assessed
signal perception_classified(npc_id: String, event: Dictionary, policy: Dictionary)

const MAX_WORKERS: int = 2
const MAX_SPEECH_WORKERS: int = 2
const REACTION_MAX_AGE: float = 20.0

var store: NpcMemoryStore
var backend: DialogBackendClient
var persist: bool = true
var save_callback: Callable
var _queued: Dictionary = {}
var _active: Dictionary = {}
var _speaking: Dictionary = {}

func observe(profile: NpcProfile, current: Dictionary, event: Dictionary,
		source: BaseNpc = null) -> void:
	store.record_observation(profile, event)
	_save()
	resume(profile, current, source)

func resume(profile: NpcProfile, current: Dictionary, source: BaseNpc = null) -> void:
	var id: String = String(profile.npc_id)
	if store.pending_observations(id).is_empty():
		return
	_queued[id] = {"profile": profile, "current": current.duplicate(true),
		"source": weakref(source) if source != null else null}
	_drain.call_deferred()

func flush(npc_id: String) -> void:
	while _queued.has(npc_id) or _active.has(npc_id) or _speaking.has(npc_id):
		await progressed

## Dialogue needs the updated feelings, not a pending optional speech generation.
func wait_for_assessment(npc_id: String) -> void:
	while not store.pending_observations(npc_id).is_empty():
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
	var pending: Array[Dictionary] = store.pending_observations(id)
	while not pending.is_empty():
		if _queued.has(id):
			job = _queued[id]
			_queued.erase(id)
		var event: Dictionary = pending[0]
		var state: Dictionary = store.snapshot(id)
		var source: BaseNpc = _source(job)
		var current: Dictionary = job.current.duplicate(true)
		if source != null:
			current = source.get_cognitive_context()
		current.recent_events = []
		current.past_observations = NpcCognitiveContext.observations(
			state.observations.filter(func(item: Dictionary) -> bool:
				return item.id != event.id and item.status != "pending"))
		var reason: String = _speech_block(source, event)
		event.speech_allowed = reason.is_empty() and not _speaking.has(id)
		var started: int = Time.get_ticks_msec()
		var diagnostic: Dictionary = {"speech_eligibility": reason if not reason.is_empty() else
			("already_speaking" if _speaking.has(id) else "allowed"),
			"queue_age_seconds": Time.get_unix_time_from_system() - event.created_at}
		var payload: Dictionary = {"protocol_version": 1,
			"npc": {"id": id, "profile": job.profile.to_backend_profile()},
			"player": {"message": ""}, "event": event,
			"context": {"current": current, "relationship": state.relationship,
				"recent_dialogue": state.recent_dialogue, "memories": []}}
		var judgment: Dictionary = await backend.request_observation(payload)
		var policy: Dictionary = judgment.get("policy", {})
		var committed: bool = store.commit_observation(id, int(event.id), policy)
		diagnostic.assessment_ms = Time.get_ticks_msec() - started
		var speech_answer: Dictionary = judgment.get("answers", {}).get("should_speak", {})
		diagnostic.speech_probability = speech_answer.get("noul", -1.0)
		diagnostic.speech_result = "not_selected" if committed else "assessment_failed_or_evicted"
		if committed and policy.get("speak", false):
			diagnostic.speech_result = "selected"
		store.annotate_observation(id, int(event.id), diagnostic)
		if committed:
			perception_classified.emit(id, event, policy)
		_save()
		observation_assessed.emit()
		if committed and policy.get("speak", false) and not _speaking.has(id):
			# Optional text generation must not hold up any NPC's memory assessment.
			_speaking[id] = true
			_deliver_speech(job, payload, judgment, diagnostic)
		pending = store.pending_observations(id)
	# New arrivals are included by the loop; remove any redundant scheduling entry.
	_queued.erase(id)
	_active.erase(id)
	progressed.emit()
	_drain.call_deferred()

func _deliver_speech(job: Dictionary, payload: Dictionary, judgment: Dictionary,
		diagnostic: Dictionary) -> void:
	diagnostic.speech_result = await _speak(job, payload, judgment)
	store.annotate_observation(payload.npc.id, int(payload.event.id), diagnostic)
	_save()
	_speaking.erase(payload.npc.id)
	progressed.emit()

func _speak(job: Dictionary, payload: Dictionary, judgment: Dictionary) -> String:
	# This job is already reserved. Capacity can change while its assessment is in flight.
	if _speaking.size() > MAX_SPEECH_WORKERS:
		return "speech_capacity"
	var source: BaseNpc = _source(job)
	var blocked: String = _speech_block(source, payload.event, false)
	if not blocked.is_empty():
		return blocked
	if not source.reserve_spoken_reaction():
		return "cooldown"
	var state: Dictionary = store.snapshot(payload.npc.id)
	payload.context.relationship = state.relationship
	payload.context.memories = NpcMemoryRetriever.new().retrieve(state.memories,
		payload.event.text, payload.context.current, job.profile.get_cognition(), store.turn)
	payload.answers = judgment.get("answers", {})
	var result: Dictionary = await backend.request_reaction(payload)
	source = _source(job)
	var text: Variant = result.get("response")
	if source == null:
		return "source_gone"
	if not _is_recent(payload.event):
		return "expired_during_generation"
	if not text is String or text.strip_edges().is_empty() or text.length() > 160:
		return "generation_failed"
	if source.show_spoken_reaction(text):
		store.record_spoken_reaction(payload.npc.id, text)
		return "displayed"
	return "dead_or_in_dialogue"

func _speech_block(source: BaseNpc, event: Dictionary, check_capacity: bool = true) -> String:
	if source == null:
		return "source_gone"
	if not _is_recent(event):
		return "expired_before_assessment"
	if check_capacity and _speaking.size() >= MAX_SPEECH_WORKERS:
		return "speech_capacity"
	if not source.can_speak_reaction():
		return "dead_dialogue_or_cooldown"
	return ""

func _source(job: Dictionary) -> BaseNpc:
	var reference: WeakRef = job.source
	return reference.get_ref() as BaseNpc if reference != null else null

func _is_recent(event: Dictionary) -> bool:
	return Time.get_unix_time_from_system() - float(event.created_at) <= REACTION_MAX_AGE

func _save() -> void:
	if persist:
		var error: Error = save_callback.call() if save_callback.is_valid() else store.save_file()
		if error != OK:
			push_warning("NPC observation could not be saved: %s" % error)
