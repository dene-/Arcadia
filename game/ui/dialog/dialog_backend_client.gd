class_name DialogBackendClient
extends Node

const CHAT_ENDPOINT: String = "http://127.0.0.1:3536/chat"

## HTTP endpoint used by DialogManager to request generated NPC dialog.
@export var chat_endpoint: String = CHAT_ENDPOINT

var _http_request: HTTPRequest

func _ready() -> void:
	_ensure_http_request()

func request_dialog(profile: Dictionary, player_message: String = "") -> Dictionary:
	_ensure_http_request()
	if _http_request == null:
		return {}

	var payload := _build_payload(profile, player_message)
	var error := _http_request.request(
		chat_endpoint,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if error != OK:
		push_warning("Dialog backend request failed to start: %s" % error)
		return {}

	var result: Array = await _http_request.request_completed
	var response_code: int = result[1]
	var response_body: PackedByteArray = result[3]
	if response_code < 200 or response_code >= 300:
		push_warning("Dialog backend returned HTTP %s" % response_code)
		return {}

	return _parse_response_body(response_body)

func _ensure_http_request() -> void:
	if _http_request != null:
		return

	_http_request = HTTPRequest.new()
	add_child(_http_request)

func _build_payload(profile: Dictionary, player_message: String) -> Dictionary:
	var payload: Dictionary = {
		"npcData": JSON.stringify(profile),
	}
	if not player_message.is_empty():
		payload["playerMessage"] = player_message
	return payload

func _parse_response_body(response_body: PackedByteArray) -> Dictionary:
	var body_string: String = response_body.get_string_from_utf8().strip_edges()
	var json := JSON.new()
	if json.parse(body_string) == OK and json.data is Dictionary:
		return json.data as Dictionary
	return {}
