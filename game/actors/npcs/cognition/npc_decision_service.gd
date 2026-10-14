class_name NpcDecisionService
extends Node

## The one game-side scheduler for provider work. Owner: the NpcCognition autoload keeps one as a
## child next to its DialogBackendClient and sets that client as `transport`.
## `evaluate` sends a v2 cognition request and validates the typed answer against the request;
## `chat` sends one player-dialogue request and validates its typed player-speech judgments;
## `run_text` sends a text-route request through the text pool. Every ticket settles exactly once
## (transport answer, deadline, cancel, cancel_owner, coalescing or service exit); its permit is
## released and its caller woken at that moment, and a late transport answer is ignored.
## The service reports outcomes only: owners check the ticket and apply effects themselves.

enum Pool { JUDGMENT, TEXT }

## Every settled ticket, for decision traces: {npc_id, request_id, request_kind, read_versions,
## latency_ms (queued to settled), outcome (lower-case NpcDecisionResult.Outcome name)}.
signal request_settled(entry: Dictionary)

## Concurrent requests per pool, mirroring the server's provider limits.
const LIMITS: Array[int] = [4, 2]
## Permits per pool that background work may not take, so interactive and safety work starts promptly.
const INTERACTIVE_RESERVE: int = 1
## Each wait of this length promotes a queued job one urgency class, so background work cannot starve.
const AGING_MSEC: int = 5000
const ROUTES: Dictionary[StringName, String] = {
	NpcDecisionTicket.APPRAISE: "/v2/cognition/appraise",
	NpcDecisionTicket.SELECT_GOAL: "/v2/cognition/select-goal",
	NpcDecisionTicket.SOCIAL: "/v2/cognition/social",
	NpcDecisionTicket.LISTEN: "/v2/cognition/listen",
	NpcDecisionTicket.UTTERANCE: "/v2/cognition/utterance",
}
const CHAT_ROUTE: String = "/v2/dialogue/chat"
const DIMENSIONS: Array[String] = ["trust", "affection", "respect", "fear", "suspicion"]
const DIRECTIONS: Array[String] = ["NEGATIVE", "UNCHANGED", "POSITIVE"]
const DURATIONS: Array[String] = ["BRIEF", "ORDINARY", "EXTENDED"]
const SMALL_TALK: String = "SMALL_TALK"
const EMOTIONS: Array[String] = ["fear", "anger", "grief", "relief"]
## Answers of the player's message (server CHAT_QUESTIONS): gates, retention scores, the
## message's intent, the reply's style and one direction per disposition toward the player.
const INTENTS: Array[String] = ["GREETING", "FAREWELL", "QUESTION", "REQUEST", "THREAT",
	"KINDNESS", "INSULT", "PROMISE", "CLAIM", "APOLOGY", "SURRENDER", "OTHER"]
const RESPONSE_MODES: Array[String] = ["NEUTRAL", "WARM", "GUARDED", "DEFENSIVE", "REFUSE",
	"UNCERTAIN"]

# Envelope limits of tools/server/src/cognition-contract.js.
const _MAX_STATE_BYTES: int = 16384
const _MAX_EVIDENCE: int = 8
const _MAX_EVIDENCE_IDS: int = 32
const _MAX_SUBJECTS: int = 3
const _MAX_CANDIDATES: int = 8
const _MAX_TOPICS: int = 6
const _MAX_TONES: int = 8
const _MAX_INTENTS: int = 12
const _MAX_READ_VERSIONS: int = 16
const _MAX_PARTICIPANTS: int = 8
const _SCORE_LEVELS: Array[String] = ["0", "1", "2", "3", "4"]
const _PROBABILITY_TOLERANCE: float = 0.02

class _Job extends RefCounted:
	signal settled
	var ticket: NpcDecisionTicket
	var pool: int
	var path: String
	var request: Dictionary
	## question id -> {"type": "noul"|"score"} or {"type": "choice", "options": Array[String]}.
	var questions: Dictionary
	var transport_ms: int
	var queued_msec: int
	var sequence: int
	var active: bool = false
	var awaiting_transport: bool = false
	var expires_msec: int = 0
	var result: NpcDecisionResult

static var _id_pattern: RegEx

var transport: DialogBackendClient
## Monotonic milliseconds; replaceable so tests control aging and deadlines.
var clock: Callable = Callable(Time, "get_ticks_msec")

