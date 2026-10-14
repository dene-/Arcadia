class_name DialogBackendClient
extends Node

# Transport deadlines: server route budget plus a 2000 ms margin (tools/server UPSTREAM_BUDGETS_MS).
const JUDGMENT_DEADLINE_MS: int = 10000
const DIALOGUE_DEADLINE_MS: int = 40000
const AMBIENT_DEADLINE_MS: int = 12000

const OUTCOME_SUCCESS: StringName = &"SUCCESS"
const OUTCOME_UNAVAILABLE: StringName = &"UNAVAILABLE"
const OUTCOME_TIMEOUT: StringName = &"TIMEOUT"
const OUTCOME_INVALID: StringName = &"INVALID"
const OUTCOME_CANCELLED: StringName = &"CANCELLED"

## One network exchange. Emits `completed` at most once per `start`; `abort` stops it silently.
class Transport extends Node:
	signal completed(result: int, status: int, body: PackedByteArray)

	func start(_url: String, _body: String) -> Error:
		return ERR_UNAVAILABLE

	func abort() -> void:
		pass

class HttpTransport extends Transport:
	const HEADERS: PackedStringArray = ["Content-Type: application/json"]
	const BODY_SIZE_LIMIT: int = 98304
	var _http: HTTPRequest

	func _init() -> void:
		_http = HTTPRequest.new()
		_http.body_size_limit = BODY_SIZE_LIMIT
		add_child(_http)
		_http.request_completed.connect(_on_request_completed)

	func start(url: String, body: String) -> Error:
		return _http.request(url, HEADERS, HTTPClient.METHOD_POST, body)

	func abort() -> void:
		_http.cancel_request()

	func _on_request_completed(result: int, status: int, _headers: PackedStringArray,
			body: PackedByteArray) -> void:
		completed.emit(result, status, body)

class Pending extends RefCounted:
	signal settled
	var transport: Transport
	var done: bool = false
	var result: Dictionary = {}

@export var v2_base_url: String = "http://127.0.0.1:3536"

## Returns a new Transport per request. Unset: HttpTransport. Tests inject fakes here.
var transport_factory: Callable = Callable()
var _pending: Dictionary[String, Pending] = {}

## Awaitable v2 request. `handle_id` (default: envelope.request_id) is the key for `cancel`.
## Settles exactly once with {outcome: StringName, status: int, body: Dictionary}; body is the
## parsed JSON object on SUCCESS and empty otherwise. Never waits on the transport after a
## cancel or deadline: the transport is aborted and freed, and any late completion is ignored.
func request_v2(path: String, envelope: Dictionary, deadline_ms: int, handle_id: String = "") -> Dictionary:
	var handle: String = handle_id if not handle_id.is_empty() else str(envelope.get("request_id", ""))
	if handle.is_empty() or deadline_ms <= 0 or _pending.has(handle):
		return _result(OUTCOME_INVALID)
	var pending := Pending.new()
	_pending[handle] = pending
	var transport: Transport = _make_transport()
	pending.transport = transport
	add_child(transport)
	transport.completed.connect(_on_transport_completed.bind(handle, pending))
	var error: Error = transport.start(v2_base_url + path, JSON.stringify(envelope))
	if error != OK:
		push_warning("Dialog backend v2 request failed to start: %s" % error)
		_settle(handle, pending, _result(OUTCOME_UNAVAILABLE), true)
	else:
		_arm_deadline(handle, pending, Time.get_ticks_msec() + deadline_ms)
	if not pending.done:
		await pending.settled
	return pending.result

func _exit_tree() -> void:
	_cancel_all()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_cancel_all()

## Settles the pending v2 request locally as CANCELLED. Unknown or finished handles are ignored.
func cancel(handle_id: String) -> void:
	var pending: Pending = _pending.get(handle_id)
	if pending != null:
		_settle(handle_id, pending, _result(OUTCOME_CANCELLED), true)

func _cancel_all() -> void:
	for handle: String in _pending.keys():
		cancel(handle)

func is_pending(handle_id: String) -> bool:
	return _pending.has(handle_id)

## Status mapping for completed exchanges: 2xx SUCCESS; 409 (protocol), other 4xx and 502
## (provider payload rejected) INVALID; 503 and any other status UNAVAILABLE.
static func outcome_for_status(status: int) -> StringName:
	if status >= 200 and status < 300:
		return OUTCOME_SUCCESS
	if status == 502 or (status >= 400 and status < 500):
		return OUTCOME_INVALID
	return OUTCOME_UNAVAILABLE

func _make_transport() -> Transport:
	if transport_factory.is_valid():
		return transport_factory.call() as Transport
	return HttpTransport.new()

func _on_transport_completed(result: int, status: int, body: PackedByteArray,
		handle: String, pending: Pending) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_settle(handle, pending, _result(OUTCOME_UNAVAILABLE, status), false)
		return
	var outcome: StringName = outcome_for_status(status)
	var parsed: Dictionary = {}
	if outcome == OUTCOME_SUCCESS:
		parsed = _parse_response_body(body)
		if parsed.is_empty():
			outcome = OUTCOME_INVALID
	if outcome != OUTCOME_SUCCESS:
		push_warning("Dialog backend v2 request failed (HTTP %s)." % status)
	_settle(handle, pending, _result(outcome, status, parsed), false)

func _arm_deadline(handle: String, pending: Pending, deadline_at_msec: int) -> void:
	# The timer only wakes the check; expiry is judged on the monotonic clock, so a long frame
	# can never fire the deadline early and wall-clock changes never matter.
	var remaining_msec: int = maxi(deadline_at_msec - Time.get_ticks_msec(), 1)
	var tree := Engine.get_main_loop() as SceneTree
	tree.create_timer(remaining_msec / 1000.0, true, false, true).timeout.connect(
		_on_deadline.bind(handle, pending, deadline_at_msec))

func _on_deadline(handle: String, pending: Pending, deadline_at_msec: int) -> void:
	if pending.done:
		return
	if Time.get_ticks_msec() < deadline_at_msec:
		_arm_deadline(handle, pending, deadline_at_msec)
		return
	_settle(handle, pending, _result(OUTCOME_TIMEOUT), true)

func _settle(handle: String, pending: Pending, result: Dictionary, abort_transport: bool) -> void:
	if pending.done:
		return
	pending.done = true
	pending.result = result
	if _pending.get(handle) == pending:
		_pending.erase(handle)
	var transport: Transport = pending.transport
	pending.transport = null
	if is_instance_valid(transport):
		for connection: Dictionary in transport.completed.get_connections():
			transport.completed.disconnect(connection["callable"])
		if abort_transport:
			transport.abort()
		transport.queue_free()
	pending.settled.emit()

static func _result(outcome: StringName, status: int = 0, body: Dictionary = {}) -> Dictionary:
	return {"outcome": outcome, "status": status, "body": body}

func _parse_response_body(response_body: PackedByteArray) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(response_body.get_string_from_utf8()) != OK:
		return {}
	return parser.data if parser.data is Dictionary else {}
