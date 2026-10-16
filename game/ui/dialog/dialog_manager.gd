extends CanvasLayer

signal dialog_started(source: Node, text: String)
signal dialog_advanced(page_index: int)
signal dialog_finished(source: Node)

const LOADING_DIALOG: String = "..."
const PLACEHOLDER_DIALOG: String = "I cannot talk just now. Try me again in a moment."
const DIALOG_PANEL_PATH: NodePath = ^"UI/Container/VBoxContainer/DialogPanel"
const DIALOG_TEXT_PATH: NodePath = ^"UI/Container/VBoxContainer/DialogPanel/DialogContainer/DialogText"
const DIALOG_NEXT_PAGE_INDICATOR_PATH: NodePath = ^"UI/Container/VBoxContainer/DialogPanel/NextPageIndicator"
const CHAT_CONTAINER_PATH: NodePath = ^"UI/Container/VBoxContainer/ChatContainer"
const CHAT_LINE_EDIT_PATH: NodePath = ^"UI/Container/VBoxContainer/ChatContainer/ChatLineEdit"
const CHAT_SEND_BUTTON_PATH: NodePath = ^"UI/Container/VBoxContainer/ChatContainer/ChatSendButton"
const CHAT_CANCEL_BUTTON_PATH: NodePath = ^"UI/Container/VBoxContainer/ChatContainer/ChatCancelButton"
const INDICATOR_BOB_DISTANCE: float = 2.0
const INDICATOR_BOB_SPEED: float = 4.0
const INDICATOR_RIGHT_MARGIN: float = 6.0
const INDICATOR_BOTTOM_MARGIN: float = 7.0
const FAREWELL_HOLD_SECONDS: float = 1.5
## Short lines a resident on an urgent duty uses to turn the player away.
const REFUSAL_LINES: Array[String] = ["Not now!", "Later. I have to go.", "Sorry, I can't stop.",
	"Not now, please."]
var _dialog_panel: Panel
var _dialog_text: RichTextLabel
var _speaker_name: Label
var _next_page_indicator: Control
var _chat_container: Control
var _chat_line_edit: LineEdit
var _chat_send_button: Button
var _chat_cancel_button: Button
var _conversation: NpcConversation = NpcConversation.new()
var _events: NpcEventProcessor
var _dialog_generation: int = 0
var _decisions: NpcDecisionService
var _speech_player: DialogVoicePlayer
var _paginator: DialogPaginator = DialogPaginator.new()
var _typewriter: DialogTypewriter = DialogTypewriter.new()
var _bound_scene: Node
# The player session hosted by the active resident's brain (null for residents without one).
var _session_brain: NpcBrain
var _session_id: String = ""
var _npc_seed: int = 0

var _active_source: Node = null
var _active_text: String = ""
var _active_pages: Array[String] = []
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
	_conversation.saves = cognition.saves
	_decisions = cognition.decisions
	_events = cognition.events
	_npc_seed = cognition.save_game.get_npc_seed()


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

	if not _start_dialog(source):
		return
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
		_update_chat_ui()
		return

	if not _has_next_page():
		if not _end_after_response and _able_to_chat:
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
	_end_player_session()
	var finished_source: Node = _active_source if is_instance_valid(_active_source) else null
	_active_source = null
	_active_text = ""
	_active_pages.clear()
	_able_to_chat = false
	_is_open = false
	_is_waiting_for_backend = false
	_end_after_response = false
	_farewell_remaining = -1.0
	_page_index = 0
	if _dialog_text != null:
		_dialog_text.text = ""
	_set_speaker_name("")
	_typewriter.reset(_dialog_text)
	if _dialog_panel != null:
		_dialog_panel.hide()
	_clear_chat_ui()
	_update_next_page_indicator()
	set_process(false)
	dialog_finished.emit(finished_source)

