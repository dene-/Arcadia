# UI

Runtime UI scenes and scripts live here.

- `hud/`: in-game HUD controls such as health bars.
- `inventory/`: inventory panel, slot template, and item interaction UI.
- `dialog/`: dialog autoload scene and helper classes.
- `widgets/`: reusable UI pieces that are not tied to one feature.

Use the project theme at `res://assets/art/ui/theme.tres` where possible. Avoid font-size overrides unless a specific UI requirement needs them.

The theme is registered as `gui/theme/custom` so detached controls and popups inherit it. Reuse the `InventorySlotBackground`, `InventorySlotHover`, `InventorySlotSelection`, `InventoryCount`, `HudTag` (HUD and world name/prompt tags), `SpeakerTag` (dialog name plate), and `SpeechBubble` variations instead of local color overrides. World-space enemy health colors live in the theme's `EnemyHealthBar` palette.

Textured styles use `assets/art/ui/Classic_UI.png`: the pack's `Classic_UI_Only.png` with `Classic_UI_Outline.png` composited on top, matching `Set_Use_Guidelines.png`. Regions include the one-pixel outline. Text sits at the Bitty font's native 16 px size on whole-pixel positions.

See the [UI visual audit](../../docs/ui_visual_audit.md) for corrected theme issues and validation notes.
