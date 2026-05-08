class_name InventoryStackData
extends RefCounted

const DropItemDataResource = preload("res://game/items/drops/drop_item_data.gd")

var item: DropItemDataResource
var count: int = 0

func _init(next_item: DropItemDataResource = null, next_count: int = 0) -> void:
	item = next_item
	count = maxi(next_count, 0)

func is_empty() -> bool:
	return item == null or count <= 0
