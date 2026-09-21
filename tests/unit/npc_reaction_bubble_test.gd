extends "res://tests/test_case.gd"

func test_bubble_fits_short_text_wraps_long_text_and_shrinks_without_scaling_font() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var bubble: Node2D = load("res://game/ui/dialog/npc_reaction_bubble.tscn").instantiate()
	tree.root.add_child(bubble)
	var panel: PanelContainer = bubble.get_node("Panel")
	var label: Label = panel.get_node("Text")
	var font_size: int = label.get_theme_font_size("font_size")
	bubble.say("Hello.")
	await tree.process_frame
	await tree.process_frame
	var compact: Vector2 = panel.size
	assert_true(compact.x < bubble.maximum_width)
	bubble.say("Mirelle told me she heard fighting near the market. Have you seen Den today?")
	await tree.process_frame
	await tree.process_frame
	assert_true(panel.size.x <= bubble.maximum_width, "Bubble exceeded its maximum width")
	assert_true(panel.size.y > compact.y, "Long text did not wrap")
	assert_eq(label.get_theme_font_size("font_size"), font_size)
	assert_eq(label.scale, Vector2.ONE)
	bubble.say("Hello.")
	await tree.process_frame
	await tree.process_frame
	assert_eq(panel.size, compact, "Bubble retained the previous line's width or height")
	bubble.free()
