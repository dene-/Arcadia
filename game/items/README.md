# Items

Item gameplay systems live here.

- `data/`: item resources such as drops and future inventory items.
- `drops/`: dropped-item scene/script, drop tables, and drop-table entry resources.
- `inventory/`: save-ready inventory resources and stack/slot data.

Inventory contents should remain serializable through resources, especially `InventoryData.slots`. UI code should ask the player or inventory API to move, remove, or drop items instead of instantiating world drops directly.
