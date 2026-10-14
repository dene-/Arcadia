class_name TownEncounters
extends Node

## Owns short social sessions between two residents, each identified by a session id.
## Phases: invite (one social judgment, no claims, bounded by INVITE_MS) -> approach (both
## brains reserve a conversation claim plus an NpcSocialTask in stable id order) -> converse
## (alternating speakers) -> leave (both tasks end, both conversations finish). Dialogue,
## injury, danger or death end the session; results of an ended session are dropped.
const MAX_SESSIONS: int = 3
const RANGE: float = 28.0
const INVITE_MS: int = 8000
const SESSION_MS: int = 45000
const PHASE_INVITE: String = "invite"
const PHASE_APPROACH: String = "approach"
const PHASE_CONVERSE: String = "converse"
var state: TownLifeState
var store: NpcMemoryStore
var backend: DialogBackendClient
var seed_value: int
var save_callback: Callable
## Returns the NpcBrain for a resident id (or null).
var brains: Callable
var tuning: NpcBehaviorTuning
# resident id -> session token; one session per resident, taken at invitation.
var _busy: Dictionary = {}
var _sessions: Dictionary = {}
var _serial: int = 0
var _diagnostics: Dictionary = {}
# Resident ids whose brain signals this node already listens to.
var _listening: Dictionary = {}

func _process(_delta: float) -> void:
	for token: int in _sessions.keys():
		var session: Dictionary = _sessions.get(token, {})
		if not session.is_empty() and not session.valid.call():
			_release(token)

func is_busy(id: String) -> bool:
	return _busy.has(id)

func interrupt(id: String) -> void:
	if _busy.has(id):
		_release(_busy[id])

## The resident's social history as prompts see it, labelled against its live session.
func social_history(id: String) -> Array[Dictionary]:
	var session: Dictionary = _sessions.get(_busy.get(id, 0), {})
	return NpcMemoryStore.history_for_prompt(state.get_person(id).recent_social, state.minute,
		session.get("id", ""), session.get("minute", -1.0))

## The phase of the resident's live session ("" when it has none).
func session_phase(id: String) -> String:
	if not _busy.has(id):
		return ""
	return _sessions[_busy[id]].phase

func _sheltering(id: String) -> bool:
	return NpcSafetyState.sheltering(state.get_person(id).get("safety", {}), state.minute)

func diagnostics(id: String) -> Dictionary:
	return _diagnostics.get(id, {}).duplicate(true)

# Opens an invitation. A resident already in a session (including a crossing invitation from
# the other side) is never invited twice: the earlier, lower session id keeps both.
func consider(first: BaseNpc, second: BaseNpc) -> void:
	var a: String = String(first.get_npc_profile().npc_id)
	var b: String = String(second.get_npc_profile().npc_id)
	if a == b or _busy.size() >= MAX_SESSIONS * 2 or _busy.has(a) or _busy.has(b) \
		or _sheltering(a) or _sheltering(b) \
		or first.daily_routine.activity == "rest" or second.daily_routine.activity == "rest" \
		or not _near(first, second) or state.get_person(a).social_after > state.minute \
		or state.get_person(b).social_after > state.minute:
		return
	var brain_a: NpcBrain = _brain(a)
	var brain_b: NpcBrain = _brain(b)
	if brain_a == null or brain_b == null or not brain_a.accepts_conversation() \
		or not brain_b.accepts_conversation():
		return
	_serial += 1
	var token: int = _serial
	_busy[a] = token
	_busy[b] = token
	_sessions[token] = {"a": a, "b": b, "id": "social:%d" % token, "phase": PHASE_INVITE,
		"minute": state.minute, "brains": {a: brain_a, b: brain_b}, "actors": {a: first, b: second}, "tasks": {}}
	state.reserve_encounter(a, seed_value)
	state.reserve_encounter(b, seed_value)
	_run(first, second, a, b, first.life_revision, second.life_revision, token)

