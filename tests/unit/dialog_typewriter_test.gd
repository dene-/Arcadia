extends "res://tests/test_case.gd"

const DialogTypewriterResource = preload("res://game/ui/dialog/dialog_typewriter.gd")

var _played_characters: Array[String] = []
var _played_indexes: Array[int] = []
var _labels: Array[RichTextLabel] = []

func before_each() -> void:
	_played_characters.clear()
	_played_indexes.clear()

func after_each() -> void:
	for label: RichTextLabel in _labels:
		label.free()
	_labels.clear()

func test_begin_sets_label_text_and_starts_hidden() -> void:
	var label := _make_label()
	var typewriter := DialogTypewriterResource.new()

	typewriter.begin(label, "Hello")

	assert_eq(label.text, "Hello")
	assert_eq(label.visible_characters, 0)
	assert_true(typewriter.is_revealing())

func test_update_reveals_characters_and_calls_callback() -> void:
	var label := _make_label()
	var typewriter := DialogTypewriterResource.new()
	typewriter.begin(label, "Hey")

	typewriter.update(label, 2.0 / DialogTypewriterResource.CHARACTERS_PER_SECOND, _record_character)

	assert_eq(label.visible_characters, 2)
	assert_eq(_played_characters, ["H", "e"])
	assert_eq(_played_indexes, [0, 1])
	assert_true(typewriter.is_revealing())

func test_update_reveals_whitespace_through_normal_flow() -> void:
	var label := _make_label()
	var typewriter := DialogTypewriterResource.new()
	typewriter.begin(label, "A B")

	typewriter.update(label, 3.0 / DialogTypewriterResource.CHARACTERS_PER_SECOND, _record_character)

	assert_eq(_played_characters, ["A", " ", "B"])
	assert_eq(_played_indexes, [0, 1, 2])
	assert_eq(label.visible_characters, -1)
	assert_false(typewriter.is_revealing())

func test_reveal_immediately_finishes_active_page() -> void:
	var label := _make_label()
	var typewriter := DialogTypewriterResource.new()
	typewriter.begin(label, "Done")

	typewriter.reveal_immediately(label)

	assert_eq(label.visible_characters, 4)
	assert_false(typewriter.is_revealing())

func test_reset_stops_revealing_and_restores_full_visibility() -> void:
	var label := _make_label()
	var typewriter := DialogTypewriterResource.new()
	typewriter.begin(label, "Reset")

	typewriter.reset(label)

	assert_eq(label.visible_characters, -1)
	assert_false(typewriter.is_revealing())

func _record_character(character: String, character_index: int) -> void:
	_played_characters.append(character)
	_played_indexes.append(character_index)

func _make_label() -> RichTextLabel:
	var label := RichTextLabel.new()
	_labels.append(label)
	return label