var _jobs: Dictionary[String, _Job] = {}
var _queued: Array[_Job] = []
var _active_counts: Array[int] = [0, 0]
## npc id -> stamp of its latest dispatch; the least recently served NPC goes first.
var _served: Dictionary[String, int] = {}
var _serve_stamp: int = 0
var _sequence: int = 0
var _pumping: bool = false

func _ready() -> void:
	set_process(not _jobs.is_empty())

func _process(_delta: float) -> void:
	_pump()

func _exit_tree() -> void:
	# Holding the pump keeps queued work from dispatching while everything settles.
	_pumping = true
	for job: _Job in _jobs.values():
		_settle(job, NpcDecisionResult.Outcome.CANCELLED)
	_pumping = false
	set_process(false)

## Sends one v2 cognition request built from `ticket` and `payload` ({state, evidence, and per
## kind: subjects | candidates | topics + tones | intents}) and returns its settled result.
## A malformed request is INVALID without contacting the provider. A newer select_goal for the same
## NPC settles its queued older select_goal as STALE.
func evaluate(ticket: NpcDecisionTicket, payload: Dictionary) -> NpcDecisionResult:
	var request: Dictionary = _envelope(ticket, payload) if ticket != null \
		and ROUTES.has(ticket.kind) else {}
	if request.is_empty() or _jobs.has(ticket.request_id):
		return NpcDecisionResult.new(NpcDecisionResult.Outcome.INVALID, ticket)
	if transport == null:
		return NpcDecisionResult.new(NpcDecisionResult.Outcome.UNAVAILABLE, ticket)
	if ticket.kind == NpcDecisionTicket.SELECT_GOAL:
		for job: _Job in _queued.duplicate():
			if job.ticket.npc_id == ticket.npc_id and job.ticket.kind == NpcDecisionTicket.SELECT_GOAL:
				_settle(job, NpcDecisionResult.Outcome.STALE)
	var job := _Job.new()
	job.ticket = ticket
	job.pool = Pool.JUDGMENT
	job.path = ROUTES[ticket.kind]
	job.request = request
	job.questions = _questions(request)
	job.transport_ms = DialogBackendClient.JUDGMENT_DEADLINE_MS
	return await _schedule(job)

## Sends one player-dialogue request for a DIALOGUE `ticket` through the text pool: `payload`
## ({npc, context, player, recent_dialogue, memories}) under the ticket's envelope header. On
## SUCCESS `judgments` holds the validated player-speech answers and `body` the whole response
## (response, memory_writes, recalled_memory_ids), which the caller still validates.
func chat(ticket: NpcDecisionTicket, payload: Dictionary) -> NpcDecisionResult:
	if not _is_valid_ticket(ticket) or ticket.kind != NpcDecisionTicket.DIALOGUE \
			or not _is_valid_ticket_fields(ticket) or _jobs.has(ticket.request_id):
		return NpcDecisionResult.new(NpcDecisionResult.Outcome.INVALID, ticket)
	if transport == null:
		return NpcDecisionResult.new(NpcDecisionResult.Outcome.UNAVAILABLE, ticket)
	var job := _Job.new()
	job.ticket = ticket
	job.pool = Pool.TEXT
	job.path = CHAT_ROUTE
	job.request = payload.duplicate(true)
	job.request.merge({"protocol_version": ticket.protocol_version,
		"prompt_version": ticket.prompt_version, "request_id": ticket.request_id,
		"npc_id": ticket.npc_id}, true)
	job.questions = chat_questions()
	job.transport_ms = DialogBackendClient.DIALOGUE_DEADLINE_MS
	return await _schedule(job)

## Sends `payload` unchanged to a text route through the text pool. On SUCCESS the parsed response
## is in `body`; validating its text is the caller's job.
func run_text(ticket: NpcDecisionTicket, path: String, payload: Dictionary,
		deadline_ms: int = DialogBackendClient.AMBIENT_DEADLINE_MS) -> NpcDecisionResult:
	if not _is_valid_ticket(ticket) or path.is_empty() or deadline_ms <= 0 \
			or _jobs.has(ticket.request_id):
		return NpcDecisionResult.new(NpcDecisionResult.Outcome.INVALID, ticket)
	if transport == null:
		return NpcDecisionResult.new(NpcDecisionResult.Outcome.UNAVAILABLE, ticket)
	var job := _Job.new()
	job.ticket = ticket
	job.pool = Pool.TEXT
	job.path = path
	job.request = payload.duplicate(true)
	job.transport_ms = deadline_ms
	return await _schedule(job)

