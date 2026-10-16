class_name NpcInterior
extends Node2D

## One furnished room with its own local navigation domain, kept alive while offscreen. A home
## lists its residents; a public room (the schoolhouse) has none and offers named seats instead.
## Wall styles: [sheet, wall corner column, side-wall row, partition doorway tiles (left cap,
## beam, right cap, left face, right face), thin wall tiles (top, middle, end face, end base),
## exterior door decals [region, offset from the door foot], back-wall window regions].
const STYLES: Dictionary = {
	"stucco": {"sheet": "Minifantasy_TownsIIStuccoBuildingIndoorTileset.png", "column": 4,
		"side_row": 8,
		"arch": [Vector2i(4, 11), Vector2i(5, 11), Vector2i(6, 11), Vector2i(4, 12), Vector2i(6, 12)],
		"post": [Vector2i(10, 5), Vector2i(10, 6), Vector2i(10, 7), Vector2i(10, 8)],
		"door": [[Rect2i(16, 160, 24, 16), Vector2(-12, 0)]],
		"windows": [Rect2i(24, 136, 8, 16), Rect2i(40, 136, 8, 16), Rect2i(56, 136, 8, 16),
			Rect2i(64, 136, 8, 16)]},
	"plank": {"sheet": "Minifantasy_TownsIIWoodenPlankBuildingIndoorTileset.png", "column": 3,
		"side_row": 8,
		"arch": [Vector2i(3, 20), Vector2i(4, 20), Vector2i(5, 20), Vector2i(3, 21), Vector2i(5, 21)],
		"post": [Vector2i(8, 6), Vector2i(8, 6), Vector2i(8, 6), Vector2i(8, 7)],
		"door": [[Rect2i(24, 208, 24, 16), Vector2(-12, 0)], [Rect2i(32, 240, 8, 8), Vector2(-4, 8)]],
		"windows": [Rect2i(24, 184, 8, 16)]},
}
## Towns tileset floor cells; several cells alternate by column.
const FLOORS: Dictionary = {
	"planks": [Vector2i(2, 9), Vector2i(3, 9)],
	"boards": [Vector2i(1, 10), Vector2i(2, 10), Vector2i(3, 10), Vector2i(4, 10)],
	"parquet": [Vector2i(37, 2)],
	"oak": [Vector2i(38, 2)],
	"cobble": [Vector2i(5, 1), Vector2i(6, 1), Vector2i(7, 1)],
	"earth": [Vector2i(2, 1)],
}
var layout: Dictionary
var floor_area: Rect2i
var bed_center: Vector2
var player_entrance: Vector2
## The household founder (or a home's own id); a public room's building id.
var resident_id: String
## Household order: the founder, then elders first. Empty for public rooms.
var residents: Array[String] = []
var resident_name: String
var job: String
var seed_value: int
var outside: Vector2
## The world space id of this room (`home:<founder>` or a public building id).
var space: StringName
## Where actors inside are, for dialogue context, and the exit door prompt.
var space_label: String
var exit_label: String = "Leave house"
var navigation := TownNavigation.new()
var door: BuildingDoor
var bed_spot: Vector2
var work_spot: Vector2
var meal_spot: Vector2
var entrance: Vector2

