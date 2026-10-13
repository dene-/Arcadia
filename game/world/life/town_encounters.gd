class_name TownEncounters
extends Node

## Owns short social sessions; dialogue, injury or death invalidate every pending inference.
## A session reserves both participants through their NpcBrain: a conversation claim plus a
## hold task owned by "session:<id>". A cancelled hold or a revoked claim ends the session.
const MAX_SESSIONS: int = 3
const RANGE: float = 28.0
const HOLD_REASON: String = "conversation"
var state: TownLifeState
var store: NpcMemoryStore
var backend: DialogBackendClient
var seed_value: int
var save_callback: Callable
## Returns the NpcBrain for a resident id (or null).
var brains: Callable
var tuning: NpcBehaviorTuning
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
			_release(session.a, session.b, token)

func is_busy(id: String) -> bool:
	return _busy.has(id)

func interrupt(id: String) -> void:
	if not _busy.has(id):
		return
	var token: int = _busy[id]
	var session: Dictionary = _sessions[token]
	_release(session.a, session.b, token)

func _sheltering(id: String) -> bool:
	return NpcSafetyState.sheltering(state.get_person(id).get("safety", {}), state.minute)

func diagnostics(id: String) -> Dictionary:
	return _diagnostics.get(id, {}).duplicate(true)

func consider(first: BaseNpc, second: BaseNpc) -> void:
	var a: String = String(first.get_npc_profile().npc_id)
	var b: String = String(second.get_npc_profile().npc_id)
	if _busy.size() >= MAX_SESSIONS * 2 or _busy.has(a) or _busy.has(b) \
		or _sheltering(a) or _sheltering(b) \
		or first.daily_routine.activity == "rest" or second.daily_routine.activity == "rest" \
		or not _near(first, second) or state.get_person(a).social_after > state.minute \
		or state.get_person(b).social_after > state.minute:
		return
	var brain_a: NpcBrain = _brain(a)
	var brain_b: NpcBrain = _brain(b)
	if brain_a == null or brain_b == null:
		return
	var session_id: String = str(_serial + 1)
	var holds: Dictionary = {}
	# Reserve in stable ID order; a refusal releases whoever was already reserved.
	for id: String in ([a, b] if a < b else [b, a]):
		var brain: NpcBrain = brain_a if id == a else brain_b
		var hold_id: String = _reserve(brain, session_id)
		if hold_id.is_empty():
			for reserved: String in holds:
				_unreserve(brain_a if reserved == a else brain_b, session_id, holds[reserved])
			return
		holds[id] = hold_id
	_serial += 1
	_busy[a] = _serial
	_busy[b] = _serial
	_sessions[_serial] = {"a": a, "b": b, "id": session_id, "holds": holds,
		"brains": {a: brain_a, b: brain_b}}
	state.reserve_encounter(a, seed_value)
	state.reserve_encounter(b, seed_value)
	first.set_facing_from_direction(second.global_position - first.global_position)
	second.set_facing_from_direction(first.global_position - second.global_position)
	_run(first, second, a, b, first.life_revision, second.life_revision, _serial)

# Returns the hold task id, or "" when the brain refused the conversation or the hold.
func _reserve(brain: NpcBrain, session_id: String) -> String:
	if not brain.request_conversation(session_id):
		return ""
	var hold := NpcHoldTask.create({"owner": "session:" + session_id, "reason": HOLD_REASON,
		"priority": tuning.hold_priority})
	if not brain.request_task(hold):
		brain.finish_conversation(session_id)
		return ""
	return hold.task_id

# Owner-checked and idempotent: a hold or claim already taken over by another task is untouched.
func _unreserve(brain: Variant, session_id: String, hold_id: String) -> void:
	if not is_instance_valid(brain):
		return
	(brain as NpcBrain).end_task(hold_id, &"session_ended")
	(brain as NpcBrain).finish_conversation(session_id)

func _brain(id: String) -> NpcBrain:
	var brain: NpcBrain = brains.call(id) if brains.is_valid() else null
	if brain != null and not _listening.has(id):
		_listening[id] = true
		brain.task_finished.connect(_on_task_finished.bind(id))
		brain.controller.claim_revoked.connect(_on_claim_revoked.bind(id))
	return brain

func _on_task_finished(task_id: String, _status: String, _reason: StringName, id: String) -> void:
	if _busy.has(id) and _sessions[_busy[id]].holds.get(id) == task_id:
		interrupt(id)

func _on_claim_revoked(_claim: StringName, old_owner: String, id: String) -> void:
	if _busy.has(id) and old_owner == "session:" + String(_sessions[_busy[id]].id):
		interrupt(id)

