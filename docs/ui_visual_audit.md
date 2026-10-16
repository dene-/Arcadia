# UI visual audit

Audited the game's current UI and `assets/art/ui/theme.tres` on Godot 4.6.2. The game renders at 240 × 160 logical pixels. Runtime screenshots covered the HUD, interaction prompt, inventory, context menu, drag preview, dialogue, replies, chat input, and representative controls from the shared theme.

| Issue | Correction |
| --- | --- |
| Half health looked almost full; low health could look empty. The fill's horizontal slice margins totalled 72 pixels. | Separate texture slicing from content minimums so progress fills track the health ratio. Snap atlas regions to whole pixels. |
| The interaction prompt used the engine font and overlapped the health bar. | Apply the shared pixel font, a light text/shadow variation, wrapping, and spacing below the HUD. Hide interaction prompts during inventory use. |
| Runtime controls outside a themed parent could fall back to the engine theme. | Register the theme as the project default; retain explicit themes on reusable UI scenes. |
| The inventory context menu used a gray engine panel and unrelated text colors. | Theme its panel, text, disabled items, hover state, and separators. |
| Inventory slots used hardcoded rectangles; selection washed out icons and counts. | Use theme variations for slot backgrounds, a hover tint, a selection border, and contrasting counts. |
| Dragged stacks lost their inherited theme, making the count oversized. | Give the reusable slot its own theme and retain its rendered size in the drag preview. |
| Eight inventory columns left insufficient room for the vertical scrollbar. | Widen the panel, preserve the grid width, and place the panel below the health HUD. |
| Long item descriptions could grow beyond the inventory panel. | Put descriptions in a bounded scroll area and reset scrolling when the displayed item changes. |
| Reply layout could push the dialogue panel above the viewport. | Bound the reply list with a scroll container and keep focus navigation within its visible region. Long replies remain reachable by scrolling. |
| A 110-character limit did not prevent dialogue with explicit newlines or wide glyphs from clipping. | Measure pages using the visible label's font and available area. Preserve newlines and page through the remaining text. |
| Typewriter text could reflow while appearing; the continuation marker moved between pixels. | Shape complete pages before revealing characters and round the marker's animated position. Reset the reveal state for loading text. |
| Inventory could cover an active conversation. | Prevent opening it while dialogue is active. |
| Scrollbar hover/pressed states used full-size button artwork and changed their apparent thickness. | Use matching compact tracks and grabbers for all scrollbar states. |
| Buttons, text fields, tabs, separators, and slider handles had unsuitable slices, fractional coordinates, or inconsistent dimensions between states. | Correct the atlas regions and margins, share compact button styles, and give text fields a distinct focus outline. |
| Checkbox, dropdown, tab-navigation, and tree icons selected unrelated atlas symbols. | Use the correct icon cells, including mixed checkbox states and mirrored tree arrows. |
| Lists and trees had transparent backgrounds, stock selection states, or an outline replacing the selected fill. | Add parchment backgrounds and consistent selected, hovered, and focused states. |
| Enemy health bars used a separate hardcoded palette and fractional fill widths. | Read colors from the shared theme, use a contrasting border, and retain a visible pixel for living enemies with low health. |
| Inventory previews in the editor called methods on placeholder scripts. | Enable editor execution for the slot and its data resources, and keep player binding at runtime. |

Item swatches intentionally retain each item's data color: they stand in for missing item artwork. They are content, rather than panel chrome.

Validation includes script checks for every changed GDScript file, the short headless game smoke test, the project test runner, and rendered UI checks at 960 × 640 and 1280 × 720 window sizes. All 13 unique textured style boxes pass the atlas coordinate/margin checks. Editor import no longer reports inventory placeholder-script errors. Four additional pagination tests cover preserved newlines, multiline overflow, wide words, and wrapped prose; they measure actual RichTextLabel content in the scene tree.

The full suite has one existing failure: `npc_ai_test.gd::test_lateral_attack_position_respects_soft_collision_distance`. It also fails on the untouched base commit `c9d3b4a` (43/44 pass). With the UI changes and new tests, 47/48 pass. This audit does not change NPC attack positioning.

The local editor also references a missing external `C:/Users/Den/minimal_theme.tres`. That is an editor preference, separate from the game's theme.

Possible follow-ups: add a visible inventory close button/key hint and keyboard selection for inventory slots. These are usability additions; the current inventory continues to use its existing I/Tab toggle and mouse controls.

