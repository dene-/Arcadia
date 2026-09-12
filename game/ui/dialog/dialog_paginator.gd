class_name DialogPaginator
extends RefCounted

const SAFE_PAGE_CHARACTER_LIMIT: int = 110

## Pass the laid-out dialog label to account for font metrics, wrapping, and explicit newlines.
func paginate(text: String, label: RichTextLabel = null) -> Array[String]:
	if text.is_empty():
		return [""]

	var pages: Array[String] = []
	var remaining := text.strip_edges()
	while not remaining.is_empty():
		var length := mini(remaining.length(), SAFE_PAGE_CHARACTER_LIMIT)
		if label != null:
			var low := 1
			var high := length
			while low < high:
				var middle := (low + high + 1) / 2
				if _fits_label(remaining.substr(0, middle), label):
					low = middle
				else:
					high = middle - 1
			length = low
		if length < remaining.length() and remaining[length] not in [" ", "\n"]:
			var word_break := maxi(
				remaining.rfind(" ", length - 1), remaining.rfind("\n", length - 1)
			)
			if word_break > 0:
				length = word_break
		pages.append(remaining.substr(0, length).strip_edges())
		remaining = remaining.substr(length).strip_edges()
	if pages.is_empty():
		return [""]
	return pages

func _fits_label(text: String, label: RichTextLabel) -> bool:
	var paragraph := TextParagraph.new()
	var available_size := label.size - label.get_theme_stylebox(&"normal").get_minimum_size()
	paragraph.width = maxf(available_size.x, 1.0)
	paragraph.break_flags = (
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	)
	paragraph.line_spacing = label.get_theme_constant(&"line_separation")
	paragraph.add_string(
		text, label.get_theme_font(&"normal_font"), label.get_theme_font_size(&"normal_font_size")
	)
	return paragraph.get_size().y <= available_size.y