func _run(first: BaseNpc, second: BaseNpc, a: String, b: String, rev_a: int, rev_b: int, token: int) -> void:
	var start: int = Time.get_ticks_msec()
	var valid: Callable = func() -> bool:
		return is_inside_tree() and is_instance_valid(first) and is_instance_valid(second) \
			and _busy.get(a) == token and _busy.get(b) == token \
			and first.life_revision == rev_a and second.life_revision == rev_b \
			and not _sheltering(a) and not _sheltering(b) \
			and Time.get_ticks_msec() - start < 45000 and _near(first, second)
	_sessions[token].valid = valid
	_status(a, b, "assessing")
	for round_index: int in range(2):
		if not valid.call():
			break
		var speaker: BaseNpc = first if round_index == 0 else second
		var listener: BaseNpc = second if round_index == 0 else first
		var speaker_id: String = a if round_index == 0 else b
		var listener_id: String = b if round_index == 0 else a
		var topics: Array[Dictionary] = state.rumors.candidates(speaker_id, listener_id, state.minute)
		var payload: Dictionary = _payload(speaker, listener)
		payload.topics = topics
		var judgment: Dictionary = await backend.request_life("social", payload)
		if not valid.call():
			break
		var policy: Dictionary = judgment.get("policy", {})
		if not _valid_social(policy, topics.size()):
			_status(a, b, "decision_unavailable")
			break
		if not policy.engage:
			_status(a, b, "declined")
			break
		var topic: Dictionary = topics[int(policy.topic_index)] if policy.topic_index >= 0 else {}
		var listener_policy: Dictionary = {}
		if not topic.is_empty():
			var assessment: Dictionary = _payload(listener, speaker)
			assessment.topic = topic
			assessment.speaker = {"id": speaker_id, "name": speaker.get_npc_profile().profile_name}
			var heard: Dictionary = await backend.request_life("listen", assessment)
			listener_policy = heard.get("policy", {})
			if not valid.call() or not _valid_listen(listener_policy):
				_status(a, b, "assessment_cancelled_or_unavailable")
				break
		var audible: bool = _player_near(speaker)
		var line: String = ""
		if audible:
			_status(a, b, "generating_speech")
			line = await _say(speaker, listener, topic, policy, "small_talk" if topic.is_empty() else "share")
			if not valid.call() or line.is_empty() or not speaker.show_spoken_reaction(line):
				_status(a, b, "speech_cancelled_or_unavailable")
				break
		_status(a, b, "bubble_displayed" if audible else "offscreen_exchange")
		# Information is transferred only once, at the actual exchange. Failed/cancelled speech has no effects.
		if not topic.is_empty():
			var account: Dictionary = state.rumors.hear(listener_id, speaker_id,
				speaker.get_npc_profile().profile_name, topic, listener_policy, state.minute)
			if not account.is_empty():
				store.record_hearsay(listener.get_npc_profile(), account, listener_policy)
		var summary: String = line if not line.is_empty() else ("Exchanged everyday greetings." if topic.is_empty()
			else "Discussed %s's account: %s" % [topic.originator_name, topic.text])
		state.remember_exchange(speaker_id, listener_id, summary)
		state.remember_exchange(listener_id, speaker_id, summary, listener_policy.get("affinity", 0.0))
		_refresh_knowledge(listener, listener_id)
		_save()
		if audible:
			await get_tree().create_timer(clampf(line.length() * 0.055, 2.5, 6.0)).timeout
			if not valid.call():
				break
			if not topic.is_empty():
				var reply: String = await _say(listener, speaker, topic, listener_policy, "reply")
				if not valid.call():
					break
				if not reply.is_empty() and listener.show_spoken_reaction(reply):
					state.remember_exchange(listener_id, speaker_id, reply)
					_save()
					await get_tree().create_timer(clampf(reply.length() * 0.055, 2.5, 6.0)).timeout
		# A greeting still gives the other person a turn to respond or bring up their own news.
		if not policy.another_exchange and not topic.is_empty():
			break
	_release(a, b, token)

# Cleanup ends both holds and finishes both conversations; safe to call more than once.
func _release(a: String, b: String, token: int) -> void:
	if not _sessions.has(token):
		return
	var session: Dictionary = _sessions[token]
	for id: String in [a, b]:
		if _busy.get(id) != token:
			continue
		_busy.erase(id)
		_unreserve(session.brains[id], session.id, session.holds[id])
	_sessions.erase(token)

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
		"recent_social": person.recent_social}

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
