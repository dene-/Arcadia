class_name TownInteriorLayout
extends RefCounted

## Authored furniture crops and trade layouts, with stable seeded domestic variation.
## Every crop contains a complete prop; feet and collision share the same anchor.
const PROPS: Dictionary = {
	"bed": [RegionArt.TOWN, Rect2i(80, 360, 16, 16), Rect2(0, 6, 16, 10)],
	"wardrobe": [RegionArt.TOWN, Rect2i(32, 240, 16, 24), Rect2(2, 16, 12, 8)],
	"cabinet": [RegionArt.TOWN, Rect2i(64, 240, 16, 24), Rect2(2, 16, 12, 8)],
	"table": [RegionArt.TOWN, Rect2i(8, 224, 16, 16), Rect2(2, 7, 12, 9)],
	"chair": [RegionArt.TOWN, Rect2i(136, 224, 16, 16), Rect2(4, 10, 8, 6)],
	"shelf": [RegionArt.TOWN, Rect2i(8, 320, 16, 16), Rect2(0, 8, 8, 8)],
	"plant": [RegionArt.TOWN, Rect2i(48, 48, 8, 16), Rect2(1, 10, 6, 6)],
	"food": [RegionArt.TOWN, Rect2i(8, 80, 24, 24), Rect2(1, 16, 22, 7)],
	"potions": [RegionArt.TOWN, Rect2i(32, 80, 24, 24), Rect2(1, 16, 22, 7)],
	"weapons": [RegionArt.TOWN, Rect2i(56, 80, 24, 24), Rect2(1, 16, 22, 7)],
	"clothes": [RegionArt.TOWN, Rect2i(80, 80, 24, 24), Rect2(1, 16, 22, 7)],
	"jewels": [RegionArt.TOWN, Rect2i(104, 88, 24, 16), Rect2(3, 8, 18, 8)],
	"hearth": [RegionArt.TOWN, Rect2i(8, 104, 24, 40), Rect2(3, 29, 18, 10)],
	"loom": ["Minifantasy_CraftingAndProfessionsTailorProps.png", Rect2i(32, 0, 32, 32), Rect2(5, 19, 21, 6)],
	"woodwork": ["Minifantasy_CraftingAndProfessionsWoodworkProps.png", Rect2i(128, 8, 32, 24), Rect2(6, 13, 22, 5)],
}
const TRADES: Dictionary = {
	"alchemist": [Vector2i(14, 10), "potions", "cabinet", 1],
	"jeweller": [Vector2i(12, 9), "jewels", "cabinet", 0],
	"tailor": [Vector2i(13, 10), "loom", "clothes", 3],
	"blacksmith": [Vector2i(16, 10), "weapons", "hearth", 4],
	"cooker": [Vector2i(16, 12), "food", "hearth", 0],
	"carpenter": [Vector2i(15, 10), "woodwork", "shelf", 0],
	"dyer": [Vector2i(12, 11), "potions", "clothes", 2],
	"butcher": [Vector2i(14, 9), "food", "shelf", 4],
	"furrier": [Vector2i(13, 9), "clothes", "cabinet", 1],
}

static func create(job: String, seed_value: int, id: String, residents: Array[String] = []) -> Dictionary:
	var trade: Array = TRADES.get(job, [Vector2i(12, 10), "table", "hearth", 0])
	if residents.size() > 1:
		return _family_layout(trade, residents)
	var size: Vector2i = trade[0]
	var floor_area := Rect2i(Vector2i(-size.x / 2, -size.y / 2), size)
	var random := NpcRoutinePlan.random_for(seed_value, id + ":interior")
	var side: float = -1 if random.randf() < 0.5 else 1
	var left: float = floor_area.position.x * 8
	var right: float = floor_area.end.x * 8
	var top: float = floor_area.position.y * 8
	var bottom: float = floor_area.end.y * 8
	var bed_x: float = left + 16 if side < 0 else right - 16
	var work_x: float = right - 24 if side < 0 else left + 24
	var bed := Vector2(bed_x, top + 24)
	var work := Vector2(work_x, top + 24)
	var meal := Vector2(bed_x - side * 16, bottom - 16)
	var table := Vector2(bed_x, bottom - 16)
	var storage := Vector2(work_x, bottom - 8)
	if job in ["carpenter", "dyer"]:
		# Front sleeping nook, with dining and work at the rear of the house.
		bed.y = bottom - 8
		table.y = top + 24
		meal.y = table.y
	elif job in ["tailor", "furrier"]:
		# Front sales counter and a rear storage/sleeping area.
		work.y = bottom - 16
		storage.y = top + 16
	var props: Array[Dictionary] = [
		{"kind": "bed", "foot": bed},
		{"kind": "wardrobe", "foot": Vector2(bed_x, top + 4)},
		{"kind": trade[1], "foot": work},
		{"kind": "table", "foot": table},
		{"kind": "chair", "foot": table + Vector2(0, 14)},
		{"kind": trade[2], "foot": storage},
	]
	if job in ["alchemist", "cooker", "dyer"]:
		props.append({"kind": "plant", "foot": Vector2(work_x - side * 8, top + 2)})
	if job == "cooker":
		props.append({"kind": "table", "foot": Vector2(0, top + 24)})
	return {"floor": floor_area, "props": props, "bed": bed, "work": work + Vector2(0, 8),
		"meal": meal, "rug": int(trade[3]), "door_x": 0.0}

static func _family_layout(trade: Array, residents: Array[String]) -> Dictionary:
	var columns: int = mini(3, residents.size())
	var size := Vector2i(12 + columns * 3, 14 if residents.size() > 3 else 11)
	var floor_area := Rect2i(Vector2i(-size.x / 2, -size.y / 2), size)
	var left: float = floor_area.position.x * 8
	var right: float = floor_area.end.x * 8
	var top: float = floor_area.position.y * 8
	var bottom: float = floor_area.end.y * 8
	var beds: Dictionary = {}
	var props: Array[Dictionary] = []
	for index: int in range(residents.size()):
		var foot := Vector2(right - 16 - (index % columns) * 24, top + 24 + (index / columns) * 32)
		beds[residents[index]] = foot
		props.append({"kind": "bed", "foot": foot})
	var work := Vector2(left + 24, top + 24)
	var table := Vector2(left + 40, bottom - 24)
	props.append_array([{"kind": trade[1], "foot": work},
		{"kind": trade[2], "foot": Vector2(left + 20, bottom - 8)},
		{"kind": "table", "foot": table},
		{"kind": "table", "foot": table + Vector2(16, 0)},
		{"kind": "wardrobe", "foot": Vector2(left + 16, top + 4)}])
	return {"floor": floor_area, "props": props, "beds": beds,
		"bed": beds[residents[0]], "work": work + Vector2(0, 8),
		"meal": table + Vector2(8, 12), "rug": int(trade[3]), "door_x": 0.0}
