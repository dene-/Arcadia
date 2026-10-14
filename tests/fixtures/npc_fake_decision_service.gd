extends DialogBackendClient

## Scripted stand-in for every provider endpoint. Records deep-copied requests, answers from a
## per-endpoint FIFO queue, then a per-endpoint default, and can hold calls until released.
## v2 judgment endpoints (appraise, select_goal, social, listen, utterance) build a complete,
## valid typed response for the request's questions: a queued or default response holds
## overrides {question_id: noul float | choice String | score number | raw answer Dictionary}.
## Every response may carry "outcome" (UNAVAILABLE, TIMEOUT, INVALID) to fail instead. Text
## routes (react, life/say) answer with the response itself as the body; decision and dialog are
## the v1 player-dialogue endpoints.
const JUDGMENT_ENDPOINTS: Array[String] = ["appraise", "select_goal", "social", "listen", "utterance"]
const ENDPOINTS: Array[String] = ["appraise", "select_goal", "social", "listen", "utterance",
	"react", "life/say", "decision", "dialog"]
const CONFIDENCE: float = 0.9

signal released(endpoint: String)

## Every endpoint is unavailable while set.
var fail_all: bool = false
var _calls: Dictionary = {}
var _queues: Dictionary = {}
var _defaults: Dictionary = {}
var _held: Dictionary = {}
var _cancelled: Dictionary = {}

func _init() -> void:
	for endpoint: String in ENDPOINTS:
		_calls[endpoint] = []
		_queues[endpoint] = []
		_defaults[endpoint] = {}
	_defaults["life/say"] = {"response": "Good day."}

## A v1 player-dialogue policy accepted by NpcMemoryStore.is_valid_policy.
static func valid_policy(remember: bool = true) -> Dictionary:
	return {"remember": remember, "retrieve": false, "update_belief": false, "speak": false,
		"importance": 0.8, "emotional_intensity": 0.7, "response_mode": "NEUTRAL",
		"relationship_delta": {"familiarity": 0.01, "trust": -0.08, "respect": 0.0,
			"affection": 0.0, "fear": 0.08, "suspicion": 0.0}}

func queue_response(endpoint: String, response: Dictionary) -> void:
	_check_endpoint(endpoint)
	_queues[endpoint].append(response.duplicate(true))

func set_default(endpoint: String, response: Dictionary) -> void:
	_check_endpoint(endpoint)
	_defaults[endpoint] = response.duplicate(true)

func hold(endpoint: String) -> void:
	_check_endpoint(endpoint)
	_held[endpoint] = true

## Resumes every call held on this endpoint and stops holding new ones.
func release(endpoint: String) -> void:
	_check_endpoint(endpoint)
	_held.erase(endpoint)
	released.emit(endpoint)

func release_all() -> void:
	for endpoint: String in _held.keys():
		release(endpoint)

func calls(endpoint: String) -> Array[Dictionary]:
	_check_endpoint(endpoint)
	var result: Array[Dictionary] = []
	result.assign(_calls[endpoint].duplicate(true))
	return result

func call_count(endpoint: String) -> int:
	_check_endpoint(endpoint)
	return _calls[endpoint].size()

func total_calls() -> int:
	var total: int = 0
	for endpoint: String in ENDPOINTS:
		total += _calls[endpoint].size()
	return total

func request_v2(path: String, envelope: Dictionary, _deadline_ms: int, handle_id: String = "") -> Dictionary:
	var endpoint: String = path.trim_prefix("/v2/cognition/").replace("-", "_").trim_prefix("/")
	_check_endpoint(endpoint)
	var handle: String = handle_id if not handle_id.is_empty() else str(envelope.get("request_id", ""))
	var response: Variant = await _respond(endpoint, envelope, handle)
	if response == null:
		return {"outcome": OUTCOME_CANCELLED, "status": 0, "body": {}}
	var outcome: StringName = StringName(response.get("outcome", OUTCOME_SUCCESS))
	if fail_all:
		outcome = OUTCOME_UNAVAILABLE
	if outcome != OUTCOME_SUCCESS:
		return {"outcome": outcome, "status": 0, "body": {}}
	response.erase("outcome")
	var body: Dictionary = _judgment_body(endpoint, envelope, response) \
		if endpoint in JUDGMENT_ENDPOINTS else response
	return {"outcome": OUTCOME_SUCCESS, "status": 200, "body": body}