func _ready() -> void:
	layout = TownInteriorLayout.create(job, seed_value, resident_id, residents)
	floor_area = layout.floor
	y_sort_enabled = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var backdrop := Polygon2D.new()
	backdrop.polygon = PackedVector2Array([Vector2(-256, -200), Vector2(256, -200),
		Vector2(256, 200), Vector2(-256, 200)])
	backdrop.color = Color(0.045, 0.035, 0.03)
	backdrop.z_index = -20
	add_child(backdrop)
	_build_tiles()
	var bounds := Rect2(Vector2(floor_area.position) * 8, Vector2(floor_area.size) * 8)
	RegionArt.barrier(self, Vector2(bounds.get_center().x, bounds.position.y - 8), Vector2(bounds.size.x + 16, 16))
	RegionArt.barrier(self, Vector2(bounds.position.x - 4, bounds.get_center().y), Vector2(8, bounds.size.y + 32))
	RegionArt.barrier(self, Vector2(bounds.end.x + 4, bounds.get_center().y), Vector2(8, bounds.size.y + 32))
	RegionArt.barrier(self, Vector2(bounds.get_center().x, bounds.end.y + 8), Vector2(bounds.size.x + 16, 16))
	for wall: Rect2 in TownInteriorLayout.partition_rects(layout):
		RegionArt.barrier(self, wall.get_center(), wall.size).name = "Partition"
	_furnish()
	entrance = global_position + Vector2(layout.door_x, bounds.end.y - 8)
	player_entrance = global_position + Vector2(layout.door_x, bounds.end.y - 5)
	work_spot = global_position + Vector2(layout.work)
	meal_spot = global_position + Vector2(layout.meal)
	var bed: Vector2 = layout.get("bed", layout.work)
	bed_spot = global_position + bed + Vector2(0, 8)
	bed_center = global_position + bed + Vector2(-1, -6)
	navigation.area = Rect2i(Vector2i(global_position / 8) + floor_area.position - Vector2i(1, 2),
		floor_area.size + Vector2i(2, 4))
	door = BuildingDoor.new()
	door.name = "Exit"
	door.label = exit_label
	door.position = Vector2(layout.door_x, bounds.end.y - 2)
	door.facing = -1
	add_child(door)

func _build_tiles() -> void:
	var style: Dictionary = STYLES[layout.wall]
	var source := TileSetAtlasSource.new()
	source.texture = load(RegionArt.ROOT + String(style.sheet))
	source.texture_region_size = Vector2i(8, 8)
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(8, 8)
	tiles.add_source(source, 0)
	var floor_source := TileSetAtlasSource.new()
	floor_source.texture = preload("res://assets/art/tilesets/towns/Minifantasy_TownsTileset.png")
	floor_source.texture_region_size = Vector2i(8, 8)
	tiles.add_source(floor_source, 1)
	var floor_layer := TileMapLayer.new()
	floor_layer.name = "Floor"
	floor_layer.tile_set = tiles
	floor_layer.z_index = -6
	add_child(floor_layer)
	# Walls draw over the floor, which shows through doorways and thin partitions.
	var layer := TileMapLayer.new()
	layer.name = "Walls"
	layer.tile_set = tiles
	layer.z_index = -5
	add_child(layer)
	for zone: Array in layout.floors:
		var cells: Array = FLOORS[zone[1]]
		var rect: Rect2i = zone[0]
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				var atlas: Vector2i = cells[posmod(x, cells.size())]
				if not floor_source.has_tile(atlas):
					floor_source.create_tile(atlas)
				floor_layer.set_cell(Vector2i(x, y), 1, atlas)
	var column: int = style.column
	for x: int in range(floor_area.position.x - 1, floor_area.end.x + 1):
		var atlas_x: int = column if x < floor_area.position.x \
			else (column + 2 if x == floor_area.end.x else column + 1)
		for row: int in range(2):
			_tile(layer, source, Vector2i(x, floor_area.position.y - 2 + row), Vector2i(atlas_x, 1 + row))
			_tile(layer, source, Vector2i(x, floor_area.end.y + row), Vector2i(atlas_x, 4 + row))
	for y: int in range(floor_area.position.y, floor_area.end.y):
		_tile(layer, source, Vector2i(floor_area.position.x - 1, y), Vector2i(column, style.side_row))
		_tile(layer, source, Vector2i(floor_area.end.x, y), Vector2i(column + 2, style.side_row))
	_build_partitions(layer, source, style)
	for decal: Array in style.door:
		_decal(style.sheet, decal[0], Vector2(layout.door_x, floor_area.end.y * 8) + decal[1])
	var windows: Array = style.windows
	for window: Array in layout.windows:
		_decal(style.sheet, windows[int(window[1]) % windows.size()],
			Vector2(window[0], floor_area.position.y * 8 - 16))

