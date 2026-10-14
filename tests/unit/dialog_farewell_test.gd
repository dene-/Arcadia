extends "res://tests/test_case.gd"

const Manager = preload("res://game/ui/dialog/dialog_manager.gd")
const FakeService = preload("res://tests/fixtures/npc_fake_decision_service.gd")
const CHAT: String = "dialogue/chat"

class ChatSource extends Node:
	func is_able_to_chat() -> bool:
		return true

var _tree: SceneTree
var _previous_scene: Node
var _scene: Node
var _manager: Node
var _source: ChatSource
var _finished_sources: Array[Node] = []
var _backend: FakeService
var _original_transport: DialogBackendClient
var _transport_swapped: bool = false

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
	if _backend != null:
		_backend.release_all()
		_backend.free()
		_backend = null
	if _transport_swapped:
		_tree.root.get_node("NpcCognition").decisions.transport = _original_transport
		_transport_swapped = false
	_manager.close_dialog()
	_tree.current_scene = _previous_scene
	_scene.free()

func _add(parent: Node, child: Node, node_name: String) -> Node:
	child.name = node_name
	parent.add_child(child)
	return child

func _reply(text: String, ending: bool = false) -> void:
	_manager._apply_dialog_result({"response": text, "end_conversation": ending})

func test_nameplate_uses_the_actual_npc_identity_and_clears_on_close() -> void:
	var npc: BaseNpc = load("res://game/actors/npcs/base_npc.tscn").instantiate()
	_scene.add_child(npc)
	_manager.close_dialog()
	_manager._start_dialog(npc)
	assert_eq(_manager._speaker_name.text, npc.get_npc_profile().profile_name)
	_manager.close_dialog()
	assert_eq(_manager._speaker_name.text, "")

func test_opening_dialog_reveals_a_hidden_ui_layer() -> void:
	_manager.close_dialog()
	var ui: CanvasLayer = _scene.get_node("UI")
	ui.hide()
	_manager._start_dialog(_source)
	assert_true(_manager.is_dialog_open())
	assert_true(ui.visible, "Opening a dialog must reveal its containing canvas layer")
	assert_true(_manager._dialog_panel.visible)
	assert_eq(_manager._dialog_text.text, "...")
	_manager.set_process(false)
	_reply("Hello.")
	_manager.advance_dialog()
	assert_true(_manager._chat_container.visible)

func test_farewell_reveals_then_closes_without_showing_chat() -> void:
	_reply("Hello.")
	_manager.advance_dialog()
	assert_true(_manager._chat_container.visible)
	_reply("See you tomorrow.", true)
	_manager._on_chat_submitted("Wait!")
	assert_eq(_manager._active_text, "See you tomorrow.")
	_manager._process(0.01)
	assert_true(_manager.is_dialog_open())
	assert_true(_manager._typewriter.is_revealing())
	_manager._process(10.0)
	assert_true(_manager.is_dialog_open(), "The final line needs reading time after revealing")
	assert_false(_manager._chat_container.visible)
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

## Routes the real decision service to a scripted fake for the rest of the test.
func _install_fake() -> FakeService:
	var cognition: Node = _tree.root.get_node("NpcCognition")
	_backend = FakeService.new()
	_tree.root.add_child(_backend)
	cognition.decisions.transport = _backend
	return _backend

func _wait_until(done: Callable) -> void:
	for _frame: int in range(300):
		if done.call():
			return
		await _tree.process_frame

## Opens a conversation with the provider offline, so the opening greeting falls back locally.
func _open_resident(npc_id: StringName) -> BaseNpc:
	var cognition: Node = _tree.root.get_node("NpcCognition")
	if not _transport_swapped:
		_original_transport = cognition.decisions.transport
		_transport_swapped = true
	cognition.decisions.transport = null
	var npc: BaseNpc = load("res://game/actors/npcs/base_npc.tscn").instantiate()
	npc.npc_data = npc.npc_data.duplicate()
	npc.npc_data.profile = NpcProfile.new()
	npc.npc_data.profile.npc_id = npc_id
	_scene.add_child(npc)
	_manager.close_dialog()
	_manager._start_dialog(npc)
	_manager.set_process(false)
	var conversation: NpcConversation = _manager._conversation
	conversation.store = NpcMemoryStore.new()
	conversation.persist = false
	return npc

func test_dialogue_retries_with_fresh_evidence_without_committing_stale_reply() -> void:
	var npc: BaseNpc = _open_resident(&"dialogue_retry_test")
	var conversation: NpcConversation = _manager._conversation
	var backend: FakeService = _install_fake()
	backend.set_default(CHAT, FakeService.threat_chat())
	backend.hold(CHAT)
	var received: Array[Dictionary] = []
	var run: Callable = func() -> void:
		received.append(await _manager._resolve_dialog_text_async(npc, "Hello."))
	run.call()
	assert_eq(backend.call_count(CHAT), 1)
	conversation.store.record_event(npc.get_npc_profile(), "Smoke fills the shop.")
	backend.release(CHAT)
	await _wait_until(func() -> bool: return not received.is_empty())
	assert_eq(backend.call_count(CHAT), 2)
	assert_eq(backend.calls(CHAT)[1].context.recent_events, ["Smoke fills the shop."])
	assert_eq(conversation.store.turn, 1, "Only the fresh exchange may commit")
	assert_eq(conversation.store.snapshot("dialogue_retry_test").recent_dialogue.size(), 2)
	assert_eq(received[0].response, "Leave my forge.")

func test_continuing_interruptions_close_dialogue_without_fallback_or_commit() -> void:
	var npc: BaseNpc = _open_resident(&"dialogue_interrupt_test")
	var conversation: NpcConversation = _manager._conversation
	var backend: FakeService = _install_fake()
	backend.set_default(CHAT, FakeService.threat_chat())
	backend.hold(CHAT)
	var received: Array[Dictionary] = []
	var run: Callable = func() -> void:
		received.append(await _manager._resolve_dialog_text_async(npc, "Hello."))
	run.call()
	# The retry is dispatched as the first request settles, so hold it before that happens.
	_tree.root.get_node("NpcCognition").decisions.request_settled.connect(
		func(_entry: Dictionary) -> void: backend.hold(CHAT), CONNECT_ONE_SHOT)
	npc.life_revision += 1
	backend.release(CHAT)
	await _wait_until(func() -> bool: return backend.call_count(CHAT) == 2)
	assert_eq(backend.call_count(CHAT), 2)
	npc.life_revision += 1
	backend.release(CHAT)
	await _wait_until(func() -> bool: return not received.is_empty())
	assert_eq(backend.call_count(CHAT), 2, "Do not keep retrying during ongoing danger")
	assert_false(_manager.is_dialog_open())
	assert_true(received[0].is_empty())
	assert_eq(conversation.store.turn, 0)
	assert_true(conversation.store.snapshot("dialogue_interrupt_test").recent_dialogue.is_empty())
