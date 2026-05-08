class_name DroppedItem
extends Area2D

## Visible world drop that can transfer itself into a player inventory.

const DropItemDataResource = preload("res://game/items/drops/drop_item_data.gd")
const InventoryDataResource = preload("res://game/items/inventory/inventory_data.gd")

## Item metadata represented by this world drop.
@export var item: DropItemDataResource:
	set(value):
		_item = value
		_apply_item_data()
	get:
		return _item
## Number of items represented by this world drop.
@export_range(1, 99, 1) var count: int = 1
## Radius of the temporary circular marker drawn for this drop.
@export_range(2.0, 16.0, 1.0) var marker_radius: float = 4.0
## Seconds before this drop can be picked up after spawning. Enemy drops use 0; player drops set this explicitly.
@export_range(0.0, 3.0, 0.05) var pickup_delay: float = 0.0

var _item: DropItemDataResource
var _can_pick_up: bool = false
var _pickup_delay_token: int = 0

func _ready() -> void:
	add_to_group("world_drops")
	_apply_item_data()
	queue_redraw()
	_begin_pickup_delay()

func configure(next_item: DropItemDataResource, next_count: int, next_pickup_delay: float = 0.0) -> void:
	item = next_item
	count = maxi(next_count, 1)
	pickup_delay = maxf(next_pickup_delay, 0.0)
	_apply_item_data()
	if is_inside_tree():
		_begin_pickup_delay()

func collect_into(inventory: InventoryDataResource) -> bool:
	if not _can_pick_up or inventory == null or item == null or count <= 0:
		return false

	var previous_count := count
	var remaining := inventory.add_item(item, count)
	count = remaining
	if count <= 0:
		queue_free()
		return true

	return remaining < previous_count

func _draw() -> void:
	var marker_color := Color(1.0, 1.0, 1.0, 1.0)
	if _item != null:
		marker_color = _item.color

	draw_circle(Vector2.ZERO, marker_radius, marker_color)
	draw_arc(Vector2.ZERO, marker_radius, 0.0, TAU, 16, Color(0.08, 0.06, 0.04, 0.75), 1.0)

func _apply_item_data() -> void:
	if _item != null:
		name = _item.get_display_name().to_pascal_case()
	queue_redraw()

func _begin_pickup_delay() -> void:
	_pickup_delay_token += 1
	var token := _pickup_delay_token
	_can_pick_up = false
	monitorable = false
	if pickup_delay > 0.0:
		await get_tree().create_timer(pickup_delay).timeout
	if token != _pickup_delay_token:
		return
	_can_pick_up = true
	monitorable = true
