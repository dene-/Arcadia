class_name NpcEventProcessor
extends Node

## Independent event classification, with one worker per NPC and two requests at a time.
signal progressed
signal observation_assessed

const MAX_WORKERS: int = 2
const REACTION_MAX_AGE: float = 20.0

var store: NpcMemoryStore
var backend: DialogBackendClient
var persist: bool = true
var _queued: Dictionary = {}
var _active: Dictionary = {}

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
	while _queued.has(npc_id) or _active.has(npc_id):
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
		var current: Dictionary = job.current.duplicate(true)
		current.recent_events = []
		current.past_observations = state.observations.filter(func(item: Dictionary) -> bool:
			return item.id != event.id and item.status != "pending")
		var source: BaseNpc = _source(job)
		event.speech_allowed = source != null and source.can_speak_reaction() and _is_recent(event)
		var payload: Dictionary = {"protocol_version": 1,
			"npc": {"id": id, "profile": job.profile.to_backend_profile()},
			"player": {"message": ""}, "event": event,
			"context": {"current": current, "relationship": state.relationship,
				"recent_dialogue": state.recent_dialogue, "memories": []}}
		var judgment: Dictionary = await backend.request_observation(payload)
		var policy: Dictionary = judgment.get("policy", {})
		var committed: bool = store.commit_observation(id, int(event.id), policy)
		_save()
		observation_assessed.emit()
		if committed and policy.get("speak", false):
			await _speak(job, payload, judgment)
		pending = store.pending_observations(id)
	# New arrivals are included by the loop; remove any redundant scheduling entry.
	_queued.erase(id)
	_active.erase(id)
	progressed.emit()
	_drain.call_deferred()

func _speak(job: Dictionary, payload: Dictionary, judgment: Dictionary) -> void:
	var source: BaseNpc = _source(job)
	if source == null or not _is_recent(payload.event) or not source.reserve_spoken_reaction():
		return
	var state: Dictionary = store.snapshot(payload.npc.id)
	payload.context.relationship = state.relationship
	payload.context.memories = NpcMemoryRetriever.new().retrieve(state.memories,
		payload.event.text, payload.context.current, job.profile.get_cognition(), store.turn)
	payload.answers = judgment.get("answers", {})
	var result: Dictionary = await backend.request_reaction(payload)
	source = _source(job)
	var text: Variant = result.get("response")
	if source == null or not _is_recent(payload.event) or not text is String \
		or text.strip_edges().is_empty() or text.length() > 160:
		return
	if source.show_spoken_reaction(text):
		store.record_spoken_reaction(payload.npc.id, text)
		_save()

func _source(job: Dictionary) -> BaseNpc:
	var reference: WeakRef = job.source
	return reference.get_ref() as BaseNpc if reference != null else null

func _is_recent(event: Dictionary) -> bool:
	return Time.get_unix_time_from_system() - float(event.created_at) <= REACTION_MAX_AGE

func _save() -> void:
	if persist:
		var error: Error = store.save_file()
		if error != OK:
			push_warning("NPC observation could not be saved: %s" % error)
