class_name DialogBackendClient
extends Node

const CHAT_ENDPOINT: String = "http://127.0.0.1:3536/chat"

@export var chat_endpoint: String = CHAT_ENDPOINT
@export var decision_endpoint: String = "http://127.0.0.1:3536/decide"
@export var observation_endpoint: String = "http://127.0.0.1:3536/observe"
@export var reaction_endpoint: String = "http://127.0.0.1:3536/react"

func request_observation(payload: Dictionary) -> Dictionary:
	return await _request(observation_endpoint, payload)

func request_reaction(payload: Dictionary) -> Dictionary:
	return await _request(reaction_endpoint, payload)

func request_decision(payload: Dictionary) -> Dictionary:
	return await _request(decision_endpoint, payload)

func request_dialog(payload: Dictionary) -> Dictionary:
	return await _request(chat_endpoint, payload)

func _request(endpoint: String, payload: Dictionary) -> Dictionary:
	# Independent requests prevent close/reopen from colliding with a pending HTTPRequest.
	var request := HTTPRequest.new()
	request.timeout = 45.0
	request.body_size_limit = 98304
	add_child(request)
	var error: Error = request.request(endpoint, ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		request.queue_free()
		push_warning("Dialog backend request failed to start: %s" % error)
		return {}
	var result: Array = await request.request_completed
	request.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] < 200 or result[1] >= 300:
		push_warning("Dialog backend unavailable (HTTP %s)." % result[1])
		return {}
	return _parse_response_body(result[3])

func _parse_response_body(response_body: PackedByteArray) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(response_body.get_string_from_utf8()) != OK:
		return {}
	return parser.data if parser.data is Dictionary else {}
