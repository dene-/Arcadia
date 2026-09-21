extends "res://tests/test_case.gd"

const Manager = preload("res://game/ui/dialog/dialog_manager.gd")

class ChatSource extends Node:
	func is_able_to_chat() -> bool:
		return true

var _tree: SceneTree
var _previous_scene: Node
var _scene: Node
var _manager: Node
var _source: ChatSource
var _finished_sources: Array[Node] = []

func before_each() -> void:
	_tree = Engine.get_main_loop() as SceneTree
	_previous_scene = _tree.current_scene
	_scene = Node.new()
	_tree.root.add_child(_scene)
	_tree.current_scene = _scene
	var ui: Node = _add(_scene, CanvasLayer.new(), "UI")
	var container: Node = _add(ui, Control.new(), "Container")
	var column: Node = _add(container, VBoxContainer.new(), "VBoxContainer")
	var panel: Node = _add(column, Panel.new(), "DialogPanel")
	_add(panel, Label.new(), "SpeakerName")
	var text_container: Node = _add(panel, Control.new(), "DialogContainer")
	var text: RichTextLabel = _add(text_container, RichTextLabel.new(), "DialogText")
	text.size = Vector2(206, 33)
	text.theme = load("res://assets/art/ui/theme.tres")
	_add(panel, Control.new(), "NextPageIndicator")
	var replies: Node = _add(column, ScrollContainer.new(), "RepliesContainer")
	var reply_list: Node = _add(replies, VBoxContainer.new(), "ReplyList")
	for index: int in range(3):
		_add(reply_list, Button.new(), "Reply%d" % index)
	var chat: Node = _add(column, HBoxContainer.new(), "ChatContainer")
	_add(chat, LineEdit.new(), "ChatLineEdit")
	_add(chat, Button.new(), "ChatSendButton")
	_add(chat, Button.new(), "ChatCancelButton")
	_source = ChatSource.new()
	_scene.add_child(_source)
	_manager = Manager.new()
	_scene.add_child(_manager)
	_manager._speech_player.free()
	_manager._speech_player = null
	assert_true(_manager._bind_dialog_ui())
	_finished_sources.clear()
	_manager.dialog_finished.connect(func(source: Node) -> void: _finished_sources.append(source))
	_manager._start_dialog(_source)
	_manager.set_process(false)

func after_each() -> void:
	_manager.close_dialog()
	_tree.current_scene = _previous_scene
	_scene.free()

func _add(parent: Node, child: Node, node_name: String) -> Node:
	child.name = node_name
	parent.add_child(child)
	return child

func _reply(text: String, ending: bool = false) -> void:
	_manager._apply_dialog_result({"response": text, "replies": ["Yes", "No", "Bye"],
		"end_conversation": ending})

func test_nameplate_uses_the_actual_npc_identity_and_clears_on_close() -> void:
	var npc: BaseNpc = load("res://game/actors/npcs/base_npc.tscn").instantiate()
	_scene.add_child(npc)
	_manager.close_dialog()
	_manager._start_dialog(npc)
	assert_eq(_manager._speaker_name.text, npc.get_npc_profile().profile_name)
	_manager.close_dialog()
	assert_eq(_manager._speaker_name.text, "")

func test_farewell_reveals_then_closes_without_showing_chat_or_replies() -> void:
	_reply("Hello.")
	_manager.advance_dialog()
	assert_true(_manager._chat_container.visible)
	assert_false(_manager._replies_container.visible)
	_reply("See you tomorrow.", true)
	_manager._on_chat_submitted("Wait!")
	assert_eq(_manager._active_text, "See you tomorrow.")
	_manager._process(0.01)
	assert_true(_manager.is_dialog_open())
	assert_true(_manager._typewriter.is_revealing())
	_manager._process(10.0)
	assert_true(_manager.is_dialog_open(), "The final line needs reading time after revealing")
	assert_false(_manager._chat_container.visible)
	assert_false(_manager._replies_container.visible)
	_manager._process(0.75)
	assert_true(_manager.is_dialog_open())
	_manager._process(0.8)
	assert_false(_manager.is_dialog_open())
	assert_eq(_finished_sources, [_source])
	assert_false(_manager._dialog_panel.visible)

