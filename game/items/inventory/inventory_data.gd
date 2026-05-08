@tool
class_name InventoryData
extends Resource

const DropItemDataResource = preload("res://game/items/drops/drop_item_data.gd")
const InventoryStackDataResource = preload("res://game/items/inventory/inventory_stack_data.gd")

signal inventory_changed

## Maximum number of item stacks this inventory can hold.
@export_range(1, 64, 1) var capacity: int:
	get:
		return _capacity
	set(value):
		resize_capacity(value)
## Serialized inventory slots. Each slot stores its item resource and stack count.
@export var slots: Array[InventorySlotData] = []

var _capacity: int = 16

func can_add_item(item: DropItemDataResource, count: int = 1) -> bool:
	if item == null or count <= 0:
		return false
	return get_addable_count(item) >= count

func get_addable_count(item: DropItemDataResource) -> int:
	if item == null:
		return 0

	_ensure_slot_capacity()
	var addable_count := 0
	var max_stack := item.get_max_stack()
	for slot: InventorySlotData in slots:
		if slot.is_empty():
			addable_count += max_stack
		elif _is_same_item(slot.item, item):
			addable_count += maxi(max_stack - slot.count, 0)

	return addable_count

func add_item(item: DropItemDataResource, count: int = 1) -> int:
	if item == null or count <= 0:
		return count

	_ensure_slot_capacity()
	var remaining := count
	remaining = _add_to_existing_stacks(item, remaining)
	remaining = _add_to_empty_slots(item, remaining)

	if remaining != count:
		inventory_changed.emit()

	return remaining

func remove_from_slot(slot_index: int, amount: int) -> InventoryStackDataResource:
	_ensure_slot_capacity()
	if amount <= 0 or not _is_valid_slot(slot_index):
		return InventoryStackDataResource.new()

	var slot := slots[slot_index]
	if slot.is_empty():
		return InventoryStackDataResource.new()

	var removed_count := mini(amount, slot.count)
	var removed_stack := InventoryStackDataResource.new(slot.item, removed_count)
	slot.count -= removed_count
	if slot.count <= 0:
		slot.clear()
	inventory_changed.emit()
	return removed_stack

func split_stack(from_slot: int, to_slot: int, amount: int) -> bool:
	_ensure_slot_capacity()
	if amount <= 0 or not _is_valid_slot(from_slot) or not _is_valid_slot(to_slot) or from_slot == to_slot:
		return false

	var source := slots[from_slot]
	var target := slots[to_slot]
	if source.is_empty() or not target.is_empty() or amount >= source.count:
		return false

	target.set_stack(source.item, amount)
	source.count -= amount
	inventory_changed.emit()
	return true

func merge_or_swap_slots(from_slot: int, to_slot: int) -> bool:
	_ensure_slot_capacity()
	if not _is_valid_slot(from_slot) or not _is_valid_slot(to_slot) or from_slot == to_slot:
		return false

	var source := slots[from_slot]
	var target := slots[to_slot]
	if source.is_empty():
		return false

	if target.is_empty():
		target.set_stack(source.item, source.count)
		source.clear()
		inventory_changed.emit()
		return true

	if _is_same_item(source.item, target.item) and target.count < target.item.get_max_stack():
		var moved_count := mini(target.item.get_max_stack() - target.count, source.count)
		target.count += moved_count
		source.count -= moved_count
		if source.count <= 0:
			source.clear()
		inventory_changed.emit()
		return true

	var old_target := target.to_stack_data()
	target.set_stack(source.item, source.count)
	source.set_stack(old_target.item, old_target.count)
	inventory_changed.emit()
	return true

func move_slot(from_slot: int, to_slot: int) -> bool:
	return merge_or_swap_slots(from_slot, to_slot)

func drop_from_slot(slot_index: int, amount: int = -1) -> InventoryStackDataResource:
	_ensure_slot_capacity()
	if not _is_valid_slot(slot_index):
		return InventoryStackDataResource.new()

	var slot := slots[slot_index]
	if slot.is_empty():
		return InventoryStackDataResource.new()

	var drop_count := slot.count if amount <= 0 else mini(amount, slot.count)
	return remove_from_slot(slot_index, drop_count)

