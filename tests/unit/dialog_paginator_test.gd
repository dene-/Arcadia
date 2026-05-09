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
