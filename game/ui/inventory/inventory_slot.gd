class_name InventorySlot
extends Control

const DropItemDataResource = preload("res://game/items/drops/drop_item_data.gd")

const DRAG_PREVIEW_BACKGROUND_COLOR := Color(1.0, 1.0, 1.0, 0.15)

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
	set_drag_preview(_create_drag_preview(_get_drag_visual_offset(at_position)))
	return {
		"source": "inventory",
		"slot_index": slot_index,
	}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("source", "") == "inventory" and int(data.get("slot_index", -1)) != slot_index

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	item_dragged.emit(int(data.get("slot_index", -1)), slot_index)

func _create_drag_preview(drag_visual_offset: Vector2) -> Control:
	var preview := Control.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.modulate = Color(1.0, 1.0, 1.0, 0.78)

	var visual := _create_drag_preview_visual()
	visual.position = -drag_visual_offset
	preview.add_child(_create_drag_preview_background(visual.position, visual.size))
	preview.add_child(visual)
	return preview

func _create_drag_preview_background(background_position: Vector2, background_size: Vector2) -> ColorRect:
	var background := ColorRect.new()
	background.color = DRAG_PREVIEW_BACKGROUND_COLOR
	background.position = background_position
	background.custom_minimum_size = background_size
	background.size = background_size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return background

func _create_drag_preview_visual() -> Control:
	if item.icon != null:
		var icon := TextureRect.new()
		icon.texture = item.icon
		icon.expand_mode = item_icon.expand_mode
		icon.stretch_mode = item_icon.stretch_mode
		icon.custom_minimum_size = item_icon.size
		icon.size = item_icon.size
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return icon

	var swatch := ColorRect.new()
	swatch.color = item.color
	swatch.custom_minimum_size = item_swatch.size
	swatch.size = item_swatch.size
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return swatch

func _get_drag_visual_offset(at_position: Vector2) -> Vector2:
	var source_visual := item_icon as Control if item.icon != null else item_swatch as Control
	return at_position - source_visual.position

func _format_slot_text() -> String:
	var text := item.get_display_name()
	if count > 1:
		text = "%s x%d" % [text, count]
	if not item.description.is_empty():
		text = "%s\n%s" % [text, item.description]
	return text
