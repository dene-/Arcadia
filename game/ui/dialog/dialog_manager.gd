extends CanvasLayer

signal dialog_started(source: Node, text: String)
signal dialog_advanced(page_index: int)
signal dialog_finished(source: Node)

const LOADING_DIALOG: String = "..."
const PLACEHOLDER_DIALOG: String = "I cannot talk just now. Try me again in a moment."
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
const FAREWELL_HOLD_SECONDS: float = 1.5
var _dialog_panel: Panel
var _dialog_text: RichTextLabel
var _speaker_name: Label
var _next_page_indicator: Control
var _replies_container: ScrollContainer
var _reply_buttons: Array[Button] = []
var _chat_container: Control
var _chat_line_edit: LineEdit
var _chat_send_button: Button
var _chat_cancel_button: Button
var _conversation: NpcConversation = NpcConversation.new()
var _events: NpcEventProcessor
var _dialog_generation: int = 0
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
var _end_after_response: bool = false
var _farewell_remaining: float = -1.0
var _page_index: int = 0
var _indicator_base_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	call_deferred("_bind_dialog_ui")
	set_process(false)

	_speech_player = DialogVoicePlayer.new()
	add_child(_speech_player)

	var cognition: Node = get_node("/root/NpcCognition")
	_conversation.store = cognition.store
	_conversation.save_callback = cognition.save_game.save_file
	_backend_client = cognition.backend
	_events = cognition.events


func _process(delta: float) -> void:
	if _is_open and (not is_instance_valid(_active_source) or get_tree().current_scene != _bound_scene):
		close_dialog()
		return
	if _is_open and _active_source is BaseActor and _active_source.health <= 0:
		close_dialog()
		return
	if _farewell_remaining >= 0.0:
		_farewell_remaining -= delta
		if _farewell_remaining <= 0.0:
			close_dialog()
			return
	_update_typewriter(delta)

	if _next_page_indicator == null or not _next_page_indicator.visible:
		return

	var phase := Time.get_ticks_msec() / 1000.0 * INDICATOR_BOB_SPEED
	_next_page_indicator.position = (
		_indicator_base_position + Vector2(0.0, sin(phase) * INDICATOR_BOB_DISTANCE)
	).round()

func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel") or _is_escape_key_pressed(event):
		close_dialog()
		get_viewport().set_input_as_handled()

func is_dialog_open() -> bool:
	return _is_open

func interrupt_source(source: Node) -> void:
	if _is_open and _active_source == source:
		close_dialog()

func request_npc_dialog(source: Node) -> void:
	if not is_instance_valid(source):
		return
	if _is_open:
		close_dialog()
	if not _bind_dialog_ui():
		return

	_start_dialog(source)
	var generation: int = _dialog_generation
	dialog_started.emit(source, "")
	await get_tree().process_frame
	if not _is_open or _active_source != source or generation != _dialog_generation:
		return
	if not _bind_dialog_ui():
		close_dialog()
		return

	var backend_result := await _resolve_dialog_text_async(source, "")
	if not _is_open or _active_source != source or generation != _dialog_generation:
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
		if not _end_after_response and (not _active_replies.is_empty() or _able_to_chat):
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

	_dialog_generation += 1
	_conversation.cancel()
	var finished_source: Node = _active_source if is_instance_valid(_active_source) else null
	_active_source = null
	_active_text = ""
	_active_pages.clear()
	_active_replies.clear()
	_able_to_chat = false
	_is_open = false
	_is_waiting_for_backend = false
	_end_after_response = false
	_farewell_remaining = -1.0
	_page_index = 0
	if _dialog_text != null:
		_dialog_text.text = ""
	if _speaker_name != null:
		_speaker_name.text = ""
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
	_speaker_name = current_scene.get_node_or_null(String(DIALOG_PANEL_PATH) + "/SpeakerName") as Label
	_next_page_indicator = current_scene.get_node_or_null(DIALOG_NEXT_PAGE_INDICATOR_PATH) as Control
	_replies_container = current_scene.get_node_or_null(REPLIES_CONTAINER_PATH) as ScrollContainer
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
	_dialog_generation += 1
	_conversation.cancel()
	_active_source = source
	if _speaker_name != null:
		_speaker_name.text = source.get_npc_profile().profile_name if source is BaseNpc \
			and source.get_npc_profile() != null else ""
	_active_text = ""
	_active_pages.clear()
	_active_replies.clear()
	_able_to_chat = _source_is_able_to_chat(source)
	_end_after_response = false
	_farewell_remaining = -1.0
	_page_index = 0
	_is_waiting_for_backend = true
	_typewriter.reset(_dialog_text)
	_dialog_text.text = LOADING_DIALOG
	var dialog_layer: CanvasLayer = _dialog_panel.get_canvas_layer_node()
	if dialog_layer != null:
		dialog_layer.show()
	_dialog_panel.show()
	_is_open = true
	set_process(true)