The theme and text fixes follow Godot's [theme inheritance](https://docs.godotengine.org/en/4.6/classes/class_theme.html), [text shaping](https://docs.godotengine.org/en/4.6/classes/class_textparagraph.html), and [control theme properties](https://docs.godotengine.org/en/4.6/classes/class_popupmenu.html).

## 240 × 160 polish pass (Godot 4.7)

Screenshots were captured from the real game window (canvas_items stretch, integer scale 6) with a throwaway capture script: temporary save, region seed 274415, providers offline. Before images are in `/tmp/ui_before`, after images in `/tmp/ui_after`.

| Surface | Defect | Correction |
| --- | --- | --- |
| All textured UI | The theme used `Classic_UI_Only.png`, which lacks the pack's black outline layer. Buttons showed detached side lines; panels looked softer than the outlined world sprites. | New `assets/art/ui/Classic_UI.png` composites the pack's outline layer over the colour layer, matching `Set_Use_Guidelines.png`. Every textured region and slice margin grows by the one-pixel outline. |
| Player health bar | The fill started at x = 0 and covered the frame's rounded end caps. | The fill is inset into the frame's 40 × 6 well with negative expand margins. Matching content margins keep the visible width proportional to health. The bar is 12 px tall to fit the outlined frame. |
| Clock, surrender hint | The clock had per-node colour overrides and a translucent shadow, which washed out on the plaza. The `[G] Surrender` hint was black text with a black shadow and could not be read. | Both use the new `HudTag` cream label plate (`Labels_And_Tags`). The clock has a fixed width and sits level with the health bar, so its plate does not change size each minute. |
| Interaction prompt | Bare shadowed text over the world; contrast depended on the ground behind it. | The prompt is now a `HudTag` plate. Its width fits the text and is centred on whole pixels. |
| Grave names | Black text with a black shadow, a hard-coded offset and night-tinted. | A centred `HudTag` plate on whole pixels, unshaded so the night tint does not dim it. |
| Speech bubbles | A flat dark Godot-style box with no tail, placed well above the speaker and dimmed by the night `CanvasModulate`. | Uses the `SpeechBubble` parchment box with the pack's tail. The tail points down at the speaker, or up when the bubble flips below the speaker at the top edge. The bubble is unshaded at night and sits closer to the head. |
| Dialog box | Pages were capped at 110 characters, so the box showed three lines and an empty fourth. The speaker name crowded the ornate corner and left a blank line. The next-page marker was a grey fragment of an unrelated slot. | With a measured label, pages fill the whole text area. The panel is 46 px tall, with a 4-line, 206 × 32 text area. The name is a `SpeakerTag` plate on the top border and is hidden without a speaker. The marker is the pack's red selector pointer, placed in the right-hand gutter. |
| Chat input and buttons | Button text was black, unlike the brown ink everywhere else. The focus box was a dark 1 px line drawn over the art's own outline, so it was invisible. | One dark-brown ink for `Label` and `Button`. Focus uses the pack's red selector frame, drawn one pixel outside the control. |
| Text spacing | `Label` used Godot's default 3 px line spacing, while dialog text used 0 px. Bubbles and item details therefore used an 11 px pitch and dialog an 8 px pitch. | Set `Label` line spacing to 0 for a consistent 8 px pitch. |
| Inventory | Only 3 of 4 slot rows were visible above a large empty detail area, the scrollbar was needed for 25 slots, and slots were flat Godot rectangles. The no-icon swatch was off-centre, and counts sat on the slot border. | The grid shows all 25 slots, centred. Slots, hover and selection use the pack's slot art. The swatch and counts are inset. |
| Context menu, tooltips | The scroll-page panel showed its rolled edge. | Shares the plain parchment dialog box with the speech bubbles. |

Left unchanged:

- Mouse cursor: hardware cursors are not scaled by the integer stretch, so a pack cursor would appear at 16 physical pixels.
- Overlapping bubbles from adjacent speakers: fixing this needs a coordinator across residents, which is outside a single bubble's scope.
- Enemy health bars: they are already pixel-aligned, themed and drawn above props.
- The `Zz` sleep indicator belongs to the NPC scene.

`DialogPaginator` keeps its 110-character page limit when no label is supplied. The pagination and bubble tests pass unchanged.
