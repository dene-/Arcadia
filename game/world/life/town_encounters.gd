class_name TownEncounters
extends Node

## Owns short social sessions between two residents, each identified by a session id.
## Phases: invite (one v2 social judgment, no claims, bounded by INVITE_MS) -> approach (both
## brains reserve a conversation claim plus an NpcSocialTask in stable id order) -> converse
## (alternating speakers; a shared account gets a v2 listen judgment, audible lines a v2
## utterance judgment before any /v2/dialogue/say text) -> leave (both tasks end, both conversations
## finish, the session's open request is cancelled). Dialogue, injury, danger or death end the
## session; results of an ended session are dropped.
const MAX_SESSIONS: int = 3
const RANGE: float = 28.0
const INVITE_MS: int = 8000
const SESSION_MS: int = 45000
const PHASE_INVITE: String = "invite"
const PHASE_APPROACH: String = "approach"
const PHASE_CONVERSE: String = "converse"
const TONES: Array[String] = ["friendly", "reserved", "concerned", "curious"]
const DEFAULT_TONE: String = "friendly"
## Utterance intent offered next to the line's mode; choosing it keeps the person quiet.
const SILENCE: String = "silence"
## Rumor confidence ceiling for an account the listener did not believe.
const DOUBTED_BELIEF: float = 0.3
static var _id_pattern: RegEx
var state: TownLifeState
var store: NpcMemoryStore
var decisions: NpcDecisionService
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
	# Cheap position checks first: every resident pair is considered each tick, and a saved
	# person record is copied on every read.
	if a == b or _busy.size() >= MAX_SESSIONS * 2 or _busy.has(a) or _busy.has(b) \
		or first.daily_routine.activity == "rest" or second.daily_routine.activity == "rest" \
		or not _near(first, second) or _sheltering(a) or _sheltering(b) \
		or state.get_person(a).social_after > state.minute \
		or state.get_person(b).social_after > state.minute:
		return
	# Sociable, curious residents open conversations more readily; one deterministic roll per
	# pair and game minute keeps the choice reproducible for a given world seed.
	var traits: Dictionary = first.get_npc_profile().social_traits
	if first.global_position.distance_to(second.global_position) > NpcTemperament.attention_range(traits, RANGE) \
		or NpcRoutinePlan.random_for(seed_value, "%s:initiate:%s:%d" % [a, b, int(state.minute)]).randf() \
			>= NpcTemperament.social_initiative(traits):
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
	# Patient residents stay with a conversation longer, impatient ones drift off sooner.
	var session_ms: float = SESSION_MS * 0.5 * (
		NpcTemperament.persistence(first.get_npc_profile().social_traits)
		+ NpcTemperament.persistence(second.get_npc_profile().social_traits))
	var session_id: String = _sessions[token].id
	var brain_a: NpcBrain = _sessions[token].brains[a]
	var brain_b: NpcBrain = _sessions[token].brains[b]
	var valid: Callable = func() -> bool:
		if not is_inside_tree() or not is_instance_valid(first) or not is_instance_valid(second) \
			or _busy.get(a) != token or _busy.get(b) != token \
			or first.life_revision != rev_a or second.life_revision != rev_b \
			or _sheltering(a) or _sheltering(b) or not _near(first, second) \
			or Time.get_ticks_msec() - start >= session_ms:
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
		var topics: Array[Dictionary] = _shareable(speaker_id, listener_id)
		var topic_ids: Array[String] = []
		var evidence: Array[Dictionary] = []
		for account: Dictionary in topics:
			topic_ids.append(account.origin_id)
			evidence.append(_evidence(account))
		var ticket: NpcDecisionTicket = _ticket(NpcDecisionTicket.SOCIAL, speaker_id, token)
		var judged: NpcDecisionResult = await _decide(token, ticket, {"evidence": evidence,
			"state": _state(speaker, listener), "topics": topic_ids, "tones": TONES})
		if not _live(token):
			break
		if not judged.is_success():
			_status(a, b, "decision_unavailable")
			break
		var social: NpcDecisionPolicy.Social = NpcDecisionPolicy.social(judged, DEFAULT_TONE, tuning)
		if not social.engage:
			_status(a, b, "declined")
			break
		if _sessions[token].phase == PHASE_INVITE and not _approach(token):
			_status(a, b, "reservation_refused")
			break
		var topic: Dictionary = {}
		for account: Dictionary in topics:
			if account.origin_id == social.topic:
				topic = account
		var heard: NpcDecisionPolicy.Listening = null
		if not topic.is_empty():
			var listen: NpcDecisionTicket = _ticket(NpcDecisionTicket.LISTEN, listener_id, token)
			var assessed: NpcDecisionResult = await _decide(token, listen, {
				"evidence": [_evidence(topic)], "state": _state(listener, speaker),
				"subjects": _subjects(topic, speaker_id, listener_id)})
			if not _live(token) or not assessed.is_success():
				_status(a, b, "assessment_cancelled_or_unavailable")
				break
			heard = NpcDecisionPolicy.listening(assessed, speaker_id, tuning)
		var audible: bool = _player_near(speaker)
		var line: String = ""
		var status: String = "offscreen_exchange"
		if audible:
			_status(a, b, "generating_speech")
			var spoken: Dictionary = await _say(token, speaker, listener, topic, social.tone,
				"small_talk" if topic.is_empty() else "share")
			if not _live(token) or not spoken.ok \
					or (not spoken.line.is_empty() and not _speak(speaker, session_id, spoken.line)):
				_status(a, b, "speech_cancelled_or_unavailable")
				break
			line = spoken.line
			status = "bubble_displayed" if not line.is_empty() else "quiet_exchange"
		_status(a, b, status)
		# Information is transferred only here, at delivery. Failed/cancelled speech has no effects.
		if heard != null:
			var listened: Dictionary = {"belief": 1.0 if heard.believe else DOUBTED_BELIEF,
				"remember": heard.remember, "importance": heard.importance,
				"dispositions": heard.dispositions}
			var account: Dictionary = state.rumors.hear(listener_id, speaker_id,
				speaker.get_npc_profile().profile_name, topic, listened, state.minute)
			if not account.is_empty():
				store.record_hearsay(listener.get_npc_profile(), account, listened)
		var summary: String = line if not line.is_empty() else ("Exchanged everyday greetings." if topic.is_empty()
			else "Discussed %s's account: %s" % [topic.originator_name, topic.text])
		state.remember_exchange(speaker_id, listener_id, summary, session_id, speaker_id, listener_id)
		state.remember_exchange(listener_id, speaker_id, summary, session_id, speaker_id, listener_id)
		# The exchange reached both residents, so each one's need for company eases once.
		for id: String in [a, b]:
			var task: NpcSocialTask = _sessions[token].tasks.get(id) as NpcSocialTask
			if task != null:
				task.deliver_exchange()
		_refresh_knowledge(listener, listener_id)
		_save()
		if not line.is_empty():
			await get_tree().create_timer(clampf(line.length() * 0.055, 2.5, 6.0)).timeout
			speaker.end_speech(session_id)
			if not _live(token):
				break
			if not topic.is_empty():
				var reply: Dictionary = await _say(token, listener, speaker, topic, social.tone, "reply")
				if not _live(token):
					break
				if not reply.line.is_empty() and _speak(listener, session_id, reply.line):
					state.remember_exchange(listener_id, speaker_id, reply.line, session_id, listener_id, speaker_id)
					_save()
					await get_tree().create_timer(clampf(reply.line.length() * 0.055, 2.5, 6.0)).timeout
					listener.end_speech(session_id)
		# A greeting still gives the other person a turn to respond or bring up their own news.
		if not topic.is_empty():
			break
	_release(token)

