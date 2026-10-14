extends "res://tests/test_case.gd"

const FakeService = preload("res://tests/fixtures/npc_fake_decision_service.gd")
const SESSION: String = "player:1"
const CHAT: String = "dialogue/chat"

var _backend: FakeService
var _decisions: NpcDecisionService
var _completed: bool = false
var _result: Dictionary = {}

func before_each() -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	_backend = FakeService.new()
	root.add_child(_backend)
	_decisions = NpcDecisionService.new()
	_decisions.transport = _backend
	root.add_child(_decisions)
	_completed = false
	_result = {}

func after_each() -> void:
	_backend.release_all()
	_decisions.free()
	_backend.free()

func _profile() -> NpcProfile:
	var profile := NpcProfile.new()
	profile.npc_id = &"test_npc"
	profile.memories = ["The player brought a dagger."]
	return profile

func _conversation() -> NpcConversation:
	var conversation := NpcConversation.new()
	conversation.persist = false
	conversation.session_id = SESSION
	return conversation

func _start(conversation: NpcConversation, message: String = "Where is the dagger?",
		guard: Callable = Callable()) -> void:
	_completed = false
	_result = await conversation.request(_profile(), {}, message, _decisions, guard)
	_completed = true

## Waits for the request started by `_start` to settle after the backend was released.
func _finish() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	for _frame: int in range(300):
		if _completed:
			return
		await tree.process_frame

func _trust(conversation: NpcConversation) -> float:
	return conversation.store.minds.get_mind("test_npc").relationships.get_relationship("player").trust

func test_nothing_commits_until_the_chat_answer_arrives() -> void:
	var conversation := _conversation()
	_backend.set_default(CHAT, FakeService.threat_chat())
	_backend.hold(CHAT)
	_start(conversation)
	assert_false(_completed)
	assert_eq(_backend.call_count(CHAT), 1, "One request carries judgment and reply")
	assert_eq(_trust(conversation), 0.0)
	var request: Dictionary = _backend.calls(CHAT)[0]
	assert_eq(request.memories.size(), 1)
	assert_eq(request.player.message, "Where is the dagger?")
	assert_false(request.npc.profile.has("memories"))
	_backend.release(CHAT)
	await _finish()
	assert_true(_completed)
	assert_eq(_result.response, "Leave my forge.")
	assert_eq(_trust(conversation), -0.08)
	assert_eq(conversation.store.snapshot("test_npc").recent_dialogue.size(), 2)

func test_opening_greeting_reaches_the_model_and_history_without_replacing_player_text() -> void:
	var conversation := _conversation()
	await conversation.request(_profile(), {}, "", _decisions)
	var greeting: String = _backend.calls(CHAT)[0].player.message
	assert_true(NpcConversation.OPENING_GREETINGS.has(greeting))
	assert_eq(conversation.store.snapshot("test_npc").recent_dialogue[0].text, greeting)
	await conversation.request(_profile(), {}, "Can you mend this?", _decisions)
	assert_eq(_backend.calls(CHAT)[1].player.message, "Can you mend this?")
	assert_eq(conversation.store.snapshot("test_npc").recent_dialogue[2].text, "Can you mend this?")

func test_cancel_during_the_request_drops_the_late_response_and_frees_the_permit() -> void:
	var conversation := _conversation()
	_backend.set_default(CHAT, {"should_end_conversation": 0.99}.merged(FakeService.threat_chat()))
	_backend.hold(CHAT)
	_start(conversation)
	assert_eq(_decisions.active_count(NpcDecisionService.Pool.TEXT), 1)
	conversation.cancel()
	assert_eq(_decisions.active_count(NpcDecisionService.Pool.TEXT), 0)
	_backend.release(CHAT)
	await _finish()
	assert_true(_completed)
	assert_true(_result.is_empty())
	assert_eq(conversation.store.turn, 0)
	assert_eq(conversation.store.snapshot("test_npc").recent_dialogue.size(), 0)
	assert_eq(_trust(conversation), 0.0)

