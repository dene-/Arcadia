extends "res://tests/test_case.gd"

const DialogBackendClientResource = preload("res://game/ui/dialog/dialog_backend_client.gd")
const PATH: String = "/v2/cognition/appraise"

class FakeTransport extends DialogBackendClient.Transport:
	var started_url: String = ""
	var started_body: String = ""
	var start_error: Error = OK
	var aborted: int = 0

	func start(url: String, body: String) -> Error:
		started_url = url
		started_body = body
		return start_error

	func abort() -> void:
		aborted += 1

var _nodes: Array[Node] = []
var _fakes: Array[FakeTransport] = []
var _results: Array[Dictionary] = []

func before_each() -> void:
	_fakes.clear()
	_results.clear()

func after_each() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()

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

func _make_client() -> DialogBackendClient:
	var client := DialogBackendClientResource.new()
	_nodes.append(client)
	return client

func test_cancel_settles_once_aborts_and_frees_the_transport() -> void:
	var client := _make_v2_client()
	_run(client, "a")
	assert_true(client.is_pending("a"))
	var fake: FakeTransport = _fakes[0]
	assert_true(fake.started_url.ends_with(PATH))
	assert_eq(JSON.parse_string(fake.started_body)["request_id"], "a")

	client.cancel("a")
	client.cancel("a")
	client.cancel("unknown")

	assert_eq(_results.size(), 1)
	assert_eq(_results[0]["outcome"], DialogBackendClient.OUTCOME_CANCELLED)
	assert_eq(fake.aborted, 1)
	assert_false(client.is_pending("a"))
	assert_true(await _freed_within_frames(fake))

func test_late_completion_after_cancel_or_deadline_is_ignored() -> void:
	var client := _make_v2_client()
	_run(client, "a")
	var cancelled: FakeTransport = _fakes[0]
	client.cancel("a")
	cancelled.completed.emit(HTTPRequest.RESULT_SUCCESS, 200, '{"late":true}'.to_utf8_buffer())
	assert_eq(_results.size(), 1)
	assert_eq(_results[0]["outcome"], DialogBackendClient.OUTCOME_CANCELLED)
	assert_true((_results[0]["body"] as Dictionary).is_empty())

	var expired: Dictionary = await client.request_v2(PATH, {"request_id": "b"}, 20)
	assert_eq(expired["outcome"], DialogBackendClient.OUTCOME_TIMEOUT)
	# The transport is only queued for deletion, so a straggling completion can still arrive.
	var straggler: FakeTransport = _fakes[1]
	assert_true(is_instance_valid(straggler))
	straggler.completed.emit(HTTPRequest.RESULT_SUCCESS, 200, '{"late":true}'.to_utf8_buffer())
	assert_false(client.is_pending("b"))
	assert_eq(_results.size(), 1)
	# The deadline result arrives inside the timer's emission; let it unwind before teardown.
	await _next_frame()

func test_transport_that_never_completes_times_out_at_its_deadline_and_is_freed() -> void:
	var client := _make_v2_client()
	var started := Time.get_ticks_msec()
	var result: Dictionary = await client.request_v2(PATH, {"request_id": "a"}, 50)
	var elapsed := Time.get_ticks_msec() - started

	assert_eq(result["outcome"], DialogBackendClient.OUTCOME_TIMEOUT)
	assert_true(elapsed >= 40 and elapsed < 2000, "Deadline fired after %d ms." % elapsed)
	var fake: FakeTransport = _fakes[0]
	assert_eq(fake.aborted, 1)
	assert_false(client.is_pending("a"))
	assert_true(await _freed_within_frames(fake))

func test_completed_statuses_map_to_outcomes() -> void:
	var expected := {
		200: DialogBackendClient.OUTCOME_SUCCESS,
		400: DialogBackendClient.OUTCOME_INVALID,
		409: DialogBackendClient.OUTCOME_INVALID,
		502: DialogBackendClient.OUTCOME_INVALID,
		503: DialogBackendClient.OUTCOME_UNAVAILABLE,
	}
	for status: int in expected:
		_results.clear()
		var client := _make_v2_client()
		_run(client, "a")
		_fakes[-1].completed.emit(HTTPRequest.RESULT_SUCCESS, status, '{"ok":true}'.to_utf8_buffer())
		assert_eq(_results.size(), 1, "HTTP %d did not settle once." % status)
		assert_eq(_results[0]["outcome"], expected[status], "HTTP %d" % status)
		assert_eq(_results[0]["status"], status)
		var body: Dictionary = _results[0]["body"]
		assert_eq(body.has("ok"), status == 200, "HTTP %d body" % status)

