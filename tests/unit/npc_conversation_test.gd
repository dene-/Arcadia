extends "res://tests/test_case.gd"

class FakeBackend extends DialogBackendClient:
	signal decision_ready
	signal dialogue_ready
	var hold_decision: bool = false
	var hold_dialogue: bool = false
	var dialogue_calls: int = 0
	var payload: Dictionary = {}
	var decision_payload: Dictionary = {}
	var policy: Dictionary = {"remember": true, "retrieve": true, "update_belief": false,
		"importance": 0.8, "emotional_intensity": 0.7, "response_mode": "DEFENSIVE",
		"relationship_delta": {"familiarity": 0.01, "trust": -0.08, "respect": 0.0,
			"affection": 0.0, "fear": 0.08, "suspicion": 0.0}}
	var result: Dictionary = {"response": "Leave my forge.", "replies": ["Sorry.", "No.", "Goodbye."],
		"memory_writes": [], "recalled_memory_ids": []}
	func request_decision(request: Dictionary) -> Dictionary:
		decision_payload = request.duplicate(true)
		if hold_decision:
			await decision_ready
		return {"policy": policy, "answers": {}}
	func request_dialog(request: Dictionary) -> Dictionary:
		dialogue_calls += 1
		payload = request
		if hold_dialogue:
			await dialogue_ready
		return result

var _completed: bool = false
var _result: Dictionary = {}

func _profile() -> NpcProfile:
	var profile := NpcProfile.new()
	profile.npc_id = &"test_npc"
	profile.memories = ["The player brought a dagger."]
	return profile

func _start(conversation: NpcConversation, backend: FakeBackend) -> void:
	_completed = false
	_result = await conversation.request(_profile(), {}, "Where is the dagger?", backend)
	_completed = true

func test_decision_preview_precedes_dialogue_but_commit_waits_for_success() -> void:
	var conversation := NpcConversation.new()
	conversation.persist = false
	var backend := FakeBackend.new()
	backend.hold_dialogue = true
	_start(conversation, backend)
	assert_false(_completed)
	assert_eq(conversation.store.snapshot("test_npc").relationship.trust, 0.0)
	assert_eq(backend.payload.context.relationship.trust, -0.08)
	assert_eq(backend.payload.context.memories.size(), 1)
	assert_false(backend.payload.npc.profile.has("memories"))
	backend.dialogue_ready.emit()
	assert_true(_completed)
	assert_eq(conversation.store.snapshot("test_npc").relationship.trust, -0.08)
	assert_eq(conversation.store.snapshot("test_npc").recent_dialogue.size(), 2)
	backend.free()

func test_opening_greeting_reaches_both_models_and_history_without_replacing_player_text() -> void:
	var conversation := NpcConversation.new()
	conversation.persist = false
	var backend := FakeBackend.new()
	await conversation.request(_profile(), {}, "", backend)
	var greeting: String = backend.decision_payload.player.message
	assert_true(NpcConversation.OPENING_GREETINGS.has(greeting))
	assert_eq(backend.payload.player.message, greeting)
	assert_eq(conversation.store.snapshot("test_npc").recent_dialogue[0].text, greeting)
	await conversation.request(_profile(), {}, "Can you mend this?", backend)
	assert_eq(backend.decision_payload.player.message, "Can you mend this?")
	assert_eq(backend.payload.player.message, "Can you mend this?")
	assert_eq(conversation.store.snapshot("test_npc").recent_dialogue[2].text, "Can you mend this?")
	backend.free()

func test_cancel_during_decision_never_generates_dialogue_or_commits() -> void:
	var conversation := NpcConversation.new()
	conversation.persist = false
	var backend := FakeBackend.new()
	backend.hold_decision = true
	_start(conversation, backend)
	conversation.cancel()
	backend.decision_ready.emit()
	assert_true(_completed)
	assert_true(_result.is_empty())
	assert_eq(backend.dialogue_calls, 0)
	assert_eq(conversation.store.turn, 0)
	backend.free()

func test_cancel_during_dialogue_drops_late_response() -> void:
	var conversation := NpcConversation.new()
	conversation.persist = false
	var backend := FakeBackend.new()
	backend.hold_dialogue = true
	_start(conversation, backend)
	conversation.cancel()
	backend.dialogue_ready.emit()
	assert_true(_result.is_empty())
	assert_eq(conversation.store.turn, 0)
	assert_eq(conversation.store.snapshot("test_npc").recent_dialogue.size(), 0)
	backend.free()

func test_retrieval_gate_and_failed_dialogue_do_not_change_memory() -> void:
	var conversation := NpcConversation.new()
	conversation.persist = false
	var backend := FakeBackend.new()
	backend.policy.retrieve = false
	backend.result = {}
	await _start(conversation, backend)
	assert_true(backend.payload.context.memories.is_empty())
	assert_true(_result.is_empty())
	assert_eq(conversation.store.turn, 0)
	backend.free()

func test_reopened_same_npc_cannot_commit_previous_request() -> void:
	var conversation := NpcConversation.new()
	conversation.persist = false
	var old_backend := FakeBackend.new()
	old_backend.hold_dialogue = true
	_start(conversation, old_backend)
	conversation.cancel()
	var new_backend := FakeBackend.new()
	await _start(conversation, new_backend)
	assert_eq(conversation.store.turn, 1)
	old_backend.dialogue_ready.emit()
	assert_eq(conversation.store.turn, 1)
	old_backend.free()
	new_backend.free()

func _start_guarded(conversation: NpcConversation, backend: FakeBackend, guard: Callable) -> void:
	_completed = false
	_result = await conversation.request(_profile(), {}, "Hello", backend, guard)
	_completed = true

func test_source_lost_before_next_frame_cannot_commit_dialogue() -> void:
	var conversation := NpcConversation.new()
	conversation.persist = false
	var backend := FakeBackend.new()
	backend.hold_dialogue = true
	var source := Node.new()
	var source_ref: WeakRef = weakref(source)
	var guard: Callable = func() -> bool: return source_ref.get_ref() != null
	_start_guarded(conversation, backend, guard)
	source.free()
	backend.dialogue_ready.emit()
	assert_true(_completed)
	assert_true(_result.is_empty())
	assert_eq(conversation.store.turn, 0)
	backend.free()
