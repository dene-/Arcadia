extends "res://tests/test_case.gd"

const DialogPaginatorResource = preload("res://game/ui/dialog/dialog_paginator.gd")

func test_empty_text_returns_one_empty_page() -> void:
	var paginator := DialogPaginatorResource.new()

	var pages := paginator.paginate("")

	assert_eq(pages.size(), 1)
	assert_eq(pages[0], "")

func test_long_words_are_split_to_safe_page_limit() -> void:
	var paginator := DialogPaginatorResource.new()
	var long_word := "x".repeat(DialogPaginatorResource.SAFE_PAGE_CHARACTER_LIMIT + 5)

	var pages := paginator.paginate(long_word)

	assert_eq(pages.size(), 2)
	assert_eq(pages[0].length(), DialogPaginatorResource.SAFE_PAGE_CHARACTER_LIMIT)
	assert_eq(pages[1].length(), 5)

func test_paginated_pages_do_not_exceed_safe_limit() -> void:
	var paginator := DialogPaginatorResource.new()
	var words: Array[String] = []
	for index: int in range(40):
		words.append("word%02d" % index)

	var pages := paginator.paginate(" ".join(words))

	assert_true(pages.size() > 1)
	for page: String in pages:
		assert_true(
			page.length() <= DialogPaginatorResource.SAFE_PAGE_CHARACTER_LIMIT,
			"Page exceeded the safe character limit: %d." % page.length()
		)

func test_newlines_are_preserved_within_a_page() -> void:
	var paginator := DialogPaginatorResource.new()
	assert_eq(paginator.paginate("First line\nSecond line"), ["First line\nSecond line"])

func test_explicit_line_breaks_fit_the_dialog_box() -> void:
	var label := _create_dialog_label(Vector2(206, 33))
	var text := "First line\nSecond line\nThird line\nFourth line\nFifth line\nSixth line"
	var paginator := DialogPaginatorResource.new()
	var pages := paginator.paginate(text, label)

	assert_true(pages.size() > 1, "Explicit newlines must count toward page height.")
	assert_eq("\n".join(pages), text, "Pagination must preserve all lines.")
	_assert_pages_fit(pages, label)
	label.free()

func test_long_words_fit_a_narrow_dialog_box() -> void:
	var label := _create_dialog_label(Vector2(72, 16))
	var text := "W".repeat(100)
	var paginator := DialogPaginatorResource.new()
	var pages := paginator.paginate(text, label)

	assert_true(pages.size() > 1)
	assert_eq("".join(pages), text, "Splitting wide words must not lose characters.")
	_assert_pages_fit(pages, label)
	label.free()

func test_wrapped_prose_preserves_words_and_fits() -> void:
	var label := _create_dialog_label(Vector2(100, 24))
	var text := "Wide words need enough room. The village needs your help. ".repeat(8).strip_edges()
	var paginator := DialogPaginatorResource.new()
	var pages := paginator.paginate(text, label)

	assert_eq(" ".join(pages), text)
	_assert_pages_fit(pages, label)
	label.free()

func _create_dialog_label(label_size: Vector2) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.theme = load("res://assets/art/ui/theme.tres")
	label.size = label_size
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.scroll_active = false
	(Engine.get_main_loop() as SceneTree).root.add_child(label)
	return label

func _assert_pages_fit(pages: Array[String], label: RichTextLabel) -> void:
	for page: String in pages:
		label.text = page
		assert_true(label.get_content_height() > 0, "The renderer must measure the page text.")
		assert_true(
			label.get_content_height() <= label.size.y,
			"Rendered page is %d pixels high in a %d pixel text box." % [
				label.get_content_height(), int(label.size.y)
			]
		)