func test_surrender_comes_from_assessed_intent_never_dialogue_metadata() -> void:
	var conversation := _conversation()
	_backend.set_default(CHAT, {"surrender": true})
	var first: Dictionary = await conversation.request(_profile(), {}, "What does surrender mean?",
		_decisions)
	assert_false(first.surrender)
	_backend.queue_response(CHAT, {"interaction_intent": "SURRENDER"})
	var second: Dictionary = await conversation.request(_profile(), {}, "I surrender.", _decisions)
	assert_true(second.surrender)

func test_farewell_commits_response_before_returning_end_decision() -> void:
	var conversation := _conversation()
	_backend.queue_response(CHAT, {"should_end_conversation": 0.99, "response": "Until next time."})
	var result: Dictionary = await conversation.request(_profile(), {}, "See you.", _decisions)
	assert_true(result.end_conversation)
	var history: Array = conversation.store.snapshot("test_npc").recent_dialogue
	assert_eq(history[0].text, "See you.")
	assert_eq(history[1].text, "Until next time.")
	_backend.queue_response(CHAT, {"outcome": "UNAVAILABLE"})
	result = await conversation.request(_profile(), {}, "Bye.", _decisions)
	assert_true(result.is_empty(), "Failed dialogue must not trigger an exit")

func test_a_weak_end_judgment_does_not_end_the_conversation() -> void:
	var conversation := _conversation()
	_backend.queue_response(CHAT, {"should_end_conversation": 0.5})
	var result: Dictionary = await conversation.request(_profile(), {}, "Hmm.", _decisions)
	assert_false(result.end_conversation)

func test_generated_metadata_cannot_end_conversation() -> void:
	var conversation := _conversation()
	_backend.queue_response(CHAT, {"end_conversation": true})
	var result: Dictionary = await conversation.request(_profile(), {}, "Wait.", _decisions)
	assert_false(result.end_conversation)
	_backend.queue_response(CHAT, {"should_end_conversation": {"type": "noul", "noul": 2.0}})
	result = await conversation.request(_profile(), {}, "Bye.", _decisions)
	assert_true(result.is_empty(), "Malformed end judgments must be rejected")

func test_recall_needs_the_retrieval_judgment_and_failed_dialogue_changes_nothing() -> void:
	var conversation := _conversation()
	_backend.queue_response(CHAT, {"recalled_memory_ids": ["legacy:0"]})
	await _start(conversation)
	assert_eq(_backend.calls(CHAT)[0].memories.size(), 1,
		"The provider is offered the candidates and judges whether to recall them")
	assert_eq(conversation.store.snapshot("test_npc").memories[0].recall_count, 0,
		"An unrecalled memory is not reinforced by being offered")
	_backend.queue_response(CHAT, {"recalled_memory_ids": ["legacy:0"], "should_retrieve_memories": 0.95})
	await _start(conversation)
	assert_eq(conversation.store.snapshot("test_npc").memories[0].recall_count, 1)
	var turn: int = conversation.store.turn
	_backend.queue_response(CHAT, {"outcome": "UNAVAILABLE"})
	await _start(conversation)
	assert_true(_result.is_empty())
	assert_eq(conversation.store.turn, turn)
	assert_eq(conversation.store.snapshot("test_npc").memories[0].recall_count, 1)

func test_new_observation_during_the_request_invalidates_the_old_judgment() -> void:
	var conversation := _conversation()
	_backend.set_default(CHAT, FakeService.threat_chat())
	_backend.hold(CHAT)
	_start(conversation)
	conversation.store.record_observation(_profile(), {
		"text": "Den hurt me.", "sense": "touch", "player_involved": true})
	_backend.release(CHAT)
	await _finish()
	assert_true(_completed)
	assert_true(_result.get("interrupted", false))
	assert_eq(_backend.call_count(CHAT), 1)
	assert_eq(conversation.store.turn, 0)
	assert_eq(_trust(conversation), 0.0)