func _bind_dialog_ui() -> bool:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return false

	_bound_scene = current_scene
	_dialog_panel = current_scene.get_node_or_null(DIALOG_PANEL_PATH) as Panel
	_dialog_text = current_scene.get_node_or_null(DIALOG_TEXT_PATH) as RichTextLabel
	_speaker_name = current_scene.get_node_or_null(String(DIALOG_PANEL_PATH) + "/SpeakerName") as Label
	_next_page_indicator = current_scene.get_node_or_null(DIALOG_NEXT_PAGE_INDICATOR_PATH) as Control
	_chat_container = current_scene.get_node_or_null(CHAT_CONTAINER_PATH) as Control
	_chat_line_edit = current_scene.get_node_or_null(CHAT_LINE_EDIT_PATH) as LineEdit
	_chat_send_button = current_scene.get_node_or_null(CHAT_SEND_BUTTON_PATH) as Button
	_chat_cancel_button = current_scene.get_node_or_null(CHAT_CANCEL_BUTTON_PATH) as Button
	if _dialog_panel == null or _dialog_text == null or _next_page_indicator == null:
		return false

	_configure_dialog_text()
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
		_clear_chat_ui()
	_update_next_page_indicator()
	return true

func _has_next_page() -> bool:
	return _page_index + 1 < _active_pages.size()

# Returns false when the resident's brain refuses the player session; the resident then turns
# the player away with a short line and no dialog opens.
func _start_dialog(source: Node) -> bool:
	_dialog_generation += 1
	_conversation.cancel()
	if not _begin_player_session(source):
		_refuse(source)
		return false
	_conversation.session_id = "player:%d" % _dialog_generation
	_conversation.session_start = _conversation.store.world_minute
	_active_source = source
	_set_speaker_name(source.get_npc_profile().profile_name if source is BaseNpc \
		and source.get_npc_profile() != null else "")
	_active_text = ""
	_active_pages.clear()
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
	return true

# The player's session wins over a resident's own conversation only when the resident is
# available; urgent duties refuse it.
func _begin_player_session(source: Node) -> bool:
	var brain: NpcBrain = NpcBrain.of(source)
	if brain == null:
		return true
	if not brain.accepts_conversation():
		return false
	var owner_now: String = brain.controller.claim_owner(NpcBrain.CONVERSATION_CLAIM)
	if not owner_now.is_empty():
		brain.interrupt(NpcTask.Interrupt.CONVERSATION)
	var session_id: String = "player:%d" % _dialog_generation
	if not brain.request_conversation(session_id):
		return false
	var task := NpcSocialTask.create(session_id, "player", "partner", brain.get_tuning())
	if not brain.request_task(task):
		brain.finish_conversation(session_id)
		return false
	# The player is already beside the resident: the session starts in conversation.
	task.converse()
	_session_brain = brain
	_session_id = session_id
	if not brain.task_finished.is_connected(_on_session_task_finished):
		brain.task_finished.connect(_on_session_task_finished.bind(brain))
	if not brain.controller.claim_revoked.is_connected(_on_session_claim_revoked):
		brain.controller.claim_revoked.connect(_on_session_claim_revoked.bind(brain))
	return true

# Owner-checked and idempotent; a claim or task already taken by another owner is untouched.
func _end_player_session() -> void:
	var brain: NpcBrain = _session_brain
	var session_id: String = _session_id
	_session_brain = null
	_session_id = ""
	if session_id.is_empty() or not is_instance_valid(brain):
		return
	brain.end_task(NpcSocialTask.owner_for(session_id), &"session_ended")
	brain.finish_conversation(session_id)

func _on_session_task_finished(task_id: String, _status: String, _reason: StringName,
		brain: NpcBrain) -> void:
	if brain == _session_brain and task_id == NpcSocialTask.owner_for(_session_id):
		interrupt_source(_active_source)

func _on_session_claim_revoked(_claim: StringName, old_owner: String, brain: NpcBrain) -> void:
	if brain == _session_brain and old_owner == NpcSocialTask.owner_for(_session_id):
		interrupt_source(_active_source)

func _refuse(source: Node) -> void:
	var npc: BaseNpc = source as BaseNpc
	if npc == null or npc.get_npc_profile() == null:
		return
	var random: RandomNumberGenerator = NpcRoutinePlan.random_for(_npc_seed,
		"%s:refusal:%d" % [npc.get_npc_profile().npc_id, _dialog_generation])
	npc.show_spoken_reaction(REFUSAL_LINES[random.randi_range(0, REFUSAL_LINES.size() - 1)])

