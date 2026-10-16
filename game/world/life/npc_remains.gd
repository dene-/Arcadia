class_name NpcRemains
extends Sprite2D

## Holds the fallen pose before the source animation's dissolve/disappearance frames.
## The pose must be at least this much wider than tall to count as lying down.
const LYING_ASPECT: float = 1.2
## Frames with fewer opaque pixels than this share of the peak are already dissolving.
const DISSOLVE_SHARE: float = 0.7
## A jump in opaque pixels after the first frames is an effect (flash, soul), not the body.
const EFFECT_BURST: float = 1.25

var _fallen_texture: Texture2D
var _shroud: Node2D

class Shroud extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(-8, -4, 16, 7), Color("5b5346"))
		draw_rect(Rect2(-7, -4, 14, 6), Color("c3bda7"))
		draw_rect(Rect2(-5, -3, 10, 3), Color("e0d6b8"))
		draw_rect(Rect2(-4, -4, 1, 6), Color("8e876f"))
		draw_rect(Rect2(4, -4, 1, 6), Color("8e876f"))

## Index of the frame where the body lies flat before it dissolves, or -1 when the
## animation never lies down. Ties go to the later frame so props have settled.
static func fallen_frame(frames: SpriteFrames) -> int:
	if frames is ActorSpriteFrames:
		frames.ensure_built()
	if not frames.has_animation(&"die"):
		return -1
	var counts: Array[int] = []
	var aspects: Array[float] = []
	for index: int in range(frames.get_frame_count(&"die")):
		var pixels: Image = frames.get_frame_texture(&"die", index).get_image()
		var rect: Rect2i = pixels.get_used_rect()
		var opaque: int = 0
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				opaque += int(pixels.get_pixel(x, y).a > 0.5)
		counts.append(opaque)
		aspects.append(float(rect.size.x) / maxf(float(rect.size.y), 1.0))
	var end: int = counts.size()
	for index: int in range(2, counts.size()):
		if counts[index] > maxi(counts[index - 1], counts[index - 2]) * EFFECT_BURST:
			end = index
			break
	var peak: int = 0
	for index: int in range(end):
		peak = maxi(peak, counts[index])
	var result: int = -1
	var widest: float = LYING_ASPECT
	for index: int in range(end):
		if counts[index] >= peak * DISSOLVE_SHARE and aspects[index] >= widest:
			widest = aspects[index]
			result = index
	return result

func configure(frames: SpriteFrames) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var index: int = fallen_frame(frames)
	texture = frames.get_frame_texture(&"die", index) if index >= 0 else frames.get_frame_texture(&"idle", 0)
	_fallen_texture = texture
	if index < 0:
		rotation = PI / 2
	modulate = Color(0.78, 0.78, 0.78)

func set_carried(value: bool) -> void:
	if _shroud == null:
		_shroud = Shroud.new()
		add_child(_shroud)
	texture = null if value else _fallen_texture
	_shroud.visible = value
