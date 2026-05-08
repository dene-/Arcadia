class_name DropItemData
extends Resource

## Item metadata used by world drops and inventory UI.

## Stable identifier used by gameplay systems and future inventory code.
@export var item_id: StringName
## Player-facing item name used in editor labels and future UI.
@export var display_name: String = ""
## Player-facing description shown by inventory detail UI.
@export_multiline var description: String = ""
## Optional item icon for inventory UI and drag previews.
@export var icon: Texture2D
## Whether more than one item can share one inventory slot.
@export var stackable: bool = true
## Maximum count that can fit in one inventory slot.
@export_range(1, 99, 1) var max_stack: int = 99
## Whether the inventory context menu should expose this item as usable later.
@export var usable: bool = false
## Optional use action identifier for future gameplay item behavior.
@export var use_action: StringName
## Optional preferred world drop scene for this item.
@export var world_drop_scene: PackedScene
## Marker color used by the placeholder world drop scene.
@export var color: Color = Color(1.0, 1.0, 1.0, 1.0)

func get_max_stack() -> int:
	if not stackable:
		return 1
	return maxi(max_stack, 1)

func get_display_name() -> String:
	if not display_name.is_empty():
		return display_name
	return String(item_id).capitalize()
