# UI

Runtime UI scenes and scripts live here.

- `hud/`: in-game HUD controls such as health bars.
- `inventory/`: inventory panel, slot template, and item interaction UI.
- `dialog/`: dialog autoload scene and helper classes.
- `widgets/`: reusable UI pieces that are not tied to one feature.

Use the project theme at `res://assets/art/ui/theme.tres` where possible. Avoid font-size overrides unless a specific UI requirement needs them.

The theme is registered as `gui/theme/custom` so detached controls and popups inherit it. Reuse the `InventorySlotBackground`, `InventorySlotHover`, `InventorySlotSelection`, `InventoryCount`, and `InteractionPrompt` variations instead of local color overrides. World-space enemy health colors live in the theme's `EnemyHealthBar` palette.

See the [UI visual audit](../../docs/ui_visual_audit.md) for corrected theme issues and validation notes.