func _configure_dialog_text() -> void:
	_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_text.scroll_active = false
	_dialog_text.scroll_following = false
	_dialog_text.fit_content = false
	_dialog_text.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING

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

func record_npc_event(profile: NpcProfile, event: String) -> void:
	if profile == null or profile.npc_id.is_empty():
		return
	_conversation.store.record_event(profile, event)
	var error: Error = _conversation.save_callback.call()
	if error != OK:
		push_warning("NPC event could not be saved: %s" % error)

func get_memory_store() -> NpcMemoryStore:
	return _conversation.store

func _resolve_dialog_text_async(source: Node, player_message: String) -> Dictionary:
	if is_instance_valid(source) and source.has_method("get_npc_profile"):
		var profile: NpcProfile = source.call("get_npc_profile")
		if profile != null and not profile.npc_id.is_empty():
			var current: Dictionary = source.call("get_cognitive_context")
			var generation: int = _dialog_generation
			var source_ref: WeakRef = weakref(source)
			var still_current: Callable = func() -> bool:
				return source_ref.get_ref() != null and _is_open and _active_source == source_ref.get_ref() \
					and generation == _dialog_generation and get_tree().current_scene == _bound_scene
			# One retry absorbs an event arriving during inference. Ongoing danger interrupts
			# the conversation instead of displaying stale prose or looping indefinitely.
			for attempt: int in range(2):
				_events.resume(profile, current, source as BaseNpc)
				await _events.wait_for_assessment(String(profile.npc_id))
				if not still_current.call():
					return {}
				current = source.call("get_cognitive_context")
				var npc: BaseNpc = source as BaseNpc
				var revision: int = npc.life_revision if npc != null else 0
				var space: StringName = npc.world_space if npc != null else &""
				var attempt_current: Callable = func() -> bool:
					if not still_current.call():
						return false
					var actor: BaseNpc = source_ref.get_ref() as BaseNpc
					return actor == null or (actor.life_revision == revision and actor.world_space == space)
				var result: Dictionary = await _conversation.request(
					profile, current, player_message, _backend_client, attempt_current)
				if not still_current.call():
					return {}
				if result.get("interrupted", false) or (npc != null
						and (npc.life_revision != revision or npc.world_space != space)):
					if attempt == 1:
						close_dialog()
						return {}
					continue
				if not result.is_empty():
					return result
				break
	if is_instance_valid(source) and source.has_method("get_dialog_text"):
		var source_text: String = str(source.call("get_dialog_text")).strip_edges()
		if not source_text.is_empty():
			return {"response": source_text, "replies": []}
	return {"response": PLACEHOLDER_DIALOG, "replies": []}

func _apply_dialog_result(result: Dictionary) -> void:
	_is_waiting_for_backend = false
	if result.get("surrender", false) == true and is_instance_valid(_active_source) \
		and _active_source.is_in_group(&"town_guards"):
		for player: BasePlayer in get_tree().get_nodes_in_group(&"players"):
			player.surrender()
	_end_after_response = result.get("end_conversation", false) == true
	_farewell_remaining = -1.0
	_active_text = str(result.get("response", ""))
	_active_replies = _get_replies_from_result(result)
	_active_pages = _paginator.paginate(_active_text, _dialog_text)
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
	if _end_after_response:
		if _chat_container != null:
			_chat_container.hide()
		if can_show and _farewell_remaining < 0.0:
			_farewell_remaining = FAREWELL_HOLD_SECONDS
		return

	if can_show and not _able_to_chat and _replies_container != null and not _active_replies.is_empty():
		var visible_reply_count: int = mini(_active_replies.size(), _reply_buttons.size())
		for index in range(visible_reply_count):
			var button := _reply_buttons[index]
			var reply_text := _active_replies[index]
			button.text = reply_text
			button.set_meta("reply_text", reply_text)
			button.show()
		_replies_container.show()
		_replies_container.scroll_vertical = 0

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

	for child in _replies_container.get_node("ReplyList").get_children():
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
	if not _is_open or not is_instance_valid(_active_source) \
		or _is_waiting_for_backend or _end_after_response:
		return
	_clear_reply_ui()
	_page_index = 0
	_active_pages.clear()
	_active_replies.clear()
	_is_waiting_for_backend = true
	_typewriter.reset(_dialog_text)
	_dialog_text.text = LOADING_DIALOG
	_update_next_page_indicator()

	var source := _active_source
	var generation: int = _dialog_generation
	var backend_result := await _resolve_dialog_text_async(source, player_message)
	if not _is_open or _active_source != source or generation != _dialog_generation:
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
