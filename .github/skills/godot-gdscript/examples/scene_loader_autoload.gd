extends Node

signal scene_changed(path: String)

func change_scene(path: String) -> void:
	if path.is_empty():
		push_error("Scene path cannot be empty.")
		return

	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		push_error("Failed to change scene to %s. Error: %d" % [path, error])
		return

	scene_changed.emit(path)
