extends "res://tests/test_case.gd"

const Fixtures = preload("res://tests/fixtures/cognition_contract_fixtures.gd")

## Stands in for DialogBackendClient.request_v2. `responder` answers each call; an empty answer
## holds the call until `release` (and a cancelled call is never answered).
class FakeTransport extends DialogBackendClient:
	signal answered
	var responder: Callable = func(_path: String, _envelope: Dictionary) -> Dictionary: return {}
	var calls: Array[Dictionary] = []
	var cancelled: Array[String] = []
	var _released: Dictionary = {}

	func request_v2(path: String, envelope: Dictionary, deadline_ms: int,
			handle_id: String = "") -> Dictionary:
		calls.append({"path": path, "envelope": envelope.duplicate(true),
			"deadline_ms": deadline_ms, "handle": handle_id})
		var answer: Dictionary = responder.call(path, envelope)
		while answer.is_empty():
			await answered
			answer = _released.get(handle_id, {})
		return answer

	func cancel(handle_id: String) -> void:
		cancelled.append(handle_id)

	func release(handle_id: String, answer: Dictionary) -> void:
		_released[handle_id] = answer
		answered.emit()

	func handles() -> Array[String]:
		var ids: Array[String] = []
		for call: Dictionary in calls:
			ids.append(call.handle)
		return ids

var _service: NpcDecisionService
var _transport: FakeTransport
var _settled: Array[NpcDecisionResult] = []
var _now_msec: int = 1000

func before_each() -> void:
	_settled.clear()
	_now_msec = 1000
	_transport = FakeTransport.new()
	_service = NpcDecisionService.new()
	_service.transport = _transport
	_service.clock = func() -> int: return _now_msec
	(Engine.get_main_loop() as SceneTree).root.add_child(_service)

func after_each() -> void:
	_service.free()
	_transport.free()

static func _success(body: Dictionary) -> Dictionary:
	return {"outcome": DialogBackendClient.OUTCOME_SUCCESS, "status": 200, "body": body}