## Settles a queued or running request as CANCELLED and aborts its transport.
func cancel(request_id: String) -> void:
	var job: _Job = _jobs.get(request_id)
	if job != null:
		_settle(job, NpcDecisionResult.Outcome.CANCELLED)

## Cancels every queued or running request of one NPC.
func cancel_owner(npc_id: String) -> void:
	for job: _Job in _jobs.values():
		if job.ticket.npc_id == npc_id:
			_settle(job, NpcDecisionResult.Outcome.CANCELLED)

func active_count(pool: Pool) -> int:
	return _active_counts[pool]

func queued_count(pool: Pool) -> int:
	return _queued.filter(func(job: _Job) -> bool: return job.pool == pool).size()

func _schedule(job: _Job) -> NpcDecisionResult:
	_sequence += 1
	job.sequence = _sequence
	job.queued_msec = _now()
	_jobs[job.ticket.request_id] = job
	_queued.append(job)
	_pump()
	if job.result == null:
		await job.settled
	return job.result

func _pump() -> void:
	if _pumping:
		return
	_pumping = true
	var now: int = _now()
	for job: _Job in _jobs.values():
		var deadline: int = job.ticket.deadline_tick_msec
		if (deadline > 0 and now >= deadline) or (job.active and now >= job.expires_msec):
			_settle(job, NpcDecisionResult.Outcome.TIMEOUT)
	for pool: int in [Pool.JUDGMENT, Pool.TEXT]:
		var next: _Job = _next(pool, now)
		while next != null:
			_dispatch(next, now)
			now = _now()
			next = _next(pool, now)
	_pumping = false
	set_process(not _jobs.is_empty())

# Lowest aged urgency class first, then the least recently served NPC, then the oldest request.
func _next(pool: int, now: int) -> _Job:
	if _active_counts[pool] >= LIMITS[pool]:
		return null
	var reserved: bool = _active_counts[pool] >= LIMITS[pool] - INTERACTIVE_RESERVE
	var best: _Job = null
	var best_class: int = 0
	for job: _Job in _queued:
		if job.pool != pool:
			continue
		var urgency: int = maxi(0, int(job.ticket.urgency) - (now - job.queued_msec) / AGING_MSEC)
		if reserved and urgency == NpcDecisionTicket.Urgency.BACKGROUND:
			continue
		if best == null or urgency < best_class or (urgency == best_class \
				and _precedes(job, best)):
			best = job
			best_class = urgency
	return best

func _precedes(job: _Job, other: _Job) -> bool:
	var served: int = _served.get(job.ticket.npc_id, 0)
	var other_served: int = _served.get(other.ticket.npc_id, 0)
	return served < other_served or (served == other_served and job.sequence < other.sequence)

func _dispatch(job: _Job, now: int) -> void:
	_queued.erase(job)
	job.active = true
	_active_counts[job.pool] += 1
	_serve_stamp += 1
	_served[job.ticket.npc_id] = _serve_stamp
	var transport_ms: int = job.transport_ms
	if job.ticket.deadline_tick_msec > 0:
		transport_ms = mini(transport_ms, job.ticket.deadline_tick_msec - now)
	job.expires_msec = now + transport_ms
	_run(job, transport_ms)

