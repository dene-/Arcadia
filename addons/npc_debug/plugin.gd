@tool
extends EditorPlugin

var _button: Button
var _confirmation: ConfirmationDialog
var _keep_map: CheckBox
var _message: AcceptDialog

func _enter_tree() -> void:
	_button = Button.new()
	_button.text = "Reset NPCs"
	_button.tooltip_text = "Wipe saved NPC history, revive everyone and reroll town life. Stop the game first."
	_button.pressed.connect(_request_reset)
	add_control_to_container(CONTAINER_TOOLBAR, _button)
	_confirmation = ConfirmationDialog.new()
	_confirmation.title = "Reset all NPCs?"
	_confirmation.ok_button_text = "Reset NPCs"
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 620
	_confirmation.add_child(content)
	var description := Label.new()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.text = "Clear learned memories, deaths, bodies, rumors and guard reports.\n" \
		+ "Generate fresh personalities, relationships and routines on next play.\n" \
		+ "Town time and economy restart too. A backup of the current save is kept.\n" \
		+ "Stop any separately launched copies of the game before resetting."
	content.add_child(description)
	_keep_map = CheckBox.new()
	_keep_map.text = "Keep current map, resident identities and families"
	_keep_map.button_pressed = true
	content.add_child(_keep_map)
	_confirmation.confirmed.connect(_reset_npcs)
	add_child(_confirmation)
	_message = AcceptDialog.new()
	add_child(_message)

func _exit_tree() -> void:
	remove_control_from_container(CONTAINER_TOOLBAR, _button)
	_button.queue_free()
	_confirmation.queue_free()
	_message.queue_free()

func _request_reset() -> void:
	if _game_is_running():
		return
	_confirmation.popup_centered()

func _game_is_running() -> bool:
	if not EditorInterface.is_playing_scene():
		return false
	_show_message("Stop the game first", "Press Stop (F8), then click Reset NPCs again.")
	return true

func _reset_npcs() -> void:
	if _game_is_running():
		return
	# Run the existing reset command outside the editor: save classes are runtime scripts.
	var arguments := PackedStringArray(["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "--script", "res://tools/reset_npc_world.gd",
		"--", "--confirm", "--reroll-npcs"])
	if _keep_map.button_pressed:
		arguments.append("--keep-region")
	var output: Array = []
	var exit_code: int = OS.execute(OS.get_executable_path(), arguments, output, true)
	if exit_code != 0:
		_show_message("NPC reset failed", "Reset exited with code %d.\n%s" % [
			exit_code, "\n".join(output)])
		return
	_show_message("NPC reset complete", "Press Play to start with everyone alive and fresh NPC lives.\n" \
		+ "Previous save backed up beside:\n" \
		+ ProjectSettings.globalize_path("user://npc_world.json"))

func _show_message(title: String, message: String) -> void:
	_message.title = title
	_message.dialog_text = message
	_message.popup_centered()