# Both residents reserve in stable id order; a refusal releases whoever was reserved first.
func _approach(token: int) -> bool:
	var session: Dictionary = _sessions[token]
	session.phase = PHASE_APPROACH
	var ids: Array[String] = [session.a, session.b]
	ids.sort()
	for id: String in ids:
		var brain: NpcBrain = session.brains[id]
		var partner: String = session.b if id == session.a else session.a
		var task := NpcSocialTask.create(session.id, partner,
			"initiator" if id == session.a else "partner", tuning)
		if not brain.request_conversation(session.id):
			return false
		if not brain.request_task(task):
			brain.finish_conversation(session.id)
			return false
		session.tasks[id] = task
	var first: BaseNpc = session.actors[session.a]
	var second: BaseNpc = session.actors[session.b]
	first.set_facing_from_direction(second.global_position - first.global_position)
	second.set_facing_from_direction(first.global_position - second.global_position)
	for id: String in ids:
		(session.tasks[id] as NpcSocialTask).converse()
	session.phase = PHASE_CONVERSE
	return true

func _brain(id: String) -> NpcBrain:
	var brain: NpcBrain = brains.call(id) if brains.is_valid() else null
	if brain != null and not _listening.has(id):
		_listening[id] = true
		brain.task_finished.connect(_on_task_finished.bind(id))
		brain.controller.claim_revoked.connect(_on_claim_revoked.bind(id))
	return brain

func _on_task_finished(task_id: String, _status: String, _reason: StringName, id: String) -> void:
	if _busy.has(id) and (_sessions[_busy[id]].tasks as Dictionary).has(id) \
		and task_id == NpcSocialTask.owner_for(_sessions[_busy[id]].id):
		interrupt(id)

func _on_claim_revoked(_claim: StringName, old_owner: String, id: String) -> void:
	if _busy.has(id) and old_owner == NpcSocialTask.owner_for(_sessions[_busy[id]].id):
		interrupt(id)

# True while `token` is still the live session with the given phase rules.
func _live(token: int) -> bool:
	return _sessions.has(token) and _sessions[token].valid.call()

