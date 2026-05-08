class_name DialogPaginator
extends RefCounted

const SAFE_PAGE_CHARACTER_LIMIT: int = 110

func paginate(text: String) -> Array[String]:
	if text.is_empty():
		return [""]

	var chunks := _split_into_chunks(text, SAFE_PAGE_CHARACTER_LIMIT)
	return _assemble_pages(chunks, SAFE_PAGE_CHARACTER_LIMIT)

func _split_into_chunks(text: String, character_limit: int) -> Array[String]:
	var chunks: Array[String] = []
	var current := ""

	for word in text.split(" ", false):
		if word.length() > character_limit:
			if not current.is_empty():
				chunks.append(current)
				current = ""
			var start := 0
			while start < word.length():
				chunks.append(word.substr(start, character_limit))
				start += character_limit
			continue

		if current.is_empty():
			current = word
			continue

		var candidate := "%s %s" % [current, word]
		if candidate.length() <= character_limit:
			current = candidate
		else:
			chunks.append(current)
			current = word

	if not current.is_empty():
		chunks.append(current)
	return chunks

func _assemble_pages(chunks: Array[String], character_limit: int) -> Array[String]:
	var pages: Array[String] = []
	var current_page := ""

	for chunk in chunks:
		if current_page.is_empty():
			current_page = chunk
			continue

		var candidate := "%s %s" % [current_page, chunk]
		if candidate.length() <= character_limit:
			current_page = candidate
		else:
			pages.append(current_page)
			current_page = chunk

	if not current_page.is_empty():
		pages.append(current_page)

	if pages.is_empty():
		pages.append("")
	return pages
