class_name EnemyHealthBar
extends Node2D

## Width of the enemy health bar in world pixels.
@export_range(4.0, 32.0, 1.0) var bar_width: float = 12.0
## Shared palette for world-space health indicators.
@export var theme: Theme = preload("res://assets/art/ui/theme.tres")

@onready var background: ColorRect = $Background
@onready var fill: ColorRect = $Fill

var _owner_actor: Node

func _ready() -> void:
	_owner_actor = get_parent()
	_configure_rects()
	hide()

	if _owner_actor != null and _owner_actor.has_signal("health_changed"):
		_owner_actor.health_changed.connect(_on_health_changed)
		_on_health_changed(int(_owner_actor.get("health")), int(_owner_actor.get("max_health")))

func _on_health_changed(current_health: int, max_health: int) -> void:
	var safe_max_health := maxi(max_health, 1)
	var health_ratio := clampf(float(current_health) / float(safe_max_health), 0.0, 1.0)
	var filled_pixels := roundf(bar_width * health_ratio)
	if current_health > 0:
		filled_pixels = maxf(filled_pixels, 1.0)
	fill.size = Vector2(filled_pixels, 1.0)
	visible = current_health > 0 and current_health < safe_max_health

func _configure_rects() -> void:
	fill.position = Vector2(-floorf(bar_width * 0.5), 0.0)
	fill.size = Vector2(bar_width, 1.0)
	fill.color = theme.get_color(&"fill", &"EnemyHealthBar")
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.position = fill.position - Vector2.ONE
	background.size = fill.size + Vector2(2.0, 2.0)
	background.color = theme.get_color(&"background", &"EnemyHealthBar")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
