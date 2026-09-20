class_name NpcInterior
extends Node2D

## One furnished room with its own local navigation domain, kept alive while offscreen.
const SHEET: String = "Minifantasy_TownsIIStuccoBuildingIndoorTileset.png"
var layout: Dictionary
var floor_area: Rect2i
var bed_center: Vector2
var player_entrance: Vector2
var resident_id: String
var resident_name: String
var job: String
var seed_value: int
var outside: Vector2
var navigation := TownNavigation.new()
var door: BuildingDoor
var bed_spot: Vector2
var work_spot: Vector2
var meal_spot: Vector2
var entrance: Vector2

func _ready() -> void:
	layout = TownInteriorLayout.create(job, seed_value, resident_id)
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
	_furnish()
	entrance = global_position + Vector2(layout.door_x, bounds.end.y - 8)
	player_entrance = global_position + Vector2(layout.door_x, bounds.end.y - 5)
	navigation.area = Rect2i(Vector2i(global_position / 8) + floor_area.position - Vector2i(1, 2),
		floor_area.size + Vector2i(2, 4))
	door = BuildingDoor.new()
	door.name = "Exit"
	door.label = "Leave house"
	door.position = Vector2(layout.door_x, bounds.end.y - 2)
	door.facing = -1
	add_child(door)

func _build_tiles() -> void:
	var source := TileSetAtlasSource.new()
	source.texture = load(RegionArt.ROOT + SHEET)
	source.texture_region_size = Vector2i(8, 8)
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(8, 8)
	tiles.add_source(source, 0)
	var floor_source := TileSetAtlasSource.new()
	floor_source.texture = preload("res://assets/art/tilesets/towns/Minifantasy_TownsTileset.png")
	floor_source.texture_region_size = Vector2i(8, 8)
	for atlas: Vector2i in [Vector2i(2, 9), Vector2i(3, 9)]:
		floor_source.create_tile(atlas)
	tiles.add_source(floor_source, 1)
	var layer := TileMapLayer.new()
	layer.name = "FloorAndWalls"
	layer.tile_set = tiles
	layer.z_index = -5
	add_child(layer)
	for y: int in range(floor_area.position.y, floor_area.end.y):
		for x: int in range(floor_area.position.x, floor_area.end.x):
			layer.set_cell(Vector2i(x, y), 1, Vector2i(2 + posmod(x, 2), 9))
	for x: int in range(floor_area.position.x - 1, floor_area.end.x + 1):
		var atlas_x: int = 4 if x < floor_area.position.x else (6 if x == floor_area.end.x else 5)
		for row: int in range(2):
			_tile(layer, source, Vector2i(x, floor_area.position.y - 2 + row), Vector2i(atlas_x, 1 + row))
			_tile(layer, source, Vector2i(x, floor_area.end.y + row), Vector2i(atlas_x, 4 + row))
	for y: int in range(floor_area.position.y, floor_area.end.y):
		_tile(layer, source, Vector2i(floor_area.position.x - 1, y), Vector2i(4, 8))
		_tile(layer, source, Vector2i(floor_area.end.x, y), Vector2i(6, 8))
	_decal(Rect2i(16, 160, 24, 16), Vector2(layout.door_x - 12, floor_area.end.y * 8))
	_decal(Rect2i(24, 136, 16, 16), Vector2(-16, floor_area.position.y * 8 - 16))

func _tile(layer: TileMapLayer, source: TileSetAtlasSource, cell: Vector2i, atlas: Vector2i) -> void:
	if not source.has_tile(atlas):
		source.create_tile(atlas)
	layer.set_cell(cell, 0, atlas)

func _decal(region: Rect2i, point: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = load(RegionArt.ROOT + SHEET)
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
		sprite.name = String(item.kind).capitalize()
	var rug: Sprite2D = art.decoration(self, RegionArt.TOWN_II,
		Rect2i(120, int(layout.rug) * 24, 24, 24), Vector2(0, 8))
	rug.name = "Rug"
	bed_spot = global_position + Vector2(layout.bed) + Vector2(0, 8)
	bed_center = global_position + Vector2(layout.bed) + Vector2(-1, -6)
	work_spot = global_position + Vector2(layout.work)
	meal_spot = global_position + Vector2(layout.meal)