func take_slot(slot_index: int) -> InventoryStackDataResource:
	return drop_from_slot(slot_index)

func resize_capacity(next_capacity: int) -> bool:
	var clamped_capacity := maxi(next_capacity, 1)
	if clamped_capacity < _capacity and _has_items_past_capacity(clamped_capacity):
		push_warning("Inventory capacity shrink rejected because items would be lost.")
		return false

	if _capacity == clamped_capacity and slots.size() == clamped_capacity:
		return true

	_capacity = clamped_capacity
	_ensure_slot_capacity()
	inventory_changed.emit()
	return true

func set_capacity(next_capacity: int) -> void:
	resize_capacity(next_capacity)

func get_slot_capacity() -> int:
	return _capacity

func get_slot_item(slot_index: int) -> DropItemDataResource:
	_ensure_slot_capacity()
	if not _is_valid_slot(slot_index):
		return null
	return slots[slot_index].item

func get_slot_count(slot_index: int) -> int:
	_ensure_slot_capacity()
	if not _is_valid_slot(slot_index):
		return 0
	return slots[slot_index].count

func get_used_slot_count() -> int:
	_ensure_slot_capacity()
	var used_count := 0
	for slot: InventorySlotData in slots:
		if not slot.is_empty():
			used_count += 1
	return used_count

func get_total_item_count() -> int:
	_ensure_slot_capacity()
	var total_count := 0
	for slot: InventorySlotData in slots:
		total_count += slot.count
	return total_count

func is_empty() -> bool:
	_ensure_slot_capacity()
	for slot: InventorySlotData in slots:
		if not slot.is_empty():
			return false
	return true

func to_save_data() -> Dictionary:
	_ensure_slot_capacity()
	var saved_slots: Array[Dictionary] = []
	for slot: InventorySlotData in slots:
		if slot.is_empty():
			saved_slots.append({})
			continue

		saved_slots.append({
			"item_path": slot.item.resource_path,
			"count": slot.count,
		})

	return {
		"capacity": _capacity,
		"slots": saved_slots,
	}

func apply_save_data(data: Dictionary) -> void:
	var next_capacity := maxi(int(data.get("capacity", _capacity)), 1)
	_capacity = next_capacity
	slots.clear()
	_ensure_slot_capacity()

	var saved_slots := data.get("slots", []) as Array
	for slot_index: int in range(mini(saved_slots.size(), _capacity)):
		var saved_slot := saved_slots[slot_index] as Dictionary
		if saved_slot == null or saved_slot.is_empty():
			continue

		var item_path := String(saved_slot.get("item_path", ""))
		var item := ResourceLoader.load(item_path) as DropItemDataResource
		var count := int(saved_slot.get("count", 0))
		if item != null and count > 0:
			slots[slot_index].set_stack(item, mini(count, item.get_max_stack()))

	inventory_changed.emit()

func _add_to_existing_stacks(item: DropItemDataResource, count: int) -> int:
	for slot: InventorySlotData in slots:
		if count <= 0:
			return 0

		if not _is_same_item(slot.item, item):
			continue

		var room := maxi(item.get_max_stack() - slot.count, 0)
		if room <= 0:
			continue

		var added := mini(room, count)
		slot.count += added
		count -= added

	return count

func _add_to_empty_slots(item: DropItemDataResource, count: int) -> int:
	for slot: InventorySlotData in slots:
		if count <= 0:
			return 0

		if not slot.is_empty():
			continue

		var added := mini(item.get_max_stack(), count)
		slot.set_stack(item, added)
		count -= added

	return count

func _ensure_slot_capacity() -> void:
	while slots.size() < _capacity:
		slots.append(InventorySlotData.new())
	if slots.size() > _capacity:
		slots.resize(_capacity)

func _has_items_past_capacity(next_capacity: int) -> bool:
	for slot_index: int in range(next_capacity, slots.size()):
		if not slots[slot_index].is_empty():
			return true
	return false

func _is_valid_slot(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < slots.size()

func _is_same_item(first_item: DropItemDataResource, second_item: DropItemDataResource) -> bool:
	return first_item != null and second_item != null and first_item.item_id == second_item.item_id
