class_name DropTable
extends Resource

## Data-driven loot table used by NPCs when they die.

const DropTableEntryResource = preload("res://game/items/drops/drop_table_entry.gd")

## Loot rolls to evaluate when this drop table is spawned.
@export var entries: Array[DropTableEntryResource] = []
## Maximum random distance from the source actor when drops appear.
@export_range(0.0, 64.0, 1.0) var scatter_radius: float = 8.0
