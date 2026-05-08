extends CanvasLayer

signal dialog_started(source: Node, text: String)
signal dialog_advanced(page_index: int)
signal dialog_finished(source: Node)

const LOADING_DIALOG: String = "..."
const PLACEHOLDER_DIALOG: String = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat."
const DIALOG_PANEL_PATH: NodePath = ^"UI/Container/VBoxContainer/DialogPanel"
const DIALOG_TEXT_PATH: NodePath = ^"UI/Container/VBoxContainer/DialogPanel/DialogContainer/DialogText"
const DIALOG_NEXT_PAGE_INDICATOR_PATH: NodePath = ^"UI/Container/VBoxContainer/DialogPanel/NextPageIndicator"
const REPLIES_CONTAINER_PATH: NodePath = ^"UI/Container/VBoxContainer/RepliesContainer"
const CHAT_CONTAINER_PATH: NodePath = ^"UI/Container/VBoxContainer/ChatContainer"
const CHAT_LINE_EDIT_PATH: NodePath = ^"UI/Container/VBoxContainer/ChatContainer/ChatLineEdit"
const CHAT_SEND_BUTTON_PATH: NodePath = ^"UI/Container/VBoxContainer/ChatContainer/ChatSendButton"
const CHAT_CANCEL_BUTTON_PATH: NodePath = ^"UI/Container/VBoxContainer/ChatContainer/ChatCancelButton"
const INDICATOR_BOB_DISTANCE: float = 2.0
const INDICATOR_BOB_SPEED: float = 4.0
const INDICATOR_RIGHT_MARGIN: float = 5.0
const INDICATOR_BOTTOM_MARGIN: float = 5.0
var _dialog_panel: Panel
var _dialog_text: RichTextLabel
var _next_page_indicator: Control
var _replies_container: Control
var _reply_buttons: Array[Button] = []
var _chat_container: Control
var _chat_line_edit: LineEdit
var _chat_send_button: Button
var _chat_cancel_button: Button
var _backend_client: DialogBackendClient
var _speech_player: DialogVoicePlayer
var _paginator: DialogPaginator = DialogPaginator.new()
var _typewriter: DialogTypewriter = DialogTypewriter.new()
var _bound_scene: Node

var _active_source: Node = null
var _active_text: String = ""
var _active_pages: Array[String] = []
var _active_replies: Array[String] = []
var _able_to_chat: bool = false
var _is_open: bool = false
var _is_waiting_for_backend: bool = false
var _page_index: int = 0
var _indicator_base_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	call_deferred("_bind_dialog_ui")
	set_process(false)

	_speech_player = DialogVoicePlayer.new()
	add_child(_speech_player)

	_backend_client = DialogBackendClient.new()
	add_child(_backend_client)


func _process(delta: float) -> void:
	_update_typewriter(delta)

	if _next_page_indicator == null or not _next_page_indicator.visible:
		return

	var phase := Time.get_ticks_msec() / 1000.0 * INDICATOR_BOB_SPEED
	_next_page_indicator.position = _indicator_base_position + Vector2(0.0, sin(phase) * INDICATOR_BOB_DISTANCE)

func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel") or _is_escape_key_pressed(event):
		close_dialog()
		get_viewport().set_input_as_handled()

func is_dialog_open() -> bool:
	return _is_open

func request_npc_dialog(source: Node) -> void:
	if not _bind_dialog_ui():
		return

	_start_dialog(source)
	dialog_started.emit(source, "")
	await get_tree().process_frame
	if not _is_open or _active_source != source:
		return
	if not _bind_dialog_ui():
		close_dialog()
		return

	var backend_result := await _resolve_dialog_text_async(source, "")
	if not _is_open or _active_source != source:
		return
	_apply_dialog_result(backend_result)

func advance_dialog() -> void:
	if not _is_open:
		return
	if not _bind_dialog_ui():
		close_dialog()
		return
	if _is_waiting_for_backend:
		return
	if _typewriter.is_revealing():
		_typewriter.reveal_immediately(_dialog_text)
		_update_next_page_indicator()
		_update_reply_ui()
		return

	if not _has_next_page():
		if not _active_replies.is_empty() or _able_to_chat:
			return
		close_dialog()
		return

	_page_index += 1
	_show_current_page()
	dialog_advanced.emit(_page_index)

func close_dialog() -> void:
	if not _is_open:
		return
	_bind_dialog_ui()

	var finished_source := _active_source
	_active_source = null
	_active_text = ""
	_active_pages.clear()
	_active_replies.clear()
	_able_to_chat = false
	_is_open = false
	_is_waiting_for_backend = false
	_page_index = 0
	if _dialog_text != null:
		_dialog_text.text = ""
	_typewriter.reset(_dialog_text)
	if _dialog_panel != null:
		_dialog_panel.hide()
	_clear_reply_ui()
	_update_next_page_indicator()
	set_process(false)
	dialog_finished.emit(finished_source)

