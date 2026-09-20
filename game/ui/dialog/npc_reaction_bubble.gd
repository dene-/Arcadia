extends Node2D

@onready var _panel: PanelContainer = $Panel
@onready var _label: Label = $Panel/Text
@onready var _timer: Timer = $Timer

func _ready() -> void:
	hide()
	_timer.timeout.connect(hide)
	_panel.resized.connect(_position_panel)

func say(text: String) -> void:
	_label.text = text
	show()
	_position_panel()
	_timer.start(clampf(float(text.length()) * 0.055, 2.5, 6.0))

func _position_panel() -> void:
	_panel.position = Vector2(-_panel.size.x * 0.5, -_panel.size.y)
