class_name InventorySlot
extends Control

const DropItemDataResource = preload("res://game/items/drops/drop_item_data.gd")

signal slot_selected(slot_index: int)
signal context_requested(slot_index: int, screen_position: Vector2)
signal item_dragged(from_slot: int, to_slot: int)

## Slot index this node represents in InventoryData.
@export_range(0, 255, 1) var slot_index: int = 0

@onready var item_swatch: ColorRect = $ItemSwatch
@onready var item_icon: TextureRect = $ItemIcon
@onready var count_label: Label = $CountLabel
@onready var selection_highlight: ColorRect = $SelectionHighlight

var item: DropItemDataResource
var count: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	for child: Node in get_children():
		var child_control := child as Control
		if child_control != null:
			child_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_highlight.hide()

func set_slot_data(next_item: DropItemDataResource, next_count: int) -> void:
	item = next_item
	count = next_count
	if item == null or count <= 0:
		item_swatch.hide()
		item_icon.hide()
		count_label.text = ""
		tooltip_text = ""
		return

	if item.icon != null:
		item_icon.texture = item.icon
		item_icon.show()
		item_swatch.hide()
	else:
		item_swatch.color = item.color
		item_swatch.show()
		item_icon.hide()
	count_label.text = str(count) if count > 1 else ""
	tooltip_text = ""

func set_selected(selected: bool) -> void:
	selection_highlight.visible = selected

func get_display_text() -> String:
	if item == null or count <= 0:
		return ""
	return _format_slot_text()

func _gui_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed:
		return

	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		slot_selected.emit(slot_index)
		accept_event()
	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and item != null:
		context_requested.emit(slot_index, get_screen_position() + mouse_event.position)
		accept_event()

func _get_drag_data(at_position: Vector2) -> Variant:
	if item == null or count <= 0:
		return null
	slot_selected.emit(slot_index)
	var preview := _create_drag_preview(at_position)
	set_drag_preview(preview)
	return {
		"source": "inventory",
		"slot_index": slot_index,
	}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("source", "") == "inventory" and int(data.get("slot_index", -1)) != slot_index

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	item_dragged.emit(int(data.get("slot_index", -1)), slot_index)

func _create_drag_preview(at_position: Vector2) -> Control:
	var preview_root := Control.new()
	preview_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var preview_slot := duplicate() as Control
	assert(preview_slot != null, "InventorySlot drag preview requires a Control duplicate.")
	preview_slot.position = -at_position.round()
	preview_slot.modulate = Color(1.0, 1.0, 1.0, 0.78)
	preview_root.add_child(preview_slot)
	preview_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return preview_root

func _format_slot_text() -> String:
	var text := item.get_display_name()
	if count > 1:
		text = "%s x%d" % [text, count]
	if not item.description.is_empty():
		text = "%s\n%s" % [text, item.description]
	return text