func _bind_dialog_ui() -> bool:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return false

	if current_scene != _bound_scene:
		_bound_scene = current_scene
		_reply_buttons.clear()

	_dialog_panel = current_scene.get_node_or_null(DIALOG_PANEL_PATH) as Panel
	_dialog_text = current_scene.get_node_or_null(DIALOG_TEXT_PATH) as RichTextLabel
	_next_page_indicator = current_scene.get_node_or_null(DIALOG_NEXT_PAGE_INDICATOR_PATH) as Control
	_replies_container = current_scene.get_node_or_null(REPLIES_CONTAINER_PATH) as Control
	_chat_container = current_scene.get_node_or_null(CHAT_CONTAINER_PATH) as Control
	_chat_line_edit = current_scene.get_node_or_null(CHAT_LINE_EDIT_PATH) as LineEdit
	_chat_send_button = current_scene.get_node_or_null(CHAT_SEND_BUTTON_PATH) as Button
	_chat_cancel_button = current_scene.get_node_or_null(CHAT_CANCEL_BUTTON_PATH) as Button
	if _dialog_panel == null or _dialog_text == null or _next_page_indicator == null:
		return false

	_configure_dialog_text()
	_bind_reply_buttons()
	if _chat_line_edit != null:
		if not _chat_line_edit.text_submitted.is_connected(_on_chat_submitted):
			_chat_line_edit.text_submitted.connect(_on_chat_submitted)
	if _chat_send_button != null:
		if not _chat_send_button.pressed.is_connected(_on_chat_send_pressed):
			_chat_send_button.pressed.connect(_on_chat_send_pressed)
	if _chat_cancel_button != null:
		if not _chat_cancel_button.pressed.is_connected(_on_chat_cancel_pressed):
			_chat_cancel_button.pressed.connect(_on_chat_cancel_pressed)
	if _is_open:
		_dialog_panel.show()
	else:
		_dialog_panel.hide()
		_clear_reply_ui()
	_update_next_page_indicator()
	return true

func _has_next_page() -> bool:
	return _page_index + 1 < _active_pages.size()

func _start_dialog(source: Node) -> void:
	_active_source = source
	_active_text = ""
	_active_pages.clear()
	_active_replies.clear()
	_able_to_chat = _source_is_able_to_chat(source)
	_page_index = 0
	_is_waiting_for_backend = true
	_dialog_text.text = LOADING_DIALOG
	_dialog_panel.show()
	_is_open = true
	set_process(true)

func _configure_dialog_text() -> void:
	_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_text.scroll_active = false
	_dialog_text.scroll_following = false
	_dialog_text.fit_content = false
	_dialog_text.visible_characters_behavior = TextServer.VC_CHARS_BEFORE_SHAPING

func _source_is_able_to_chat(source: Node) -> bool:
	return source != null and source.has_method("is_able_to_chat") and (source.call("is_able_to_chat") as bool)

func _update_next_page_indicator() -> void:
	if _dialog_panel == null or _next_page_indicator == null:
		return

	_indicator_base_position = Vector2(
		_dialog_panel.size.x - _next_page_indicator.size.x - INDICATOR_RIGHT_MARGIN,
		_dialog_panel.size.y - _next_page_indicator.size.y - INDICATOR_BOTTOM_MARGIN
	)

	var show_indicator: bool = _is_open and not _is_waiting_for_backend and not _typewriter.is_revealing() and _has_next_page()
	_next_page_indicator.visible = show_indicator
	_next_page_indicator.position = _indicator_base_position

func _show_current_page() -> void:
	if _dialog_text == null or _page_index >= _active_pages.size():
		return

	_clear_reply_ui()
	_typewriter.begin(_dialog_text, _active_pages[_page_index])
	_update_next_page_indicator()
	if _speech_player != null:
		_speech_player.ensure_started()

func _update_typewriter(delta: float) -> void:
	if not _is_open or _dialog_text == null or _page_index >= _active_pages.size():
		return

	var was_revealing: bool = _typewriter.is_revealing()
	_typewriter.update(_dialog_text, delta, _play_speech_sound_for_character)
	if was_revealing and not _typewriter.is_revealing():
		_update_next_page_indicator()
		_update_reply_ui()

func _play_speech_sound_for_character(character: String, character_index: int) -> void:
	if _speech_player == null:
		return
	_speech_player.play_character(character, character_index)

