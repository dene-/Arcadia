@tool
class_name InventoryPanel
extends CanvasLayer

const InventoryDataResource = preload("res://game/items/inventory/inventory_data.gd")
const InventorySlotNode = preload("res://game/ui/inventory/inventory_slot.gd")

const CONTEXT_USE_ID: int = 0
const CONTEXT_DROP_ONE_ID: int = 1
const CONTEXT_DROP_STACK_ID: int = 2

## NodePath to the player that owns the inventory resource.
@export var player_path: NodePath
## Inventory resource displayed by this panel. The player is wired to the same resource at runtime.
@export var inventory_data: InventoryDataResource:
	set(value):
		inventory_data = value
		if is_node_ready():
			_bind_inventory()
			_rebuild_slots()
## Input action that opens or closes the inventory panel.
@export var toggle_action: StringName = &"inventory_toggle"

@onready var panel: Panel = $Panel
@onready var grid: GridContainer = $Panel/MarginContainer/VBoxContainer/SlotScroll/SlotGrid
@onready var detail_label: Label = $Panel/MarginContainer/VBoxContainer/DetailLabel
@onready var summary_label: Label = $Panel/MarginContainer/VBoxContainer/HeaderRow/SummaryLabel
@onready var context_menu: PopupMenu = $ContextMenu

var _inventory: InventoryDataResource
var _player: Node
var _slot_nodes: Array[InventorySlotNode] = []
var _selected_slot: int = -1
var _context_slot: int = -1

func _ready() -> void:
	if not Engine.is_editor_hint():
		panel.hide()
	_cache_slot_nodes()
	_bind_inventory()
	_configure_context_menu()
	_rebuild_slots()

func _exit_tree() -> void:
	remove_from_group("blocking_player_input")

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	if event.is_action_pressed(toggle_action):
		_set_inventory_open(not panel.visible)
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not panel.visible:
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _is_screen_position_over_inventory_control(mouse_event.position):
		return

	_selected_slot = -1
	_context_slot = -1
	context_menu.hide()
	_rebuild_slots()

func _bind_inventory() -> void:
	_player = get_node_or_null(player_path)
	if inventory_data != null:
		_set_inventory(inventory_data)
		if _player != null and _player.has_method("set_inventory_data"):
			_player.call("set_inventory_data", inventory_data)
		return

	if _player == null or not _player.has_method("get_inventory_data"):
		return

	_set_inventory(_player.call("get_inventory_data") as InventoryDataResource)

func _configure_context_menu() -> void:
	context_menu.clear()
	context_menu.add_item("Use", CONTEXT_USE_ID)
	context_menu.add_item("Drop One", CONTEXT_DROP_ONE_ID)
	context_menu.add_item("Drop Stack", CONTEXT_DROP_STACK_ID)
	if not context_menu.id_pressed.is_connected(_on_context_menu_id_pressed):
		context_menu.id_pressed.connect(_on_context_menu_id_pressed)

func _cache_slot_nodes() -> void:
	_slot_nodes.clear()
	for child: Node in grid.get_children():
		var slot := child as InventorySlotNode
		if slot == null:
			continue

		slot.slot_index = _slot_nodes.size()
		_slot_nodes.append(slot)
		_connect_slot(slot)

func _set_inventory(next_inventory: InventoryDataResource) -> void:
	if _inventory != null and _inventory.inventory_changed.is_connected(_rebuild_slots):
		_inventory.inventory_changed.disconnect(_rebuild_slots)

	_inventory = next_inventory
	if _inventory != null and not _inventory.inventory_changed.is_connected(_rebuild_slots):
		_inventory.inventory_changed.connect(_rebuild_slots)

func _rebuild_slots() -> void:
	if _inventory == null:
		_bind_inventory()
	if _inventory == null:
		_update_summary()
		return

	_ensure_slot_nodes_for_capacity(_inventory.get_slot_capacity())

	for slot: InventorySlotNode in _slot_nodes:
		var active := slot.slot_index < _inventory.get_slot_capacity()
		slot.visible = active
		if active:
			slot.set_slot_data(_inventory.get_slot_item(slot.slot_index), _inventory.get_slot_count(slot.slot_index))
			slot.set_selected(slot.slot_index == _selected_slot)

	if _selected_slot >= _inventory.get_slot_capacity():
		_selected_slot = -1

	_update_summary()
	_update_detail_for_selection()

