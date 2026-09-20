extends Node2D

@export_range(48, 220, 1) var maximum_width: float = 154.0

@onready var _panel: PanelContainer = $Panel
@onready var _label: Label = $Panel/Text
@onready var _timer: Timer = $Timer

func _ready() -> void:
	hide()
	set_process(false)
	visibility_changed.connect(func() -> void: set_process(visible))
	_timer.timeout.connect(hide)
	_panel.resized.connect(_position_panel)
	_label.minimum_size_changed.connect(_panel.reset_size)

func _process(_delta: float) -> void:
	_position_panel()

func say(text: String) -> void:
	var font: Font = _label.get_theme_font("font")
	var font_size: int = _label.get_theme_font_size("font_size")
	var natural_width: float = 1.0
	for line: String in text.split("\n"):
		natural_width = maxf(natural_width,
			font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var padding: Vector2 = _panel.get_theme_stylebox("panel").get_minimum_size()
	var available_width: float = minf(maximum_width, get_viewport_rect().size.x - 8.0)
	_label.custom_minimum_size.x = ceilf(minf(natural_width, available_width - padding.x))
	_label.text = text
	_panel.reset_size()
	show()
	_position_panel()
	_timer.start(clampf(float(text.length()) * 0.055, 2.5, 6.0))

func _position_panel() -> void:
	var transform: Transform2D = get_global_transform_with_canvas()
	var inverse: Transform2D = transform.affine_inverse()
	var viewport: Rect2 = inverse * get_viewport_rect()
	var position := Vector2(-_panel.size.x * 0.5, -_panel.size.y)
	# Keep on-screen speakers readable near camera edges without dragging off-screen speech into view.
	if viewport.has_point(Vector2.ZERO):
		position.x = clampf(position.x, viewport.position.x + 4, viewport.end.x - _panel.size.x - 4)
		if position.y < viewport.position.y + 4:
			position.y = 14.0
	# Snap the rendered origin, preserving the theme font's native pixels even while the actor moves.
	_panel.position = inverse * (transform * position).round()
