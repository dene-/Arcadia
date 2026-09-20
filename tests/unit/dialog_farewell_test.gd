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
	var text_container: Node = _add(panel, Control.new(), "DialogContainer")
	_add(text_container, RichTextLabel.new(), "DialogText")
	_add(panel, Control.new(), "NextPageIndicator")
	var replies: Node = _add(column, HBoxContainer.new(), "RepliesContainer")
	for index: int in range(3):
		_add(replies, Button.new(), "Reply%d" % index)
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