func _run(first: BaseNpc, second: BaseNpc, a: String, b: String, rev_a: int, rev_b: int, token: int) -> void:
	var start: int = Time.get_ticks_msec()
	var session_id: String = _sessions[token].id
	var brain_a: NpcBrain = _sessions[token].brains[a]
	var brain_b: NpcBrain = _sessions[token].brains[b]
	var valid: Callable = func() -> bool:
		if not is_inside_tree() or not is_instance_valid(first) or not is_instance_valid(second) \
			or _busy.get(a) != token or _busy.get(b) != token \
			or first.life_revision != rev_a or second.life_revision != rev_b \
			or _sheltering(a) or _sheltering(b) or not _near(first, second) \
			or Time.get_ticks_msec() - start >= SESSION_MS:
			return false
		if _sessions[token].phase != PHASE_INVITE:
			return true
		return Time.get_ticks_msec() - start < INVITE_MS and is_instance_valid(brain_a) \
			and is_instance_valid(brain_b) and brain_a.accepts_conversation() \
			and brain_b.accepts_conversation()
	_sessions[token].valid = valid
	_status(a, b, "assessing")
	for round_index: int in range(2):
		if not _live(token):
			break
		var speaker: BaseNpc = first if round_index == 0 else second
		var listener: BaseNpc = second if round_index == 0 else first
		var speaker_id: String = a if round_index == 0 else b
		var listener_id: String = b if round_index == 0 else a
		var topics: Array[Dictionary] = state.rumors.candidates(speaker_id, listener_id, state.minute)
		var payload: Dictionary = _payload(speaker, listener)
		payload.topics = topics
		var judgment: Dictionary = await backend.request_life("social", payload)
		if not _live(token):
			break
		var policy: Dictionary = judgment.get("policy", {})
		if not _valid_social(policy, topics.size()):
			_status(a, b, "decision_unavailable")
			break
		if not policy.engage:
			_status(a, b, "declined")
			break
		if _sessions[token].phase == PHASE_INVITE and not _approach(token):
			_status(a, b, "reservation_refused")
			break
		var topic: Dictionary = topics[int(policy.topic_index)] if policy.topic_index >= 0 else {}
		var listener_policy: Dictionary = {}
		if not topic.is_empty():
			var assessment: Dictionary = _payload(listener, speaker)
			assessment.topic = topic
			assessment.speaker = {"id": speaker_id, "name": speaker.get_npc_profile().profile_name}
			var heard: Dictionary = await backend.request_life("listen", assessment)
			listener_policy = heard.get("policy", {})
			if not _live(token) or not _valid_listen(listener_policy):
				_status(a, b, "assessment_cancelled_or_unavailable")
				break
		var audible: bool = _player_near(speaker)
		var line: String = ""
		if audible:
			_status(a, b, "generating_speech")
			line = await _say(speaker, listener, topic, policy, "small_talk" if topic.is_empty() else "share")
			if not _live(token) or line.is_empty() or not _speak(speaker, session_id, line):
				_status(a, b, "speech_cancelled_or_unavailable")
				break
		_status(a, b, "bubble_displayed" if audible else "offscreen_exchange")
		# Information is transferred only here, at delivery. Failed/cancelled speech has no effects.
		if not topic.is_empty():
			var account: Dictionary = state.rumors.hear(listener_id, speaker_id,
				speaker.get_npc_profile().profile_name, topic, listener_policy, state.minute)
			if not account.is_empty():
				store.record_hearsay(listener.get_npc_profile(), account, listener_policy)
		var summary: String = line if not line.is_empty() else ("Exchanged everyday greetings." if topic.is_empty()
			else "Discussed %s's account: %s" % [topic.originator_name, topic.text])
		state.remember_exchange(speaker_id, listener_id, summary, session_id, speaker_id, listener_id)
		state.remember_exchange(listener_id, speaker_id, summary, session_id, speaker_id, listener_id,
			listener_policy.get("affinity", 0.0))
		_refresh_knowledge(listener, listener_id)
		_save()
		if audible:
			await get_tree().create_timer(clampf(line.length() * 0.055, 2.5, 6.0)).timeout
			speaker.end_speech(session_id)
			if not _live(token):
				break
			if not topic.is_empty():
				var reply: String = await _say(listener, speaker, topic, listener_policy, "reply")
				if not _live(token):
					break
				if not reply.is_empty() and _speak(listener, session_id, reply):
					state.remember_exchange(listener_id, speaker_id, reply, session_id, listener_id, speaker_id)
					_save()
					await get_tree().create_timer(clampf(reply.length() * 0.055, 2.5, 6.0)).timeout
					listener.end_speech(session_id)
		# A greeting still gives the other person a turn to respond or bring up their own news.
		if not policy.another_exchange and not topic.is_empty():
			break
	_release(token)

# A session line is protected: no other owner's speech can replace it while it shows.
func _speak(npc: BaseNpc, session_id: String, line: String) -> bool:
	if not npc.begin_speech(session_id, true):
		return false
	if npc.show_spoken_reaction(line, session_id):
		return true
	npc.end_speech(session_id)
	return false

# Leave: ends both social tasks and finishes both conversations. Owner-checked and idempotent;
# a claim or task already taken over by another owner is untouched.
func _release(token: int) -> void:
	if not _sessions.has(token):
		return
	var session: Dictionary = _sessions[token]
	_sessions.erase(token)
	for id: String in [session.a, session.b]:
		if _busy.get(id) == token:
			_busy.erase(id)
	for id: String in [session.a, session.b]:
		var actor: Variant = session.actors[id]
		if is_instance_valid(actor):
			(actor as BaseNpc).end_speech(session.id)
		if session.tasks.has(id):
			(session.tasks[id] as NpcSocialTask).leave()
		var brain: Variant = session.brains[id]
		if is_instance_valid(brain):
			(brain as NpcBrain).end_task(NpcSocialTask.owner_for(session.id), &"session_ended")
			(brain as NpcBrain).finish_conversation(session.id)

