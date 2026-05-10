extends "res://tests/test_case.gd"

const DropItemDataResource = preload("res://game/items/drops/drop_item_data.gd")
const InventoryDataResource = preload("res://game/items/inventory/inventory_data.gd")

func test_add_item_fills_existing_stack_before_empty_slots() -> void:
	var item := _make_item(&"apple", 10)
	var inventory := InventoryDataResource.new()
	inventory.capacity = 2

	var remaining_first := inventory.add_item(item, 8)
	var remaining_second := inventory.add_item(item, 5)

	assert_eq(remaining_first, 0)
	assert_eq(remaining_second, 0)
	assert_eq(inventory.get_used_slot_count(), 2)
	assert_eq(inventory.get_slot_count(0), 10)
	assert_eq(inventory.get_slot_count(1), 3)

func test_add_item_returns_unstored_count_when_inventory_is_full() -> void:
	var item := _make_item(&"stone", 4)
	var inventory := InventoryDataResource.new()
	inventory.capacity = 1

	var remaining := inventory.add_item(item, 6)

	assert_eq(remaining, 2)
	assert_eq(inventory.get_total_item_count(), 4)

func test_split_stack_moves_requested_amount_to_empty_slot() -> void:
	var item := _make_item(&"berry", 10)
	var inventory := InventoryDataResource.new()
	inventory.capacity = 2
	inventory.add_item(item, 7)

	var did_split := inventory.split_stack(0, 1, 3)

	assert_true(did_split)
	assert_eq(inventory.get_slot_count(0), 4)
	assert_eq(inventory.get_slot_count(1), 3)

func test_remove_from_slot_clears_empty_source_slot() -> void:
	var item := _make_item(&"coin", 99)
	var inventory := InventoryDataResource.new()
	inventory.capacity = 1
	inventory.add_item(item, 2)

	var removed_stack := inventory.remove_from_slot(0, 2)

	assert_eq(removed_stack.item, item)
	assert_eq(removed_stack.count, 2)
	assert_true(inventory.is_empty())
	assert_null(inventory.get_slot_item(0))

func _make_item(item_id: StringName, max_stack: int) -> DropItemDataResource:
	var item := DropItemDataResource.new()
	item.item_id = item_id
	item.max_stack = max_stack
	item.stackable = true
	return item