# The name tag sizes itself to the name and is hidden for anonymous speakers.
func _set_speaker_name(speaker_name: String) -> void:
	if _speaker_name == null:
		return
	_speaker_name.text = speaker_name
	_speaker_name.visible = not speaker_name.is_empty()
	_speaker_name.reset_size()

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

	_clear_chat_ui()
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
		_update_chat_ui()

func _play_speech_sound_for_character(character: String, character_index: int) -> void:
	if _speech_player == null:
		return
	_speech_player.play_character(character, character_index)

func record_npc_event(profile: NpcProfile, event: String) -> void:
	if profile == null or profile.npc_id.is_empty():
		return
	_conversation.store.record_event(profile, event)
	_conversation.saves.request(&"npc_event")

func get_memory_store() -> NpcMemoryStore:
	return _conversation.store

func _resolve_dialog_text_async(source: Node, player_message: String) -> Dictionary:
	if is_instance_valid(source) and source.has_method("get_npc_profile"):
		var profile: NpcProfile = source.call("get_npc_profile")
		if profile != null and not profile.npc_id.is_empty():
			var participants: Array[String] = ["player"]
			var current: Dictionary = source.call("get_cognitive_context", NpcCognitiveContext.DIALOGUE, participants)
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
				current = source.call("get_cognitive_context", NpcCognitiveContext.DIALOGUE, participants)
				var npc: BaseNpc = source as BaseNpc
				var revision: int = npc.life_revision if npc != null else 0
				var space: StringName = npc.world_space if npc != null else &""
				var attempt_current: Callable = func() -> bool:
					if not still_current.call():
						return false
					var actor: BaseNpc = source_ref.get_ref() as BaseNpc
					return actor == null or (actor.life_revision == revision and actor.world_space == space)
				var result: Dictionary = await _conversation.request(
					profile, current, player_message, _decisions, attempt_current)
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
			return {"response": source_text}
	return {"response": PLACEHOLDER_DIALOG}

func _apply_dialog_result(result: Dictionary) -> void:
	_is_waiting_for_backend = false
	if result.get("surrender", false) == true and is_instance_valid(_active_source) \
		and _active_source.is_in_group(&"town_guards"):
		for player: BasePlayer in get_tree().get_nodes_in_group(&"players"):
			player.surrender()
	_end_after_response = result.get("end_conversation", false) == true
	_farewell_remaining = -1.0
	_active_text = str(result.get("response", ""))
	_active_pages = _paginator.paginate(_active_text, _dialog_text)
	if _active_pages.is_empty():
		_active_pages.append(_active_text)
	_show_current_page()

func _update_chat_ui() -> void:
	var on_last_page := not _has_next_page()
	var can_show := _is_open and not _is_waiting_for_backend and not _typewriter.is_revealing() and on_last_page
	if _end_after_response:
		if _chat_container != null:
			_chat_container.hide()
		if can_show and _farewell_remaining < 0.0:
			_farewell_remaining = FAREWELL_HOLD_SECONDS
		return

	if can_show and _able_to_chat and _chat_container != null:
		_chat_container.show()
		if _chat_line_edit != null:
			_chat_line_edit.grab_focus()
	elif _chat_container != null:
		_chat_container.hide()

func _clear_chat_ui() -> void:
	if _chat_container != null:
		_chat_container.hide()
	if _chat_line_edit != null:
		_chat_line_edit.text = ""
		_chat_line_edit.release_focus()

func _send_player_message(player_message: String) -> void:
	if not _is_open or not is_instance_valid(_active_source) \
		or _is_waiting_for_backend or _end_after_response:
		return
	_clear_chat_ui()
	_page_index = 0
	_active_pages.clear()
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

func _on_chat_submitted(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	if _chat_line_edit != null:
		_chat_line_edit.text = ""
	_send_player_message(trimmed)

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
