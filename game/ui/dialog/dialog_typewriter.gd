class_name DialogTypewriter
extends RefCounted

const CHARACTERS_PER_SECOND: float = 45.0

var _is_revealing: bool = false
var _progress: float = 0.0
var _visible_character_count: int = 0
var _page_text: String = ""

func begin(label: RichTextLabel, page_text: String) -> void:
	_page_text = page_text
	_progress = 0.0
	_visible_character_count = 0
	_is_revealing = true
	label.text = page_text
	label.visible_characters = 0

func reveal_immediately(label: RichTextLabel) -> void:
	if not _is_revealing:
		return

	label.visible_characters = _page_text.length()
	_progress = float(label.visible_characters)
	_visible_character_count = label.visible_characters
	_is_revealing = false

func update(label: RichTextLabel, delta: float, play_character: Callable) -> void:
	if not _is_revealing:
		return

	var target_characters := _page_text.length()
	_progress += CHARACTERS_PER_SECOND * delta
	var next_visible_count := mini(target_characters, int(floor(_progress)))
	if next_visible_count <= _visible_character_count:
		return

	for character_index in range(_visible_character_count, next_visible_count):
		play_character.call(_page_text[character_index], character_index)

	_visible_character_count = next_visible_count
	label.visible_characters = _visible_character_count
	if _visible_character_count >= target_characters:
		_is_revealing = false
		label.visible_characters = -1

func reset(label: RichTextLabel) -> void:
	_page_text = ""
	_progress = 0.0
	_visible_character_count = 0
	_is_revealing = false
	if label != null:
		label.visible_characters = -1

func is_revealing() -> bool:
	return _is_revealing
