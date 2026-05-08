class_name DropTableEntry
extends Resource

## One probabilistic entry in an NPC drop table.

const DropItemDataResource = preload("res://game/items/drops/drop_item_data.gd")

## Item metadata assigned to spawned drops for this entry.
@export var item: DropItemDataResource
## Independent probability that this entry spawns. 0.0 never drops, 1.0 always drops.
@export_range(0.0, 1.0, 0.01) var chance: float = 1.0
## Minimum stack count spawned if this entry succeeds.
@export_range(1, 99, 1) var min_count: int = 1
## Maximum stack count spawned if this entry succeeds.
@export_range(1, 99, 1) var max_count: int = 1
## Scene instantiated for the visible world drop.
@export var drop_scene: PackedScene