# Known accounts the speaker may pass on, keyed by origin id (which must be a protocol id).
func _shareable(speaker_id: String, listener_id: String) -> Array[Dictionary]:
	var shareable: Array[Dictionary] = []
	for account: Dictionary in state.rumors.candidates(speaker_id, listener_id, state.minute):
		if _is_id(account.origin_id):
			shareable.append(account)
	return shareable

# The messenger, then whom the account is about: the player and its (absent) originator.
static func _subjects(account: Dictionary, speaker_id: String, listener_id: String) -> Array[String]:
	var subjects: Array[String] = [speaker_id]
	if account.player_involved:
		subjects.append("player")
	var originator: String = account.originator
	if _is_id(originator) and not originator in [speaker_id, listener_id, "player"]:
		subjects.append(originator)
	return subjects

static func _evidence(account: Dictionary) -> Dictionary:
	return {"id": account.origin_id, "modality": "spoken_report",
		"text": ("%s reported: %s" % [account.originator_name, account.text]).substr(0, 1000),
		"source_id": String(account.source_id).substr(0, 100), "participant_ids": []}

static func _is_id(value: String) -> bool:
	if _id_pattern == null:
		_id_pattern = RegEx.create_from_string("^[A-Za-z0-9_:-]{1,100}$")
	return _id_pattern.search(value) != null

# A ticket bound to the live session: its id is the task, its token the generation.
func _ticket(kind: StringName, npc_id: String, token: int) -> NpcDecisionTicket:
	var session: Dictionary = _sessions[token]
	var ticket := NpcDecisionTicket.create(npc_id, kind)
	ticket.task_id = session.id
	ticket.task_generation = token
	ticket.created_minute = int(state.minute)
	for id: String in [session.a, session.b]:
		ticket.read_versions["life:" + id] = (session.actors[id] as BaseNpc).life_revision
	return ticket

# Runs one request as the session's current one, so leaving the session cancels it.
func _decide(token: int, ticket: NpcDecisionTicket, payload: Dictionary,
		text_path: String = "") -> NpcDecisionResult:
	_sessions[token].request = ticket.request_id
	var result: NpcDecisionResult
	if text_path.is_empty():
		result = await decisions.evaluate(ticket, payload)
	else:
		result = await decisions.run_text(ticket, text_path, payload)
	if _sessions.has(token) and _sessions[token].get("request") == ticket.request_id:
		_sessions[token].erase("request")
	return result

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
	if session.has("request"):
		decisions.cancel(session.request)