func test_event_during_the_request_does_not_commit_stale_response_or_feelings() -> void:
	var conversation := _conversation()
	_backend.set_default(CHAT, FakeService.threat_chat())
	_backend.hold(CHAT)
	_start(conversation)
	conversation.store.record_event(_profile(), "The shop caught fire.")
	_backend.release(CHAT)
	await _finish()
	assert_true(_result.get("interrupted", false))
	var state: Dictionary = conversation.store.snapshot("test_npc")
	assert_true(state.recent_dialogue.is_empty())
	assert_eq(_trust(conversation), 0.0)
	assert_eq(state.recent_events, ["The shop caught fire."])
	assert_eq(conversation.store.turn, 0)

func test_other_npc_and_diagnostics_do_not_cancel_valid_exchange() -> void:
	var conversation := _conversation()
	_backend.set_default(CHAT, FakeService.threat_chat())
	_backend.hold(CHAT)
	conversation.store.record_observation(_profile(), {
		"text": "A noise.", "sense": "hearing", "player_involved": false,
		"observation_id": "test_npc:noise"})
	_start(conversation)
	var other: NpcProfile = _profile()
	other.npc_id = &"other"
	conversation.store.record_event(other, "A bell rang.")
	conversation.store.annotate_observation("test_npc", "test_npc:noise", {"assessment_ms": 300})
	_backend.release(CHAT)
	await _finish()
	assert_eq(_result.response, "Leave my forge.")
	assert_eq(conversation.store.turn, 1)

func test_reopened_same_npc_cannot_commit_previous_request() -> void:
	var conversation := _conversation()
	_backend.hold(CHAT)
	_start(conversation)
	conversation.cancel()
	assert_true(_completed)
	assert_true(_result.is_empty())
	_start(conversation)
	assert_false(_completed)
	_backend.release(CHAT)
	await _finish()
	assert_eq(_backend.call_count(CHAT), 2)
	assert_eq(conversation.store.turn, 1)
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_eq(conversation.store.turn, 1, "The cancelled request never commits late")
	assert_eq(conversation.store.snapshot("test_npc").recent_dialogue.size(), 2)

func test_source_lost_before_next_frame_cannot_commit_dialogue() -> void:
	var conversation := _conversation()
	_backend.hold(CHAT)
	var source := Node.new()
	var source_ref: WeakRef = weakref(source)
	var guard: Callable = func() -> bool: return source_ref.get_ref() != null
	_start(conversation, "Hello", guard)
	source.free()
	_backend.release(CHAT)
	await _finish()
	assert_true(_completed)
	assert_true(_result.is_empty())
	assert_eq(conversation.store.turn, 0)

func test_exchanges_belong_to_their_session_and_need_one_to_commit() -> void:
	var conversation := NpcConversation.new()
	conversation.persist = false
	assert_true((await conversation.request(_profile(), {}, "Hello", _decisions)).is_empty())
	assert_eq(conversation.store.turn, 0)
	conversation.store.set_world_minute(600.0)
	conversation.session_id = "player:1"
	conversation.session_start = 600.0
	await conversation.request(_profile(), {}, "Hello", _decisions)
	assert_eq(conversation.store.snapshot("test_npc").recent_dialogue[1].session_id, "player:1")
	conversation.store.set_world_minute(630.0)
	conversation.session_id = "player:2"
	conversation.session_start = 630.0
	await conversation.request(_profile(), {}, "Back again", _decisions)
	var calls: Array[Dictionary] = _backend.calls(CHAT)
	var history: Array = calls[calls.size() - 1].recent_dialogue
	assert_eq(history.size(), 2)
	assert_eq(history[0], {"speaker": "player", "text": "Hello"})
	assert_eq(conversation.store.snapshot("test_npc").recent_dialogue[3].session_id, "player:2")

func test_opening_greeting_is_reproducible_for_the_same_session_and_minute() -> void:
	var greetings: Array[String] = []
	for attempt: int in 2:
		var conversation := _conversation()
		await conversation.request(_profile(), {}, "", _decisions)
		greetings.append(_backend.calls(CHAT)[attempt].player.message)
	assert_eq(greetings[0], greetings[1])