func _run(job: _Job, transport_ms: int) -> void:
	var client: DialogBackendClient = transport
	job.awaiting_transport = true
	var response: Dictionary = await client.request_v2(job.path, job.request, transport_ms,
		job.ticket.request_id)
	job.awaiting_transport = false
	if job.result != null:
		return
	var body: Variant = response.get("body", {})
	match response.get("outcome", &""):
		DialogBackendClient.OUTCOME_SUCCESS:
			if not body is Dictionary:
				_settle(job, NpcDecisionResult.Outcome.INVALID)
			elif job.questions.is_empty():
				_settle(job, NpcDecisionResult.Outcome.SUCCESS, {}, (body as Dictionary).duplicate(true))
			else:
				var judgments: Dictionary = _judgments(job, body)
				# Dialogue keeps its whole response next to the judgments; cognition has no prose.
				var kept: Dictionary = (body as Dictionary).duplicate(true) \
					if job.ticket.kind == NpcDecisionTicket.DIALOGUE else {}
				_settle(job, NpcDecisionResult.Outcome.SUCCESS if not judgments.is_empty()
					else NpcDecisionResult.Outcome.INVALID, judgments, kept)
		DialogBackendClient.OUTCOME_TIMEOUT:
			_settle(job, NpcDecisionResult.Outcome.TIMEOUT)
		DialogBackendClient.OUTCOME_UNAVAILABLE:
			_settle(job, NpcDecisionResult.Outcome.UNAVAILABLE)
		DialogBackendClient.OUTCOME_CANCELLED:
			_settle(job, NpcDecisionResult.Outcome.CANCELLED)
		_:
			_settle(job, NpcDecisionResult.Outcome.INVALID)

func _settle(job: _Job, outcome: NpcDecisionResult.Outcome, judgments: Dictionary = {},
		body: Dictionary = {}) -> void:
	if job.result != null:
		return
	job.result = NpcDecisionResult.new(outcome, job.ticket, judgments, body)
	_jobs.erase(job.ticket.request_id)
	if job.active:
		job.active = false
		_active_counts[job.pool] -= 1
	else:
		_queued.erase(job)
	if job.awaiting_transport and is_instance_valid(transport):
		transport.cancel(job.ticket.request_id)
	request_settled.emit({"npc_id": job.ticket.npc_id, "request_id": job.ticket.request_id,
		"request_kind": String(job.ticket.kind), "read_versions": job.ticket.read_versions.duplicate(),
		"latency_ms": maxi(_now() - job.queued_msec, 0),
		"outcome": String(NpcDecisionResult.Outcome.keys()[outcome]).to_lower()})
	job.settled.emit()
	_pump()

func _now() -> int:
	return int(clock.call())

# --- Request envelope (mirrors validateEnvelope in tools/server/src/cognition-contract.js) ---

func _is_valid_ticket(ticket: NpcDecisionTicket) -> bool:
	return ticket != null and _is_id(ticket.request_id) and _is_id(ticket.npc_id) \
		and ticket.kind in NpcDecisionTicket.KINDS

# The v2 request body, or {} when the ticket or payload breaks the contract.
func _envelope(ticket: NpcDecisionTicket, payload: Dictionary) -> Dictionary:
	if not _is_valid_ticket(ticket) or not _is_valid_ticket_fields(ticket):
		return {}
	var state: Variant = payload.get("state")
	if not state is Dictionary or JSON.stringify(state).to_utf8_buffer().size() > _MAX_STATE_BYTES:
		return {}
	var evidence: Variant = _evidence(payload.get("evidence", []))
	if evidence == null:
		return {}
	var request: Dictionary = {"protocol_version": ticket.protocol_version,
		"prompt_version": ticket.prompt_version, "request_id": ticket.request_id,
		"npc_id": ticket.npc_id, "kind": String(ticket.kind), "ticket": ticket.envelope_ticket(),
		"state": (state as Dictionary).duplicate(true), "evidence": evidence}
	match ticket.kind:
		NpcDecisionTicket.APPRAISE, NpcDecisionTicket.LISTEN:
			var subjects: Variant = _id_list(payload.get("subjects"), _MAX_SUBJECTS)
			if subjects == null:
				return {}
			request["subjects"] = subjects
		NpcDecisionTicket.SELECT_GOAL:
			# The ticket names exactly the candidates the request offers, in order.
			var candidates: Variant = _candidates(payload.get("candidates"))
			if candidates == null or (candidates as Array).size() != ticket.candidate_ids.size():
				return {}
			for index: int in ticket.candidate_ids.size():
				if candidates[index].id != ticket.candidate_ids[index]:
					return {}
			request["candidates"] = candidates
		NpcDecisionTicket.SOCIAL:
			var topics: Variant = _id_list(payload.get("topics"), _MAX_TOPICS)
			var tones: Variant = _id_list(payload.get("tones"), _MAX_TONES, 1)
			if topics == null or tones == null or SMALL_TALK in (topics as Array):
				return {}
			request["topics"] = topics
			request["tones"] = tones
		NpcDecisionTicket.UTTERANCE:
			var intents: Variant = _id_list(payload.get("intents"), _MAX_INTENTS, 1)
			if intents == null:
				return {}
			request["intents"] = intents
	return request