func _payload(speaker: BaseNpc, listener: BaseNpc) -> Dictionary:
	var profile: NpcProfile = speaker.get_npc_profile()
	var other: NpcProfile = listener.get_npc_profile()
	var person: Dictionary = state.get_person(String(profile.npc_id))
	store.ensure_npc(profile)
	var memory: Dictionary = store.snapshot(String(profile.npc_id))
	var current: Dictionary = NpcCognitiveContext.build(memory, speaker.get_cognitive_context())
	current.participants = [String(profile.npc_id), String(other.npc_id)]
	current.relationship_with_player = memory.relationship
	current.memories = NpcMemoryRetriever.new().retrieve(memory.memories,
		other.profile_name + " " + str(current.get("activity", "")), current,
		profile.get_cognition(), store.world_minute)
	return {"protocol_version": 1, "npc": {"id": String(profile.npc_id), "profile": profile.to_backend_profile()},
		"listener": {"id": String(other.npc_id), "name": other.profile_name, "job": other.job,
			"activity": listener.daily_routine.activity},
		"current": current, "relationship": person.ties.get(String(other.npc_id), {}),
		"recent_social": social_history(String(profile.npc_id))}

func _status(a: String, b: String, outcome: String) -> void:
	_diagnostics[a] = {"with": b, "outcome": outcome, "minute": state.minute}
	_diagnostics[b] = {"with": a, "outcome": outcome, "minute": state.minute}

func _say(speaker: BaseNpc, listener: BaseNpc, topic: Dictionary, policy: Dictionary, mode: String) -> String:
	var payload: Dictionary = _payload(speaker, listener)
	payload.topic = topic if not topic.is_empty() else null
	payload.policy = policy
	payload.mode = mode
	var result: Dictionary = await backend.request_life("say", payload)
	var response: Variant = result.get("response")
	return response if response is String and response.length() <= 160 else ""

func _near(a: BaseNpc, b: BaseNpc) -> bool:
	return a.can_follow_routine() and b.can_follow_routine() \
		and a.global_position.distance_to(b.global_position) <= RANGE and NpcPerception.can_see(a, b)

func _player_near(speaker: BaseNpc) -> bool:
	for player: Node2D in get_tree().get_nodes_in_group(&"players"):
		if player is BasePlayer and player.world_space == speaker.world_space \
			and speaker.global_position.distance_to(player.global_position) <= 200:
			return true
	return false

func _refresh_knowledge(npc: BaseNpc, id: String) -> void:
	npc.life_context.town_rumors = state.rumors.get_known(id, state.minute).slice(-4)

func _save() -> void:
	if save_callback.is_valid():
		var error: Error = save_callback.call()
		if error != OK:
			push_warning("Social exchange could not be saved: %s" % error)

static func _valid_social(policy: Dictionary, count: int) -> bool:
	return policy.get("engage") is bool and policy.get("another_exchange") is bool \
		and NpcMemory.is_integer(policy.get("topic_index")) and policy.topic_index >= -1 \
		and policy.topic_index < count and policy.get("tone") in ["FRIENDLY", "RESERVED", "CONCERNED", "CURIOUS"]

static func _valid_listen(policy: Dictionary) -> bool:
	if not NpcMemory.is_unit(policy.get("belief")) or not NpcMemory.is_unit(policy.get("importance")) \
		or not policy.get("remember") is bool:
		return false
	for key: String in ["affinity", "trust_player"]:
		if not (policy.get(key) is int or policy.get(key) is float) \
			or not is_finite(float(policy[key])) or absf(policy[key]) > 0.030001:
			return false
	return true