# The v2 `state` judgments see: the speaker, the listener, the speaker's social context with
# relevant memories, their relationship and recent social history.
func _state(speaker: BaseNpc, listener: BaseNpc) -> Dictionary:
	var profile: NpcProfile = speaker.get_npc_profile()
	var other: NpcProfile = listener.get_npc_profile()
	var other_id: String = String(other.npc_id)
	store.ensure_npc(profile)
	var memory: Dictionary = store.snapshot(String(profile.npc_id))
	var raw: Dictionary = speaker.get_cognitive_context(NpcCognitiveContext.SOCIAL, [other_id])
	var current: Dictionary = NpcCognitiveContext.build(memory, raw)
	current.participants = [String(profile.npc_id), other_id]
	current.memories = NpcMemoryRetriever.new().retrieve(memory.memories,
		other.profile_name + " " + str(current.get("activity", "")), current,
		profile.get_cognition(), store.world_minute, NpcMemoryRetriever.links_for(raw))
	return {"npc": {"id": String(profile.npc_id), "profile": profile.to_backend_profile()},
		"listener": {"id": String(other.npc_id), "name": other.profile_name, "job": other.job,
			"activity": listener.daily_routine.activity},
		"current": current, "relationship": raw.relationships.get(other_id, {}),
		"recent_social": social_history(String(profile.npc_id))}

# The `/v2/dialogue/say` request for one line in `intent` addressed to `listener`, about the
# attributed `topic` account when there is one.
func _say_payload(ticket: NpcDecisionTicket, speaker: BaseNpc, listener: BaseNpc,
		topic: Dictionary, tone: String, intent: String) -> Dictionary:
	var speaker_id: String = ticket.npc_id
	var heard: NpcProfile = listener.get_npc_profile()
	var context: Dictionary = speaker.get_cognitive_context(NpcCognitiveContext.SOCIAL,
		[String(heard.npc_id)])
	context.recent_social = social_history(speaker_id)
	context.tone = tone
	var payload: Dictionary = {"protocol_version": ticket.protocol_version,
		"prompt_version": ticket.prompt_version, "request_id": ticket.request_id,
		"npc_id": speaker_id,
		"npc": {"id": speaker_id, "profile": speaker.get_npc_profile().to_backend_profile()},
		"intent": intent, "listener": {"id": String(heard.npc_id), "name": heard.profile_name},
		"context": context}
	if not topic.is_empty():
		payload.topic = {"originator_name": String(topic.originator_name).substr(0, 100),
			"source_name": String(topic.source_name).substr(0, 100),
			"text": String(topic.text).substr(0, NpcReportSpeech.MAX_EVENT_TEXT),
			"sense": topic.sense, "basis": topic.get("basis", ""), "hops": topic.get("hops", 0),
			"confidence": topic.confidence}
	return payload

func _status(a: String, b: String, outcome: String) -> void:
	_diagnostics[a] = {"with": b, "outcome": outcome, "minute": state.minute}
	_diagnostics[b] = {"with": a, "outcome": outcome, "minute": state.minute}

# One line in `mode` (share | small_talk | reply): a v2 utterance judgment, then text only when it
# speaks with that intent. {ok: false} when the judgment or text was unavailable or the session
# ended; {ok: true, line: ""} when the person chose to stay quiet.
func _say(token: int, speaker: BaseNpc, listener: BaseNpc, topic: Dictionary, tone: String,
		mode: String) -> Dictionary:
	var speaker_id: String = String(speaker.get_npc_profile().npc_id)
	var described: Dictionary = _state(speaker, listener)
	described.merge({"mode": mode, "tone": tone, "topic_id": topic.get("origin_id", "")})
	var ticket: NpcDecisionTicket = _ticket(NpcDecisionTicket.UTTERANCE, speaker_id, token)
	var judged: NpcDecisionResult = await _decide(token, ticket, {"state": described,
		"evidence": [_evidence(topic)] if not topic.is_empty() else [], "intents": [mode, SILENCE]})
	if not _live(token) or not judged.is_success():
		return {"ok": false, "line": ""}
	var decided: NpcDecisionPolicy.Utterance = NpcDecisionPolicy.utterance(judged, [mode], tuning)
	if not decided.speak:
		return {"ok": true, "line": ""}
	var line_ticket: NpcDecisionTicket = _ticket(NpcDecisionTicket.UTTERANCE, speaker_id, token)
	var text: NpcDecisionResult = await _decide(token, line_ticket,
		_say_payload(line_ticket, speaker, listener, topic, tone, decided.intent), NpcReportSpeech.PATH)
	if not _live(token):
		return {"ok": false, "line": ""}
	var line: String = NpcReportSpeech.spoken_line(text)
	return {"ok": not line.is_empty(), "line": line}

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
