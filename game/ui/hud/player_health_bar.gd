class_name PlayerHealthBar
extends ProgressBar

## NodePath to the player actor whose health this bar displays.
@export var player_path: NodePath

var _player: Node

func _ready() -> void:
	show_percentage = false
	_bind_player()

func _bind_player() -> void:
	_player = get_node_or_null(player_path)
	if _player == null:
		hide()
		return

	show()
	if _player.has_signal("health_changed") and not _player.health_changed.is_connected(_on_health_changed):
		_player.health_changed.connect(_on_health_changed)

	_on_health_changed(int(_player.get("health")), int(_player.get("max_health")))

func _on_health_changed(current_health: int, next_max_health: int) -> void:
	max_value = maxi(next_max_health, 1)
	value = clampi(current_health, 0, int(max_value))
