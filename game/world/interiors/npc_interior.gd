class_name NpcInterior
extends Node2D

## One furnished room with its own local navigation domain, kept alive while offscreen.
const SHEET: String = "Minifantasy_TownsIIStuccoBuildingIndoorTileset.png"
const FLOOR := Rect2i(-10, -6, 20, 13)
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
	y_sort_enabled = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var backdrop := Polygon2D.new()
	backdrop.polygon = PackedVector2Array([Vector2(-256, -200), Vector2(256, -200),
		Vector2(256, 200), Vector2(-256, 200)])
	backdrop.color = Color(0.045, 0.035, 0.03)
	backdrop.z_index = -20
	add_child(backdrop)
	_build_tiles()
	RegionArt.barrier(self, Vector2(0, -56), Vector2(176, 16))
	RegionArt.barrier(self, Vector2(-84, 4), Vector2(8, 136))
	RegionArt.barrier(self, Vector2(84, 4), Vector2(8, 136))
	RegionArt.barrier(self, Vector2(0, 64), Vector2(176, 16))
	_furnish()
	entrance = global_position + Vector2(0, 40)
	navigation.area = Rect2i(Vector2i(global_position / 8) + Vector2i(-11, -8), Vector2i(22, 17))
	door = BuildingDoor.new()
	door.name = "Exit"
	door.label = "Leave " + resident_name + "'s shop"
	door.position = Vector2(0, 48)
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
	for y: int in range(FLOOR.position.y, FLOOR.end.y):
		for x: int in range(FLOOR.position.x, FLOOR.end.x):
			layer.set_cell(Vector2i(x, y), 1, Vector2i(2 + posmod(x, 2), 9))
	for x: int in range(-11, 11):
		var atlas_x: int = 4 if x == -11 else (6 if x == 10 else 5)
		for row: int in range(2):
			_tile(layer, source, Vector2i(x, -8 + row), Vector2i(atlas_x, 1 + row))
			_tile(layer, source, Vector2i(x, 7 + row), Vector2i(atlas_x, 4 + row))
	for y: int in range(-6, 7):
		_tile(layer, source, Vector2i(-11, y), Vector2i(4, 8))
		_tile(layer, source, Vector2i(10, y), Vector2i(6, 8))
	# Door and windows occupy separate art above the structural wall tiles.
	_decal(Rect2i(16, 160, 24, 16), Vector2(-12, 56))
	_decal(Rect2i(24, 136, 16, 16), Vector2(-48, -64))
	_decal(Rect2i(40, 136, 16, 16), Vector2(40, -64))

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
	var random := NpcRoutinePlan.random_for(seed_value, resident_id + ":interior")
	var side: float = -1.0 if random.randf() < 0.5 else 1.0
	var bed: Vector2 = Vector2(side * 56, -24)
	art.sprite(self, RegionArt.TOWN, Rect2i(80, 360, 16, 16), bed, Rect2(0, 6, 16, 10))
	bed_spot = global_position + bed + Vector2(0, 16)
	art.sprite(self, RegionArt.TOWN, Rect2i(40, 240, 16, 24), Vector2(side * 56, -40), Rect2(0, 16, 16, 8))
	art.sprite(self, RegionArt.TOWN, Rect2i(8, 224, 16, 16), Vector2(side * 48, 32), Rect2(0, 7, 16, 9))
	meal_spot = global_position + Vector2(side * 40, 40)
	art.sprite(self, RegionArt.TOWN, Rect2i(144, 224, 8, 16), Vector2(side * 64, 32), Rect2(0, 9, 8, 7))
	art.sprite(self, RegionArt.TOWN, Rect2i(72, 224, 16, 16), Vector2(-side * 48, 16), Rect2(0, 7, 16, 9))
	art.sprite(self, RegionArt.TOWN, Rect2i(32, 320, 16, 16), Vector2(-side * 64, -40), Rect2(0, 8, 16, 8))
	art.sprite(self, RegionArt.TOWN, Rect2i(48, 48, 8, 16), Vector2(side * 72, 48), Rect2(1, 10, 6, 6))
	var counter := Rect2i(32, 88, 24, 16)
	if job in ["blacksmith", "carpenter"]:
		counter = Rect2i(56, 88, 24, 16)
	elif job in ["tailor", "dyer", "furrier"]:
		counter = Rect2i(80, 88, 24, 16)
	elif job in ["butcher", "cooker"]:
		counter = Rect2i(8, 88, 24, 16)
	art.sprite(self, RegionArt.TOWN, counter, Vector2(-side * 40, -24), Rect2(1, 8, 22, 7))
	work_spot = global_position + Vector2(-side * 40, -8)
