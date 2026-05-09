extends "res://tests/test_case.gd"

const DialogBackendClientResource = preload("res://game/ui/dialog/dialog_backend_client.gd")

var _nodes: Array[Node] = []

func after_each() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()

func test_build_payload_serializes_profile_without_empty_player_message() -> void:
	var client := _make_client()
	var profile := {
		"name": "Mira",
		"job": "Alchemist",
	}

	var payload: Dictionary = client.call("_build_payload", profile, "")

	assert_true(payload.has("npcData"))
	assert_false(payload.has("playerMessage"))
	var parsed_profile: Variant = JSON.parse_string(str(payload["npcData"]))
	assert_true(parsed_profile is Dictionary)
	assert_eq((parsed_profile as Dictionary)["name"], "Mira")
	assert_eq((parsed_profile as Dictionary)["job"], "Alchemist")

func test_build_payload_includes_non_empty_player_message() -> void:
	var client := _make_client()

	var payload: Dictionary = client.call("_build_payload", {"name": "Mira"}, "Hello")

	assert_eq(payload["playerMessage"], "Hello")

func test_parse_response_body_returns_dictionary_json() -> void:
	var client := _make_client()
	var body := PackedByteArray('{"text":"Welcome","mood":"calm"}'.to_utf8_buffer())

	var parsed: Dictionary = client.call("_parse_response_body", body)

	assert_eq(parsed["text"], "Welcome")
	assert_eq(parsed["mood"], "calm")

func test_parse_response_body_returns_empty_dictionary_for_invalid_json() -> void:
	var client := _make_client()
	var body := PackedByteArray("not json".to_utf8_buffer())

	var parsed: Dictionary = client.call("_parse_response_body", body)

	assert_true(parsed.is_empty())

func test_parse_response_body_returns_empty_dictionary_for_non_dictionary_json() -> void:
	var client := _make_client()
	var body := PackedByteArray("[1,2,3]".to_utf8_buffer())

	var parsed: Dictionary = client.call("_parse_response_body", body)

	assert_true(parsed.is_empty())

func _make_client() -> Node:
	var client := DialogBackendClientResource.new()
	_nodes.append(client)
	return client