func _ensure_slot_nodes_for_capacity(required_capacity: int) -> void:
	if _slot_nodes.is_empty():
		return

	var base_slot := _slot_nodes[0]
	while _slot_nodes.size() < required_capacity:
		var slot := base_slot.duplicate() as InventorySlotNode
		if slot == null:
			return

		slot.name = "Slot%d" % _slot_nodes.size()
		slot.slot_index = _slot_nodes.size()
		grid.add_child(slot)
		if Engine.is_editor_hint():
			slot.owner = null
		_slot_nodes.append(slot)
		_connect_slot(slot)

func _connect_slot(slot: InventorySlotNode) -> void:
	if not slot.slot_selected.is_connected(_on_slot_selected):
		slot.slot_selected.connect(_on_slot_selected)
	if not slot.context_requested.is_connected(_on_slot_context_requested):
		slot.context_requested.connect(_on_slot_context_requested)
	if not slot.item_dragged.is_connected(_on_item_dragged):
		slot.item_dragged.connect(_on_item_dragged)
	if not slot.mouse_entered.is_connected(_on_slot_mouse_entered.bind(slot.slot_index)):
		slot.mouse_entered.connect(_on_slot_mouse_entered.bind(slot.slot_index))
	if not slot.mouse_exited.is_connected(_on_slot_mouse_exited):
		slot.mouse_exited.connect(_on_slot_mouse_exited)

func _update_summary() -> void:
	if _inventory == null:
		summary_label.text = "0/0"
		return

	summary_label.text = "%d/%d" % [
		_inventory.get_used_slot_count(),
		_inventory.get_slot_capacity(),
	]

func _set_inventory_open(open: bool) -> void:
	panel.visible = open
	if open:
		add_to_group("blocking_player_input")
	else:
		remove_from_group("blocking_player_input")
		context_menu.hide()
		_selected_slot = -1
		_context_slot = -1
		_rebuild_slots()

func _on_slot_selected(slot_index: int) -> void:
	if _inventory == null or slot_index >= _inventory.get_slot_capacity():
		return

	_selected_slot = slot_index
	_rebuild_slots()

func _on_slot_context_requested(slot_index: int, screen_position: Vector2) -> void:
	if _inventory == null or _inventory.get_slot_item(slot_index) == null:
		return

	_context_slot = slot_index
	var item := _inventory.get_slot_item(slot_index)
	context_menu.set_item_disabled(context_menu.get_item_index(CONTEXT_USE_ID), item == null or not item.usable)
	context_menu.position = Vector2i(screen_position)
	context_menu.popup()

func _on_item_dragged(from_slot: int, to_slot: int) -> void:
	if _inventory == null:
		return

	if _inventory.merge_or_swap_slots(from_slot, to_slot):
		_selected_slot = to_slot
		_rebuild_slots()

func _on_context_menu_id_pressed(id: int) -> void:
	if _context_slot < 0:
		return

	if id == CONTEXT_USE_ID:
		_context_slot = -1
		return

	if _player == null or not _player.has_method("drop_inventory_stack"):
		return

	if id == CONTEXT_DROP_ONE_ID:
		_player.call("drop_inventory_stack", _context_slot, 1)
	elif id == CONTEXT_DROP_STACK_ID:
		_player.call("drop_inventory_stack", _context_slot, -1)
	_context_slot = -1

func _on_slot_mouse_entered(slot_index: int) -> void:
	if _inventory == null or slot_index >= _inventory.get_slot_capacity():
		return

	var slot := _get_slot_node(slot_index)
	if slot == null:
		return

	detail_label.text = slot.get_display_text()

func _on_slot_mouse_exited() -> void:
	_update_detail_for_selection()

func _update_detail_for_selection() -> void:
	var slot := _get_slot_node(_selected_slot)
	if slot == null:
		detail_label.text = ""
		return

	detail_label.text = slot.get_display_text()

func _get_slot_node(slot_index: int) -> InventorySlotNode:
	for slot: InventorySlotNode in _slot_nodes:
		if slot.slot_index == slot_index:
			return slot
	return null

func _is_screen_position_over_inventory_control(screen_position: Vector2) -> bool:
	if context_menu.visible:
		var context_rect := Rect2(Vector2(context_menu.position), Vector2(context_menu.size))
		if context_rect.has_point(screen_position):
			return true

	for slot: InventorySlotNode in _slot_nodes:
		if slot.visible and slot.get_global_rect().has_point(screen_position):
			return true

	return false
