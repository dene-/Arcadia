extends DialogBackendClient

## Scripted stand-in for every provider endpoint. Records deep-copied payloads, answers from a
## per-endpoint FIFO queue, then a per-endpoint default, and can hold calls until released.
## Endpoint keys: observation, reaction, decision, dialog, life/routine, life/social,
## life/listen, life/say.
const ENDPOINTS: Array[String] = ["observation", "reaction", "decision", "dialog",
	"life/routine", "life/social", "life/listen", "life/say"]

signal released(endpoint: String)

## Every endpoint answers {} (provider unavailable) while set.
var fail_all: bool = false
var _calls: Dictionary = {}
var _queues: Dictionary = {}
var _defaults: Dictionary = {}
var _held: Dictionary = {}

func _init() -> void:
	for endpoint: String in ENDPOINTS:
		_calls[endpoint] = []
		_queues[endpoint] = []
		_defaults[endpoint] = {}
	_defaults["observation"] = {"policy": valid_policy(), "answers": {}}

## A policy accepted by NpcMemoryStore.is_valid_policy.
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

func request_life(kind: String, payload: Dictionary) -> Dictionary:
	if not kind in ["routine", "social", "listen", "say"]:
		return {}
	return await _respond("life/" + kind, payload)

func request_observation(payload: Dictionary) -> Dictionary:
	return await _respond("observation", payload)

func request_reaction(payload: Dictionary) -> Dictionary:
	return await _respond("reaction", payload)

func request_decision(payload: Dictionary) -> Dictionary:
	return await _respond("decision", payload)

func request_dialog(payload: Dictionary) -> Dictionary:
	return await _respond("dialog", payload)

func _respond(endpoint: String, payload: Dictionary) -> Dictionary:
	_calls[endpoint].append(payload.duplicate(true))
	while _held.has(endpoint):
		await released
	if fail_all:
		return {}
	var queue: Array = _queues[endpoint]
	var response: Dictionary = queue.pop_front() if not queue.is_empty() else _defaults[endpoint]
	return response.duplicate(true)

func _check_endpoint(endpoint: String) -> void:
	assert(endpoint in ENDPOINTS, "Unknown fake endpoint: " + endpoint)