func test_farewell_waits_for_last_page_and_allows_manual_close() -> void:
	_reply("Keep to the road. ".repeat(15), true)
	assert_true(_manager._active_pages.size() > 1)
	_manager.advance_dialog()
	_manager._process(10.0)
	assert_true(_manager.is_dialog_open(), "Do not close before the remaining pages are read")
	assert_true(_manager._next_page_indicator.visible)
	while _manager._has_next_page():
		_manager.advance_dialog()
		_manager.advance_dialog()
	assert_true(_manager.is_dialog_open())
	_manager.advance_dialog()
	assert_false(_manager.is_dialog_open())

func test_closing_and_reopening_cancels_pending_farewell() -> void:
	_reply("Goodbye.", true)
	_manager.advance_dialog()
	_manager.close_dialog()
	_manager._start_dialog(_source)
	_manager.set_process(false)
	_reply("Back already?")
	_manager.advance_dialog()
	_manager._process(10.0)
	assert_true(_manager.is_dialog_open())
	assert_true(_manager._chat_container.visible)
	assert_eq(_finished_sources.size(), 1)

func test_dialogue_retries_with_fresh_evidence_without_committing_stale_reply() -> void:
	var npc: BaseNpc = load("res://game/actors/npcs/base_npc.tscn").instantiate()
	npc.npc_data = npc.npc_data.duplicate()
	npc.npc_data.profile = NpcProfile.new()
	npc.npc_data.profile.npc_id = &"dialogue_retry_test"
	_scene.add_child(npc)
	_manager.close_dialog()
	_manager._start_dialog(npc)
	_manager.set_process(false)
	var conversation: NpcConversation = _manager._conversation
	conversation.store = NpcMemoryStore.new()
	conversation.persist = false
	var previous_backend: DialogBackendClient = _manager._backend_client
	var backend = preload("res://tests/unit/npc_conversation_test.gd").FakeBackend.new()
	_manager._backend_client = backend
	backend.hold_dialogue = true
	var received: Array[Dictionary] = []
	var run: Callable = func() -> void:
		received.append(await _manager._resolve_dialog_text_async(npc, "Hello."))
	run.call()
	assert_eq(backend.dialogue_calls, 1)
	conversation.store.record_event(npc.get_npc_profile(), "Smoke fills the shop.")
	backend.hold_dialogue = false
	backend.dialogue_ready.emit()
	assert_eq(backend.dialogue_calls, 2)
	assert_eq(backend.payload.context.current.recent_events, ["Smoke fills the shop."])
	assert_eq(conversation.store.turn, 1, "Only the fresh exchange may commit")
	assert_eq(conversation.store.snapshot("dialogue_retry_test").recent_dialogue.size(), 2)
	assert_eq(received[0].response, "Leave my forge.")
	_manager._backend_client = previous_backend
	backend.free()

func test_continuing_interruptions_close_dialogue_without_fallback_or_commit() -> void:
	var npc: BaseNpc = load("res://game/actors/npcs/base_npc.tscn").instantiate()
	npc.npc_data = npc.npc_data.duplicate()
	npc.npc_data.profile = NpcProfile.new()
	npc.npc_data.profile.npc_id = &"dialogue_interrupt_test"
	_scene.add_child(npc)
	_manager.close_dialog()
	_manager._start_dialog(npc)
	_manager.set_process(false)
	var conversation: NpcConversation = _manager._conversation
	conversation.store = NpcMemoryStore.new()
	conversation.persist = false
	var previous_backend: DialogBackendClient = _manager._backend_client
	var backend = preload("res://tests/unit/npc_conversation_test.gd").FakeBackend.new()
	_manager._backend_client = backend
	backend.hold_dialogue = true
	var received: Array[Dictionary] = []
	var run: Callable = func() -> void:
		received.append(await _manager._resolve_dialog_text_async(npc, "Hello."))
	run.call()
	npc.life_revision += 1
	backend.dialogue_ready.emit()
	assert_eq(backend.dialogue_calls, 2)
	npc.life_revision += 1
	backend.dialogue_ready.emit()
	assert_eq(backend.dialogue_calls, 2, "Do not keep retrying during ongoing danger")
	assert_false(_manager.is_dialog_open())
	assert_true(received[0].is_empty())
	assert_eq(conversation.store.turn, 0)
	assert_true(conversation.store.snapshot("dialogue_interrupt_test").recent_dialogue.is_empty())
	_manager._backend_client = previous_backend
	backend.free()