func _is_valid_ticket_fields(ticket: NpcDecisionTicket) -> bool:
	if ticket.protocol_version != NpcDecisionTicket.PROTOCOL_VERSION \
			or ticket.prompt_version != NpcDecisionTicket.PROMPT_VERSION \
			or ticket.task_id.length() > 100 or ticket.task_generation < 0 \
			or ticket.created_minute < 0 or ticket.context_hash.length() > 128 \
			or ticket.read_versions.size() > _MAX_READ_VERSIONS \
			or _id_list(ticket.evidence_ids, _MAX_EVIDENCE_IDS) == null \
			or _id_list(ticket.candidate_ids, _MAX_CANDIDATES) == null:
		return false
	for key: Variant in ticket.read_versions:
		var value: Variant = ticket.read_versions[key]
		if not key is String:
			return false
		if value is String:
			if (value as String).length() > 100:
				return false
		elif not _is_number(value) or float(value) < 0.0 or float(value) != floorf(float(value)):
			return false
	return true

func _evidence(value: Variant) -> Variant:
	if not value is Array or (value as Array).size() > _MAX_EVIDENCE:
		return null
	var items: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw: Variant in value:
		if not raw is Dictionary:
			return null
		var item: Dictionary = raw
		var text: Variant = item.get("text")
		var modality: Variant = item.get("modality")
		var source: Variant = item.get("source_id")
		var participants: Variant = _id_list(item.get("participant_ids"), _MAX_PARTICIPANTS)
		if not _is_id(item.get("id")) or seen.has(item.id) or participants == null \
				or not text is String or (text as String).strip_edges().is_empty() \
				or (text as String).length() > 1000 or not modality is String \
				or (modality as String).strip_edges().is_empty() or (modality as String).length() > 40 \
				or not source is String or (source as String).length() > 100:
			return null
		seen[item.id] = true
		items.append({"id": item.id, "text": text, "modality": modality, "source_id": source,
			"participant_ids": participants})
	return items

func _candidates(value: Variant) -> Variant:
	if not value is Array or (value as Array).is_empty() or (value as Array).size() > _MAX_CANDIDATES:
		return null
	var items: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw: Variant in value:
		if not raw is Dictionary:
			return null
		var item: Dictionary = raw
		var description: Variant = item.get("description")
		if not _is_id(item.get("id")) or seen.has(item.id) or not description is String \
				or (description as String).strip_edges().is_empty() \
				or (description as String).length() > 500:
			return null
		seen[item.id] = true
		items.append({"id": item.id, "description": description})
	return items

func _id_list(value: Variant, maximum: int, minimum: int = 0) -> Variant:
	if not value is Array or (value as Array).size() < minimum or (value as Array).size() > maximum:
		return null
	var ids: Array[String] = []
	for item: Variant in value:
		if not _is_id(item) or (item as String) in ids:
			return null
		ids.append(item)
	return ids

# --- Expected questions and judgment validation (mirror buildQuestions / validateJudgments) ---

static func _questions(request: Dictionary) -> Dictionary:
	var noul: Dictionary = {"type": "noul"}
	var score: Dictionary = {"type": "score"}
	var questions: Dictionary = {}
	match StringName(request.kind):
		NpcDecisionTicket.APPRAISE:
			questions["immediate_danger"] = noul
			questions["remember"] = noul
			questions["importance"] = score
			for emotion: String in EMOTIONS:
				questions[emotion] = score
			_add_dispositions(questions, request.subjects)
		NpcDecisionTicket.SELECT_GOAL:
			for candidate: Dictionary in request.candidates:
				questions["suitability:" + candidate.id] = score
				questions["duration:" + candidate.id] = _choice(DURATIONS)
		NpcDecisionTicket.SOCIAL:
			questions["engage"] = noul
			questions["topic"] = _choice([SMALL_TALK] + request.topics)
			questions["tone"] = _choice(request.tones)
		NpcDecisionTicket.LISTEN:
			questions["believe_account"] = noul
			questions["remember"] = noul
			questions["importance"] = score
			_add_dispositions(questions, request.subjects)
		NpcDecisionTicket.UTTERANCE:
			questions["speak"] = noul
			questions["intent"] = _choice(request.intents)
	return questions

