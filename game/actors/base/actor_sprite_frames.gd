@tool
class_name ActorSpriteFrames
extends SpriteFrames

## SpriteFrames resource that rebuilds actor animations from editable clip resources.

## Pixel size of one frame in every configured sprite sheet.
@export var frame_size: Vector2i = Vector2i(32, 32)
## Clip definitions used to rebuild this SpriteFrames resource.
@export var clips: Array[ActorAnimationClip] = []

var _clip_lookup: Dictionary[StringName, ActorAnimationClip] = {}

func ensure_built() -> void:
	_rebuild()

func source_faces_right(animation_name: StringName) -> bool:
	var clip := _clip_lookup.get(animation_name, null) as ActorAnimationClip
	if clip == null:
		return false
	return clip.source_faces_right

func _set(property: StringName, value: Variant) -> bool:
	var handled := false

	match property:
		&"frame_size":
			frame_size = value as Vector2i
			handled = true
		&"clips":
			clips = _to_clip_array(value)
			handled = true

	if handled and Engine.is_editor_hint():
		_rebuild()

	return handled

func _rebuild() -> void:
	_clip_lookup.clear()

	for animation_name: StringName in get_animation_names():
		remove_animation(animation_name)

	for clip: ActorAnimationClip in clips:
		if clip == null:
			continue

		if clip.animation_name.is_empty():
			push_warning("ActorSpriteFrames has a clip with an empty animation name.")
			continue

		if clip.sprite_path.is_empty():
			push_warning("Animation '%s' has no sprite path." % clip.animation_name)
			continue

		var texture := _load_sprite_texture(clip.sprite_path)
		if texture == null:
			push_warning("Animation '%s' could not load '%s'." % [clip.animation_name, clip.sprite_path])
			continue

		_clip_lookup[clip.animation_name] = clip
		_add_clip(clip, texture)

func _load_sprite_texture(sprite_path: String) -> Texture2D:
	return ResourceLoader.load(sprite_path) as Texture2D

func _add_clip(clip: ActorAnimationClip, texture: Texture2D) -> void:
	var frame_count: int = int(texture.get_width() / float(frame_size.x))
	var row_count: int = int(texture.get_height() / float(frame_size.y))
	if frame_count <= 0 or row_count <= 0:
		push_warning("Animation '%s' has no frames for frame size %s." % [clip.animation_name, frame_size])
		return

	var last_row: int = clip.source_row if clip.end_row <= 0 else mini(clip.end_row, row_count - 1)
	var first_column: int = clampi(clip.start_column, 0, frame_count - 1)
	var last_column: int = frame_count - 1 if clip.end_column < 0 else clampi(clip.end_column, 0, frame_count - 1)
	add_animation(clip.animation_name)
	set_animation_speed(clip.animation_name, 1.0 / clip.frame_duration)
	set_animation_loop(clip.animation_name, clip.loop)

	for row: int in range(clip.source_row, last_row + 1):
		var row_start_column: int = first_column if row == clip.source_row else 0
		var row_end_column: int = last_column if row == last_row else frame_count - 1

		for column: int in range(row_start_column, row_end_column + 1):
			var atlas_texture := AtlasTexture.new()
			atlas_texture.atlas = texture
			atlas_texture.region = Rect2(
				column * frame_size.x,
				row * frame_size.y,
				frame_size.x,
				frame_size.y
			)
			add_frame(clip.animation_name, atlas_texture)

func _to_clip_array(value: Variant) -> Array[ActorAnimationClip]:
	var typed_clips: Array[ActorAnimationClip] = []
	if not value is Array:
		return typed_clips

	for item in value:
		var clip := item as ActorAnimationClip
		if clip == null:
			push_warning("ActorSpriteFrames clips only accept ActorAnimationClip resources.")
			continue
		typed_clips.append(clip)

	return typed_clips
