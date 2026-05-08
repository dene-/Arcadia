class_name InventorySlotData
extends Resource

const DropItemDataResource = preload("res://game/items/drops/drop_item_data.gd")
const InventoryStackDataResource = preload("res://game/items/inventory/inventory_stack_data.gd")

## Item stored in this inventory slot.
@export var item: DropItemDataResource
## Number of items in this inventory slot.
@export_range(0, 999, 1) var count: int = 0

func is_empty() -> bool:
	return item == null or count <= 0

func set_stack(next_item: DropItemDataResource, next_count: int) -> void:
	item = next_item
	count = maxi(next_count, 0)
	if count <= 0:
		item = null

func to_stack_data() -> InventoryStackDataResource:
	return InventoryStackDataResource.new(item, count)

func clear() -> void:
	item = null
	count = 0