static func _add_dispositions(questions: Dictionary, subjects: Array) -> void:
	for subject: String in subjects:
		for dimension: String in DIMENSIONS:
			var prefix: String = "disposition:%s:%s:" % [subject, dimension]
			questions[prefix + "direction"] = _choice(DIRECTIONS)
			questions[prefix + "magnitude"] = {"type": "score"}

static func _choice(options: Array) -> Dictionary:
	return {"type": "choice", "options": options}

## The typed questions every /v2/dialogue/chat response answers about the player's message.
static func chat_questions() -> Dictionary:
	var noul: Dictionary = {"type": "noul"}
	var score: Dictionary = {"type": "score"}
	var questions: Dictionary = {"should_remember": noul, "memory_importance": score,
		"emotional_intensity": score, "interaction_intent": _choice(INTENTS),
		"should_end_conversation": noul, "should_retrieve_memories": noul,
		"should_update_belief": noul, "response_mode": _choice(RESPONSE_MODES)}
	for dimension: String in DIMENSIONS:
		questions[dimension + "_change"] = _choice(DIRECTIONS)
	return questions

# Validated judgments, or {} when anything is missing, extra, mistyped or out of range (every
# request has at least one question, so {} is never a valid answer). Dialogue responses carry no
# prompt version or kind.
static func _judgments(job: _Job, body: Dictionary) -> Dictionary:
	var answers: Variant = body.get("judgments")
	var cognition: bool = job.ticket.kind != NpcDecisionTicket.DIALOGUE
	if not _is_number(body.get("protocol_version")) \
			or float(body.protocol_version) != float(job.ticket.protocol_version) \
			or body.get("request_id") != job.ticket.request_id \
			or (cognition and (body.get("prompt_version") != job.ticket.prompt_version
				or body.get("kind") != String(job.ticket.kind))) \
			or not answers is Dictionary or (answers as Dictionary).size() != job.questions.size():
		return {}
	var judgments: Dictionary = {}
	for id: String in job.questions:
		var question: Dictionary = job.questions[id]
		var answer: Variant = (answers as Dictionary).get(id)
		if not answer is Dictionary or answer.get("type") != question.type:
			return {}
		match question.type:
			"noul":
				if not _is_unit(answer.get("noul")):
					return {}
				judgments[id] = {"type": "noul", "noul": float(answer.noul)}
			"choice":
				var options: Array = question.options
				var distribution: Dictionary = _distribution(answer, options)
				if not answer.get("choice") is String or not answer.choice in options \
						or distribution.is_empty():
					return {}
				judgments[id] = {"type": "choice", "choice": answer.choice,
					"confidence": distribution.confidence, "probabilities": distribution.probabilities}
			"score":
				var value: Variant = answer.get("score")
				var distribution: Dictionary = _distribution(answer, _SCORE_LEVELS)
				if not _is_number(value) or float(value) < 0.0 \
						or float(value) > float(_SCORE_LEVELS.size() - 1) or distribution.is_empty():
					return {}
				judgments[id] = {"type": "score", "score": float(value),
					"confidence": distribution.confidence, "probabilities": distribution.probabilities}
	return judgments

static func _distribution(answer: Dictionary, keys: Array) -> Dictionary:
	var probabilities: Variant = answer.get("probabilities")
	if not _is_unit(answer.get("confidence")) or not probabilities is Dictionary \
			or (probabilities as Dictionary).size() != keys.size():
		return {}
	var copied: Dictionary = {}
	var total: float = 0.0
	for key: String in keys:
		var value: Variant = (probabilities as Dictionary).get(key)
		if not _is_unit(value):
			return {}
		copied[key] = float(value)
		total += float(value)
	if absf(total - 1.0) > _PROBABILITY_TOLERANCE:
		return {}
	return {"confidence": float(answer.confidence), "probabilities": copied}

static func _is_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _is_unit(value: Variant) -> bool:
	return _is_number(value) and float(value) >= 0.0 and float(value) <= 1.0

static func _is_id(value: Variant) -> bool:
	if _id_pattern == null:
		_id_pattern = RegEx.create_from_string("^[A-Za-z0-9_:-]{1,100}$")
	return value is String and _id_pattern.search(value) != null
