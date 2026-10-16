extends Node2D

## Pixels the tail art reaches beyond the panel edge it is attached to.
const TAIL_REACH: float = 8.0
## The tail art also covers the panel's two border rows, opening the border where it joins.
const TAIL_OVERLAP: float = 2.0
const TAIL_WIDTH: float = 16.0
## Horizontal room kept between the tail and the panel's rounded corners.
const TAIL_CORNER: float = 4.0
## Panel top when the speaker is too close to the top edge and the bubble opens below them.
const BELOW_SPEAKER_TOP: float = 22.0

@export_range(48, 220, 1) var maximum_width: float = 154.0
## Tail joined to the panel's bottom edge, pointing down at the speaker.
@export var tail_down: Texture2D
## Tail joined to the panel's top edge when the bubble opens below the speaker.
@export var tail_up: Texture2D

@onready var _panel: PanelContainer = $Panel
@onready var _label: Label = $Panel/Text
@onready var _tail: TextureRect = $Tail
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
	# Short lines still leave room for the tail between the panel's rounded corners.
	var tail_room: float = TAIL_WIDTH + TAIL_CORNER * 2.0 - padding.x
	_label.custom_minimum_size.x = ceilf(maxf(minf(natural_width, available_width - padding.x),
		tail_room))
	_label.text = text
	_panel.reset_size()
	show()
	_position_panel()
	_timer.start(clampf(float(text.length()) * 0.055, 2.5, 6.0))

func _position_panel() -> void:
	var transform: Transform2D = get_global_transform_with_canvas()
	var inverse: Transform2D = transform.affine_inverse()
	var viewport: Rect2 = inverse * get_viewport_rect()
	var position := Vector2(-_panel.size.x * 0.5, -_panel.size.y - TAIL_REACH)
	var below: bool = false
	# Keep on-screen speakers readable near camera edges without dragging off-screen speech into view.
	if viewport.has_point(Vector2.ZERO):
		position.x = clampf(position.x, viewport.position.x + 4, viewport.end.x - _panel.size.x - 4)
		if position.y < viewport.position.y + 4:
			position.y = BELOW_SPEAKER_TOP
			below = true
	# Snap the rendered origin, preserving the theme font's native pixels even while the actor moves.
	_panel.position = inverse * (transform * position).round()
	# The tail points at the speaker but stays between the panel's rounded corners.
	var tail_x: float = clampf(roundf(-TAIL_WIDTH * 0.5 - position.x), TAIL_CORNER,
		maxf(TAIL_CORNER, _panel.size.x - TAIL_WIDTH - TAIL_CORNER))
	_tail.texture = tail_up if below else tail_down
	var tail_y: float = -TAIL_REACH if below else _panel.size.y - TAIL_OVERLAP
	_tail.position = _panel.position + Vector2(tail_x, tail_y)
