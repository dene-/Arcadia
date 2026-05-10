extends "res://tests/test_case.gd"

const DropItemDataResource = preload("res://game/items/drops/drop_item_data.gd")
const InventorySlotDataResource = preload("res://game/items/inventory/inventory_slot_data.gd")
const InventoryStackDataResource = preload("res://game/items/inventory/inventory_stack_data.gd")

func test_new_slot_is_empty() -> void:
	var slot := InventorySlotDataResource.new()

	assert_true(slot.is_empty())

func test_set_stack_stores_item_and_count() -> void:
	var item := _make_item()
	var slot := InventorySlotDataResource.new()

	slot.set_stack(item, 3)

	assert_false(slot.is_empty())
	assert_eq(slot.item, item)
	assert_eq(slot.count, 3)

func test_set_stack_with_zero_or_negative_count_clears_item() -> void:
	var item := _make_item()
	var slot := InventorySlotDataResource.new()

	slot.set_stack(item, -5)

	assert_true(slot.is_empty())
	assert_null(slot.item)
	assert_eq(slot.count, 0)

func test_to_stack_data_copies_item_and_count() -> void:
	var item := _make_item()
	var slot := InventorySlotDataResource.new()
	slot.set_stack(item, 4)

	var stack: InventoryStackDataResource = slot.to_stack_data()

	assert_eq(stack.item, item)
	assert_eq(stack.count, 4)

func test_clear_removes_item_and_count() -> void:
	var item := _make_item()
	var slot := InventorySlotDataResource.new()
	slot.set_stack(item, 2)

	slot.clear()

	assert_true(slot.is_empty())
	assert_null(slot.item)
	assert_eq(slot.count, 0)

func test_stack_data_clamps_negative_count_and_reports_empty() -> void:
	var item := _make_item()

	var stack := InventoryStackDataResource.new(item, -3)

	assert_eq(stack.count, 0)
	assert_true(stack.is_empty())

func _make_item() -> DropItemDataResource:
	var item := DropItemDataResource.new()
	item.item_id = &"test_item"
	return item