static func _normalized(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

func _ticket(kind: String, npc_id: String, request_id: String,
		urgency: NpcDecisionTicket.Urgency) -> NpcDecisionTicket:
	var ticket: NpcDecisionTicket = Fixtures.ticket(Fixtures.request(kind))
	ticket.npc_id = npc_id
	ticket.request_id = request_id
	ticket.urgency = urgency
	return ticket

func _launch(kind: String, npc_id: String, request_id: String,
		urgency: NpcDecisionTicket.Urgency = NpcDecisionTicket.Urgency.INTERACTIVE) -> void:
	var ticket: NpcDecisionTicket = _ticket(kind, npc_id, request_id, urgency)
	_settled.append(await _service.evaluate(ticket, Fixtures.payload(Fixtures.request(kind))))

func _launch_text(npc_id: String, request_id: String) -> void:
	var ticket: NpcDecisionTicket = _ticket("utterance", npc_id, request_id,
		NpcDecisionTicket.Urgency.INTERACTIVE)
	_settled.append(await _service.run_text(ticket, "/life/say", {"intent": "warn"}))

func _answer_appraise(request_id: String) -> Dictionary:
	var body: Dictionary = Fixtures.response("appraise")
	body.request_id = request_id
	return _success(body)

func _outcomes(request_id: String) -> Array:
	var outcomes: Array = []
	for result: NpcDecisionResult in _settled:
		if result.ticket.request_id == request_id:
			outcomes.append(result.outcome)
	return outcomes

func test_every_fixture_kind_round_trips_to_success_and_the_policy_maps_it() -> void:
	_transport.responder = func(_path: String, envelope: Dictionary) -> Dictionary:
		return _success(Fixtures.response(envelope.kind))
	var tuning := NpcBehaviorTuning.new()
	for kind: String in Fixtures.kinds():
		var envelope: Dictionary = Fixtures.request(kind)
		var result: NpcDecisionResult = await _service.evaluate(Fixtures.ticket(envelope),
			Fixtures.payload(envelope))
		assert_eq(result.outcome, NpcDecisionResult.Outcome.SUCCESS, kind)
		var call: Dictionary = _transport.calls[-1]
		assert_eq(call.path, Fixtures.route(kind))
		assert_eq(call.deadline_ms, DialogBackendClient.JUDGMENT_DEADLINE_MS)
		assert_eq(_normalized(call.envelope), envelope, "%s envelope matches the fixture" % kind)
		assert_eq(result.judgments.size(), Fixtures.response(kind).judgments.size())
		match kind:
			"appraise":
				var appraisal: NpcDecisionPolicy.Appraisal = NpcDecisionPolicy.appraisal(result, tuning)
				assert_true(appraisal.immediate_danger)
				assert_true(appraisal.remember)
				assert_true(is_equal_approx(appraisal.importance, 0.8125))
				assert_true(is_equal_approx(appraisal.emotions.fear, 0.625))
				assert_true(is_equal_approx(appraisal.dispositions.player.trust, -0.0875))
				assert_true(is_equal_approx(appraisal.dispositions.player.fear, 0.05))
				assert_true(is_equal_approx(appraisal.dispositions.mirelle.affection, 0.025))
				assert_eq(appraisal.dispositions.player.size(), 2)
			"select_goal":
				var goal: NpcDecisionPolicy.GoalChoice = NpcDecisionPolicy.goal_choice(result, tuning)
				assert_eq(goal.candidate_id, "VISIT_MIRELLE")
				assert_eq(goal.duration_minutes, tuning.extended_goal_minutes)
			"social":
				var social: NpcDecisionPolicy.Social = NpcDecisionPolicy.social(result, "friendly", tuning)
				assert_true(social.engage)
				assert_eq(social.topic, "news:forge_attack")
				assert_eq(social.tone, "concerned")
			"listen":
				var heard: NpcDecisionPolicy.Listening = NpcDecisionPolicy.listening(result, "mirelle", tuning)
				assert_false(heard.believe, "0.64 is below the belief threshold")
				assert_true(heard.remember)
				assert_true(heard.dispositions.is_empty(), "A disbelieved account blames nobody")
			"utterance":
				var permitted: Array[String] = ["warn", "acknowledge"]
				var spoken: NpcDecisionPolicy.Utterance = NpcDecisionPolicy.utterance(result, permitted, tuning)
				assert_true(spoken.speak)
				assert_eq(spoken.intent, "warn")
	assert_eq(_transport.calls.size(), Fixtures.kinds().size())

func test_each_invalid_provider_payload_is_invalid_without_judgments() -> void:
	for case: Dictionary in Fixtures.invalid_cases():
		_transport.responder = func(_path: String, _envelope: Dictionary) -> Dictionary:
			return _success(case.response)
		var envelope: Dictionary = Fixtures.request(case.kind)
		var result: NpcDecisionResult = await _service.evaluate(Fixtures.ticket(envelope),
			Fixtures.payload(envelope))
		assert_eq(result.outcome, NpcDecisionResult.Outcome.INVALID, case.file)
		assert_true(result.judgments.is_empty(), case.file)

func test_mismatched_response_header_or_transport_failure_is_not_success() -> void:
	var envelope: Dictionary = Fixtures.request("appraise")
	_transport.responder = func(_path: String, _envelope: Dictionary) -> Dictionary:
		var body: Dictionary = Fixtures.response("appraise")
		body.request_id = "req:someone_else"
		return _success(body)
	var foreign: NpcDecisionResult = await _service.evaluate(Fixtures.ticket(envelope),
		Fixtures.payload(envelope))
	assert_eq(foreign.outcome, NpcDecisionResult.Outcome.INVALID)
	_transport.responder = func(_path: String, _envelope: Dictionary) -> Dictionary:
		return {"outcome": DialogBackendClient.OUTCOME_UNAVAILABLE, "status": 503, "body": {}}
	var unavailable: NpcDecisionResult = await _service.evaluate(Fixtures.ticket(envelope),
		Fixtures.payload(envelope))
	assert_eq(unavailable.outcome, NpcDecisionResult.Outcome.UNAVAILABLE)
	assert_true(unavailable.judgments.is_empty())

func test_malformed_request_is_invalid_without_contacting_the_provider() -> void:
	var social: Dictionary = Fixtures.request("social")
	var payload: Dictionary = Fixtures.payload(social)
	payload.topics.append(NpcDecisionService.SMALL_TALK)
	var reserved_topic: NpcDecisionResult = await _service.evaluate(Fixtures.ticket(social), payload)
	var goal: Dictionary = Fixtures.request("select_goal")
	var unnamed: NpcDecisionTicket = Fixtures.ticket(goal)
	unnamed.candidate_ids.remove_at(0)
	var foreign_candidates: NpcDecisionResult = await _service.evaluate(unnamed, Fixtures.payload(goal))
	var outdated: NpcDecisionTicket = Fixtures.ticket(goal)
	outdated.prompt_version = "cognition-0"
	var other_prompt: NpcDecisionResult = await _service.evaluate(outdated, Fixtures.payload(goal))
	for result: NpcDecisionResult in [reserved_topic, foreign_candidates, other_prompt]:
		assert_eq(result.outcome, NpcDecisionResult.Outcome.INVALID)
	assert_true(_transport.calls.is_empty())

func test_cancel_and_cancel_owner_settle_once_and_release_capacity() -> void:
	for index: int in range(5):
		_launch("appraise", "npc_%d" % (index % 2), "req:%d" % index)
	assert_eq(_service.active_count(NpcDecisionService.Pool.JUDGMENT), 4)
	assert_eq(_service.queued_count(NpcDecisionService.Pool.JUDGMENT), 1)
	_service.cancel("req:1")
	assert_eq(_outcomes("req:1"), [NpcDecisionResult.Outcome.CANCELLED])
	assert_true("req:1" in _transport.cancelled, "The transport request is aborted")
	assert_true("req:4" in _transport.handles(), "The freed permit starts the queued request")
	_transport.release("req:1", _answer_appraise("req:1"))
	_service.cancel("req:1")
	assert_eq(_outcomes("req:1"), [NpcDecisionResult.Outcome.CANCELLED], "A late answer is ignored")
	_service.cancel_owner("npc_0")
	for request_id: String in ["req:0", "req:2", "req:4"]:
		assert_eq(_outcomes(request_id), [NpcDecisionResult.Outcome.CANCELLED], request_id)
	assert_eq(_service.active_count(NpcDecisionService.Pool.JUDGMENT), 1)
	_transport.release("req:3", _answer_appraise("req:3"))
	assert_eq(_outcomes("req:3"), [NpcDecisionResult.Outcome.SUCCESS])
	assert_eq(_service.active_count(NpcDecisionService.Pool.JUDGMENT), 0)
	assert_eq(_settled.size(), 5, "Every request settled exactly once")

func test_pools_limit_judgment_to_four_and_text_to_two() -> void:
	for index: int in range(6):
		_launch("appraise", "npc_%d" % index, "req:judge:%d" % index)
	for index: int in range(3):
		_launch_text("speaker_%d" % index, "req:text:%d" % index)
	assert_eq(_service.active_count(NpcDecisionService.Pool.JUDGMENT), 4)
	assert_eq(_service.queued_count(NpcDecisionService.Pool.JUDGMENT), 2)
	assert_eq(_service.active_count(NpcDecisionService.Pool.TEXT), 2)
	assert_eq(_service.queued_count(NpcDecisionService.Pool.TEXT), 1)
	_transport.release("req:text:0", _success({"text": "Watch out!"}))
	var spoken: Array = _settled.filter(
		func(result: NpcDecisionResult) -> bool: return result.ticket.request_id == "req:text:0")
	assert_eq(spoken[0].body.text, "Watch out!")
	assert_eq(_transport.calls[-1].path, "/life/say")
	assert_eq(_transport.calls[-1].deadline_ms, DialogBackendClient.AMBIENT_DEADLINE_MS)
	assert_eq(_service.active_count(NpcDecisionService.Pool.TEXT), 2)
	assert_eq(_service.queued_count(NpcDecisionService.Pool.TEXT), 0)

func test_background_work_leaves_a_permit_for_interactive_work() -> void:
	for index: int in range(4):
		_launch("appraise", "npc_%d" % index, "req:bg:%d" % index, NpcDecisionTicket.Urgency.BACKGROUND)
	assert_eq(_service.active_count(NpcDecisionService.Pool.JUDGMENT), 3)
	_launch("appraise", "talker", "req:talk")
	assert_true("req:talk" in _transport.handles(), "Interactive work starts at once")
	assert_eq(_service.queued_count(NpcDecisionService.Pool.JUDGMENT), 1)

func test_npcs_take_turns_when_permits_free_up() -> void:
	for index: int in range(4):
		_launch("appraise", "busy", "req:busy:%d" % index)
	_launch("appraise", "busy", "req:busy:4")
	_launch("appraise", "busy", "req:busy:5")
	_launch("appraise", "quiet", "req:quiet")
	_transport.release("req:busy:0", _answer_appraise("req:busy:0"))
	assert_eq(_transport.handles()[-1], "req:quiet", "The NPC served least recently goes first")
	_transport.release("req:busy:1", _answer_appraise("req:busy:1"))
	assert_eq(_transport.handles()[-1], "req:busy:4")

func test_waiting_background_work_ages_ahead_of_newer_safety_work() -> void:
	for index: int in range(4):
		_launch("appraise", "talker_%d" % index, "req:talk:%d" % index)
	_launch("appraise", "walker", "req:routine", NpcDecisionTicket.Urgency.BACKGROUND)
	_now_msec += NpcDecisionService.AGING_MSEC + 1000
	_launch("appraise", "guard", "req:safety", NpcDecisionTicket.Urgency.SAFETY)
	_transport.release("req:talk:0", _answer_appraise("req:talk:0"))
	assert_eq(_transport.handles()[-1], "req:routine")
	_transport.release("req:talk:1", _answer_appraise("req:talk:1"))
	assert_eq(_transport.handles()[-1], "req:safety")

func test_a_newer_select_goal_stales_the_queued_older_one() -> void:
	for index: int in range(4):
		_launch("appraise", "talker_%d" % index, "req:talk:%d" % index)
	_launch("select_goal", "garrin_holt", "req:goal:old", NpcDecisionTicket.Urgency.BACKGROUND)
	_launch("select_goal", "garrin_holt", "req:goal:new", NpcDecisionTicket.Urgency.BACKGROUND)
	assert_eq(_outcomes("req:goal:old"), [NpcDecisionResult.Outcome.STALE])
	assert_eq(_service.queued_count(NpcDecisionService.Pool.JUDGMENT), 1)
	_service.cancel_owner("talker_0")
	_service.cancel_owner("talker_1")
	assert_eq(_transport.handles()[-1], "req:goal:new")
	assert_false("req:goal:old" in _transport.handles())

func test_deadlines_time_out_queued_and_running_requests() -> void:
	var envelope: Dictionary = Fixtures.request("appraise")
	var expired: NpcDecisionTicket = Fixtures.ticket(envelope)
	expired.deadline_tick_msec = _now_msec
	var late: NpcDecisionResult = await _service.evaluate(expired, Fixtures.payload(envelope))
	assert_eq(late.outcome, NpcDecisionResult.Outcome.TIMEOUT)
	assert_true(_transport.calls.is_empty())
	_launch("appraise", "garrin_holt", "req:slow")
	assert_eq(_transport.calls[-1].deadline_ms, DialogBackendClient.JUDGMENT_DEADLINE_MS)
	_now_msec += DialogBackendClient.JUDGMENT_DEADLINE_MS
	# process_frame fires before nodes process, so the service's tick has run after the second one.
	for _frame: int in range(2):
		await (Engine.get_main_loop() as SceneTree).process_frame
	assert_eq(_outcomes("req:slow"), [NpcDecisionResult.Outcome.TIMEOUT])
	assert_true("req:slow" in _transport.cancelled)
	assert_eq(_service.active_count(NpcDecisionService.Pool.JUDGMENT), 0)