func test_transport_failures_are_unavailable_and_unreadable_success_is_invalid() -> void:
	var client := _make_v2_client()
	_run(client, "a")
	_fakes[0].completed.emit(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray())
	assert_eq(_results[0]["outcome"], DialogBackendClient.OUTCOME_UNAVAILABLE)

	_run(client, "b")
	_fakes[1].completed.emit(HTTPRequest.RESULT_SUCCESS, 200, "not json".to_utf8_buffer())
	assert_eq(_results[1]["outcome"], DialogBackendClient.OUTCOME_INVALID)

	var failing := FakeTransport.new()
	failing.start_error = ERR_CANT_CONNECT
	client.transport_factory = func() -> DialogBackendClient.Transport: return failing
	var result: Dictionary = await client.request_v2(PATH, {"request_id": "d"}, 1000)
	assert_eq(result["outcome"], DialogBackendClient.OUTCOME_UNAVAILABLE)
	assert_false(client.is_pending("d"))
	await _next_frame()
	assert_false(is_instance_valid(failing))

func test_missing_or_duplicate_handles_are_invalid_without_a_transport() -> void:
	var client := _make_v2_client()
	var missing: Dictionary = await client.request_v2(PATH, {}, 1000)
	assert_eq(missing["outcome"], DialogBackendClient.OUTCOME_INVALID)
	assert_true(_fakes.is_empty())

	_run(client, "a")
	var duplicate: Dictionary = await client.request_v2(PATH, {"request_id": "a"}, 1000)
	assert_eq(duplicate["outcome"], DialogBackendClient.OUTCOME_INVALID)
	assert_eq(_fakes.size(), 1)
	assert_true(client.is_pending("a"))
	client.cancel("a")

func test_cancelled_handle_can_be_reused() -> void:
	var client := _make_v2_client()
	_run(client, "a")
	client.cancel("a")
	_run(client, "a")
	assert_true(client.is_pending("a"))
	_fakes[1].completed.emit(HTTPRequest.RESULT_SUCCESS, 200, '{"ok":true}'.to_utf8_buffer())
	assert_eq(_results[1]["outcome"], DialogBackendClient.OUTCOME_SUCCESS)

func test_leaving_the_tree_settles_every_pending_handle_once() -> void:
	var client := _make_v2_client()
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(client)
	_run(client, "a")
	_run(client, "b")
	root.remove_child(client)
	assert_eq(_results.size(), 2)
	for result: Dictionary in _results:
		assert_eq(result["outcome"], DialogBackendClient.OUTCOME_CANCELLED)
	for fake: FakeTransport in _fakes:
		assert_eq(fake.aborted, 1)
	assert_false(client.is_pending("a"))
	_fakes[0].completed.emit(HTTPRequest.RESULT_SUCCESS, 200, '{"late":true}'.to_utf8_buffer())
	client.cancel("b")
	assert_eq(_results.size(), 2)
	await _next_frame()
	await _next_frame()
	assert_eq(client.get_child_count(), 0)

func test_freeing_the_client_settles_pending_handles_once() -> void:
	var client := _make_v2_client()
	_run(client, "a")
	_run(client, "b")
	var fakes: Array[FakeTransport] = _fakes.duplicate()
	_nodes.erase(client)
	client.free()
	assert_eq(_results.size(), 2)
	for result: Dictionary in _results:
		assert_eq(result["outcome"], DialogBackendClient.OUTCOME_CANCELLED)
	await _next_frame()
	for fake: FakeTransport in fakes:
		assert_false(is_instance_valid(fake))

func test_default_transport_reports_an_unreachable_server_as_unavailable() -> void:
	var client := _make_v2_client(false)
	client.v2_base_url = "http://127.0.0.1:1"
	var result: Dictionary = await client.request_v2(PATH, {"request_id": "a"}, 5000)
	assert_eq(result["outcome"], DialogBackendClient.OUTCOME_UNAVAILABLE)
	assert_false(client.is_pending("a"))
	# The result arrives inside the transport's own signal emission; let it unwind before teardown.
	await _next_frame()
	assert_eq(client.get_child_count(), 0)

func test_default_transport_cancel_settles_locally() -> void:
	var client := _make_v2_client(false)
	client.v2_base_url = "http://127.0.0.1:1"
	_run(client, "a", 5000)
	assert_true(client.is_pending("a"))
	client.cancel("a")
	assert_eq(_results.size(), 1)
	assert_eq(_results[0]["outcome"], DialogBackendClient.OUTCOME_CANCELLED)
	await _next_frame()
	assert_eq(client.get_child_count(), 0)

func _make_v2_client(use_fakes: bool = true) -> DialogBackendClient:
	var client := _make_client()
	if use_fakes:
		client.transport_factory = _new_fake
	else:
		# HTTPRequest only works inside the tree.
		(Engine.get_main_loop() as SceneTree).root.add_child(client)
	return client

func _new_fake() -> DialogBackendClient.Transport:
	var fake := FakeTransport.new()
	_fakes.append(fake)
	return fake

func _run(client: DialogBackendClient, handle: String, deadline_ms: int = 5000) -> void:
	var result: Dictionary = await client.request_v2(PATH, {"request_id": handle}, deadline_ms)
	_results.append(result)

func _next_frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame

# Deferred frees land at the end of a frame; how many frames that takes depends on what else the
# runner has queued, so wait a few frames at most.
func _freed_within_frames(object: Object, frames: int = 3) -> bool:
	for _frame: int in frames:
		if not is_instance_valid(object):
			return true
		await _next_frame()
	return not is_instance_valid(object)