# Horizontal partitions repeat the back wall's middle tiles and open an arch at the doorway;
# vertical ones are thin walls that end in a face where they stop inside the room.
func _build_partitions(layer: TileMapLayer, source: TileSetAtlasSource, style: Dictionary) -> void:
	var arch: Array = style.arch
	var post: Array = style.post
	var rows: Array[int] = []
	for partition: Dictionary in layout.partitions:
		if partition.axis == "h":
			rows.append(partition.at)
	for partition: Dictionary in layout.partitions:
		var at: int = partition.at
		if partition.axis == "h":
			var gap: int = partition.get("gap", -9999)
			for x: int in range(partition["from"], partition["to"]):
				if x == gap - 1:
					_tile(layer, source, Vector2i(x, at), arch[0])
					_tile(layer, source, Vector2i(x, at + 1), arch[3])
				elif x == gap or x == gap + 1:
					_tile(layer, source, Vector2i(x, at), arch[1])
				elif x == gap + TownInteriorLayout.DOORWAY_CELLS:
					_tile(layer, source, Vector2i(x, at), arch[2])
					_tile(layer, source, Vector2i(x, at + 1), arch[4])
				else:
					_tile(layer, source, Vector2i(x, at), Vector2i(style.column + 1, 1))
					_tile(layer, source, Vector2i(x, at + 1), Vector2i(style.column + 1, 2))
			continue
		for span: Vector2i in TownInteriorLayout.partition_spans(partition):
			var exposed: bool = span.y != floor_area.end.y and not span.y in rows
			for y: int in range(span.x, span.y):
				var atlas: Vector2i = post[1]
				if exposed and y >= span.y - 2:
					atlas = post[2] if y == span.y - 2 else post[3]
				elif y == span.x:
					atlas = post[0]
				_tile(layer, source, Vector2i(at, y), atlas)

func _tile(layer: TileMapLayer, source: TileSetAtlasSource, cell: Vector2i, atlas: Vector2i) -> void:
	if not source.has_tile(atlas):
		source.create_tile(atlas)
	layer.set_cell(cell, 0, atlas)

func _decal(sheet: String, region: Rect2i, point: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = load(RegionArt.ROOT + sheet)
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.centered = false
	sprite.position = point
	sprite.z_index = -4
	add_child(sprite)

func _furnish() -> void:
	var art := RegionArt.new()
	for item: Dictionary in layout.props:
		var prop: Array = TownInteriorLayout.PROPS[item.kind]
		var sprite: Sprite2D = art.sprite(self, prop[0], prop[1], item.foot, prop[2])
		sprite.name = String(item.kind).to_pascal_case()
	for rug: Dictionary in layout.rugs:
		art.decoration(self, RegionArt.TOWN_II, TownInteriorLayout.RUG_REGIONS[rug.color],
			rug.foot).name = "Rug"
	for picture: Dictionary in layout.decor:
		var prop: Array = TownInteriorLayout.PROPS[picture.kind]
		var sprite: Sprite2D = art.sprite(self, prop[0], prop[1], picture.foot)
		sprite.name = String(picture.kind).to_pascal_case()
		sprite.z_index = -4

## A resident's own bed: the standing spot beside it, or its mattress centre.
func bed_for(id: String, center: bool = false) -> Vector2:
	var foot: Vector2 = layout.beds.get(id, layout.get("bed", layout.work))
	return global_position + foot + (Vector2(-1, -6) if center else Vector2(0, 8))

## Each housemate has an authored place at the table, a full personal space from the others.
func meal_for(id: String) -> Vector2:
	return global_position + Vector2(layout.meals.get(id, layout.meal))

## Where a household member works indoors: the founder at the trade, others at their own corner.
func work_for(id: String) -> Vector2:
	return global_position + Vector2(layout.works.get(id, layout.work))

## A public room's named places to sit or stand (school desks, tavern stools).
func seats(group: String) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for seat: Vector2 in layout.seats.get(group, []):
		result.append(global_position + seat)
	return result

## A named standing spot (the teacher's place, the tavern floor); the work spot otherwise.
func spot(spot_name: String) -> Vector2:
	return global_position + Vector2(layout.spots.get(spot_name, layout.work))