func _resolve_dialog_text_async(source: Node, player_message: String) -> Dictionary:
	if source != null and source.has_method("get_backend_profile") and _backend_client != null:
		var backend_profile: Dictionary = source.call("get_backend_profile") as Dictionary
		if backend_profile is Dictionary and not backend_profile.is_empty():
			var result: Dictionary = await _backend_client.request_dialog(backend_profile, player_message)
			var response: String = result.get("response", "")
			if not response.is_empty():
				return {
					"response": response.strip_edges().replace("\r\n", "\n"),
					"replies": result.get("replies", []),
				}

	if source != null and source.has_method("get_dialog_text"):
		var source_text := str(source.call("get_dialog_text")).strip_edges().replace("\r\n", "\n")
		if not source_text.is_empty():
			return {"response": source_text, "replies": []}

	return {"response": PLACEHOLDER_DIALOG, "replies": []}

func _apply_dialog_result(result: Dictionary) -> void:
	_is_waiting_for_backend = false
	_active_text = str(result.get("response", ""))
	_active_replies = _get_replies_from_result(result)
	_active_pages = _paginator.paginate(_active_text)
	if _active_pages.is_empty():
		_active_pages.append(_active_text)
	_show_current_page()

func _get_replies_from_result(result: Dictionary) -> Array[String]:
	var replies: Array[String] = []
	var raw: Array = result.get("replies", [])
	for item in raw:
		if item is String:
			replies.append(item as String)
	return replies

func _update_reply_ui() -> void:
	_clear_reply_buttons()

	var on_last_page := not _has_next_page()
	var can_show := _is_open and not _is_waiting_for_backend and not _typewriter.is_revealing() and on_last_page

	if can_show and not _able_to_chat and _replies_container != null and not _active_replies.is_empty():
		var visible_reply_count: int = mini(_active_replies.size(), _reply_buttons.size())
		for index in range(visible_reply_count):
			var button := _reply_buttons[index]
			var reply_text := _active_replies[index]
			button.text = reply_text
			button.set_meta("reply_text", reply_text)
			button.show()
		_replies_container.show()

	if can_show and _able_to_chat and _chat_container != null:
		_chat_container.show()
		if _chat_line_edit != null:
			_chat_line_edit.grab_focus()
	elif _chat_container != null:
		_chat_container.hide()

func _clear_reply_buttons() -> void:
	if _replies_container == null:
		return
	for button: Button in _reply_buttons:
		button.hide()
		if button.has_meta("reply_text"):
			button.remove_meta("reply_text")
	_replies_container.hide()

func _clear_reply_ui() -> void:
	_clear_reply_buttons()
	if _chat_container != null:
		_chat_container.hide()
	if _chat_line_edit != null:
		_chat_line_edit.text = ""
		_chat_line_edit.release_focus()

func _bind_reply_buttons() -> void:
	_reply_buttons.clear()
	if _replies_container == null:
		return

	for child in _replies_container.get_children():
		var button := child as Button
		if button == null:
			continue

		var button_index := _reply_buttons.size()
		_reply_buttons.append(button)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if not button.pressed.is_connected(_on_reply_button_pressed.bind(button_index)):
			button.pressed.connect(_on_reply_button_pressed.bind(button_index))

func _send_player_reply(player_message: String) -> void:
	if not _is_open or _active_source == null:
		return
	_clear_reply_ui()
	_page_index = 0
	_active_pages.clear()
	_active_replies.clear()
	_is_waiting_for_backend = true
	_dialog_text.text = LOADING_DIALOG
	_update_next_page_indicator()

	var source := _active_source
	var backend_result := await _resolve_dialog_text_async(source, player_message)
	if not _is_open or _active_source != source:
		return
	_apply_dialog_result(backend_result)

func _on_reply_selected(reply_text: String) -> void:
	if _active_replies.is_empty():
		return
	if reply_text == _active_replies.back():
		close_dialog()
		return
	_send_player_reply(reply_text)

func _on_reply_button_pressed(button_index: int) -> void:
	if button_index < 0 or button_index >= _reply_buttons.size():
		return

	var reply_text := str(_reply_buttons[button_index].get_meta("reply_text", ""))
	if reply_text.is_empty():
		return

	_on_reply_selected(reply_text)

func _on_chat_submitted(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	if _chat_line_edit != null:
		_chat_line_edit.text = ""
	_send_player_reply(trimmed)

func _on_chat_send_pressed() -> void:
	if _chat_line_edit != null:
		_on_chat_submitted(_chat_line_edit.text)

func _on_chat_cancel_pressed() -> void:
	close_dialog()

func _is_escape_key_pressed(event: InputEvent) -> bool:
	var key_event := event as InputEventKey
	if key_event == null:
		return false
	return key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE
