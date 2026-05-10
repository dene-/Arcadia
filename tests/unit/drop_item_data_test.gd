extends "res://tests/test_case.gd"

const DropItemDataResource = preload("res://game/items/drops/drop_item_data.gd")

func test_stackable_item_uses_configured_max_stack() -> void:
	var item := DropItemDataResource.new()
	item.stackable = true
	item.max_stack = 12

	assert_eq(item.get_max_stack(), 12)

func test_non_stackable_item_uses_single_item_stack() -> void:
	var item := DropItemDataResource.new()
	item.stackable = false
	item.max_stack = 12

	assert_eq(item.get_max_stack(), 1)

func test_max_stack_never_goes_below_one() -> void:
	var item := DropItemDataResource.new()
	item.stackable = true
	item.max_stack = 0

	assert_eq(item.get_max_stack(), 1)

func test_display_name_uses_explicit_name_when_present() -> void:
	var item := DropItemDataResource.new()
	item.item_id = &"iron_ore"
	item.display_name = "Iron Ore"

	assert_eq(item.get_display_name(), "Iron Ore")

func test_display_name_falls_back_to_capitalized_item_id() -> void:
	var item := DropItemDataResource.new()
	item.item_id = &"goblin_ear"

	assert_eq(item.get_display_name(), "Goblin Ear")