## Settles a held request as cancelled, like the real client.
func cancel(handle_id: String) -> void:
	_cancelled[handle_id] = true
	released.emit("")

func request_decision(payload: Dictionary) -> Dictionary:
	return await _v1("decision", payload)

func request_dialog(payload: Dictionary) -> Dictionary:
	return await _v1("dialog", payload)

func _v1(endpoint: String, payload: Dictionary) -> Dictionary:
	var response: Variant = await _respond(endpoint, payload, "")
	return {} if response == null or fail_all else response

# The next scripted response, or null when the request was cancelled while held.
func _respond(endpoint: String, payload: Dictionary, handle: String) -> Variant:
	_calls[endpoint].append(payload.duplicate(true))
	while _held.has(endpoint) and not _cancelled.has(handle):
		await released
	if _cancelled.has(handle):
		_cancelled.erase(handle)
		return null
	var queue: Array = _queues[endpoint]
	var response: Dictionary = queue.pop_front() if not queue.is_empty() else _defaults[endpoint]
	return response.duplicate(true)

func _judgment_body(endpoint: String, envelope: Dictionary, overrides: Dictionary) -> Dictionary:
	var questions: Dictionary = NpcDecisionService._questions(envelope)
	var judgments: Dictionary = {}
	for id: String in questions:
		var question: Dictionary = questions[id]
		var value: Variant = overrides.get(id, _default_value(endpoint, envelope, id, question))
		judgments[id] = value if value is Dictionary else _answer(question, value)
	return {"protocol_version": envelope.get("protocol_version"),
		"prompt_version": envelope.get("prompt_version"), "request_id": envelope.get("request_id"),
		"kind": envelope.get("kind"), "judgments": judgments}

static func _default_value(endpoint: String, envelope: Dictionary, id: String,
		question: Dictionary) -> Variant:
	if id.begins_with("disposition:"):
		return "UNCHANGED" if id.ends_with(":direction") else 0.0
	match endpoint:
		"appraise":
			return {"immediate_danger": 0.1, "remember": 0.9, "importance": 3.0}.get(id, 0.0)
		"select_goal":
			if id.begins_with("duration:"):
				return "ORDINARY"
			return 3.0 if id == "suitability:" + String(envelope.candidates[0].id) else 1.0
		"social":
			if id == "topic":
				return envelope.topics[0] if not envelope.topics.is_empty() \
					else NpcDecisionService.SMALL_TALK
			return envelope.tones[0] if id == "tone" else CONFIDENCE
		"listen":
			return 3.0 if id == "importance" else CONFIDENCE
		"utterance":
			return envelope.intents[0] if id == "intent" else CONFIDENCE
	return question.get("options", [""])[0] if question.type == "choice" else 0.0

static func _answer(question: Dictionary, value: Variant) -> Dictionary:
	match question.type:
		"noul":
			return {"type": "noul", "noul": float(value)}
		"choice":
			return {"type": "choice", "choice": value, "confidence": CONFIDENCE,
				"probabilities": _spread(question.options, String(value))}
	return {"type": "score", "score": float(value), "confidence": CONFIDENCE,
		"probabilities": _spread(["0", "1", "2", "3", "4"], str(clampi(roundi(float(value)), 0, 4)))}

static func _spread(keys: Array, chosen: String) -> Dictionary:
	var probabilities: Dictionary = {}
	var rest: float = (1.0 - CONFIDENCE) / maxf(keys.size() - 1, 1)
	for key: String in keys:
		probabilities[key] = CONFIDENCE if key == chosen else rest
	if keys.size() == 1:
		probabilities[chosen] = 1.0
	return probabilities

func _check_endpoint(endpoint: String) -> void:
	assert(endpoint in ENDPOINTS, "Unknown fake endpoint: " + endpoint)
