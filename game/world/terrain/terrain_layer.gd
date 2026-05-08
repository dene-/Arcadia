@tool
class_name TerrainLayer
extends TileMapLayer

## Procedurally fills the tile layer using seeded noise and the existing terrain set.

const TERRAIN_SET_ID: int = 0

## Width and height, in cells, generated around this layer's origin.
@export var map_size: Vector2i = Vector2i(96, 96):
	set(value):
		map_size = value
		_queue_regenerate()
## Seed used for deterministic noise and ground variation.
@export var noise_seed: int = 1337:
	set(value):
		noise_seed = value
		_queue_regenerate()
## Noise frequency used to decide where grass terrain appears.
@export_range(0.001, 1.0, 0.001) var frequency: float = 0.045:
	set(value):
		frequency = value
		_queue_regenerate()
## Noise threshold above which cells are assigned grass terrain.
@export_range(-1.0, 1.0, 0.01) var grass_threshold: float = 0.02:
	set(value):
		grass_threshold = value
		_queue_regenerate()
## Fallback atlas source id used when no weighted ground variant is found.
@export var ground_source_id: int = 1:
	set(value):
		ground_source_id = value
		_queue_regenerate()
## Fallback atlas coordinates used when no weighted ground variant is found.
@export var ground_atlas_coords: Vector2i = Vector2i(8, 1):
	set(value):
		ground_atlas_coords = value
		_queue_regenerate()
## Terrain id applied to cells selected as grass.
@export var grass_terrain_id: int = 1:
	set(value):
		grass_terrain_id = value
		_queue_regenerate()
## Allows terrain generation to run while editing the scene.
@export var generate_in_editor: bool = true:
	set(value):
		generate_in_editor = value
		_queue_regenerate()

var _noise: FastNoiseLite
var _observed_tile_set: TileSet
var _ground_variants: Array[Dictionary] = []
var _ground_total_weight: float = 0.0
var _ground_variants_dirty: bool = true
var _regenerate_queued: bool = false
var _is_generating: bool = false

const TERRAIN_BIT_NAMES: Array[String] = [
	"right_side",
	"bottom_right_corner",
	"bottom_side",
	"bottom_left_corner",
	"left_side",
	"top_left_corner",
	"top_side",
	"top_right_corner"
]

func _enter_tree() -> void:
	_connect_tile_set_changed()

func _exit_tree() -> void:
	_disconnect_tile_set_changed()

func _ready() -> void:
	_connect_tile_set_changed()
	_ground_variants_dirty = true

	if Engine.is_editor_hint() and not generate_in_editor:
		return

	generate()

func generate() -> void:
	if _is_generating:
		return

	if Engine.is_editor_hint() and not generate_in_editor:
		return

	_regenerate_queued = false
	_is_generating = true
	_connect_tile_set_changed()
	_ensure_noise()
	_ensure_ground_variants()
	clear()

	var grass_cells: Array[Vector2i] = []
	var half_size := Vector2i(
		int(floorf(float(map_size.x) * 0.5)),
		int(floorf(float(map_size.y) * 0.5))
	)

	for y: int in range(map_size.y):
		for x: int in range(map_size.x):
			var cell := Vector2i(x - half_size.x, y - half_size.y)
			_apply_ground_tile(cell)
			var sample: float = _noise.get_noise_2d(cell.x, cell.y)
			if sample >= grass_threshold:
				grass_cells.append(cell)

	if not grass_cells.is_empty():
		set_cells_terrain_connect(grass_cells, TERRAIN_SET_ID, grass_terrain_id, true)

	update_internals()

	_is_generating = false

func _queue_regenerate() -> void:
	if not is_inside_tree():
		return

	if Engine.is_editor_hint() and not generate_in_editor:
		return

	if _regenerate_queued:
		return

	_regenerate_queued = true
	call_deferred("_deferred_generate")

func _deferred_generate() -> void:
	if not is_inside_tree():
		_regenerate_queued = false
		return

	generate()

func _ensure_noise() -> void:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.fractal_octaves = 3
		_noise.fractal_gain = 0.5
		_noise.fractal_lacunarity = 2.0

	_noise.seed = noise_seed
	_noise.frequency = frequency

func _connect_tile_set_changed() -> void:
	if tile_set == _observed_tile_set:
		return

	_disconnect_tile_set_changed()
	_observed_tile_set = tile_set

	if _observed_tile_set != null and not _observed_tile_set.changed.is_connected(_on_tile_set_changed):
		_observed_tile_set.changed.connect(_on_tile_set_changed)

func _disconnect_tile_set_changed() -> void:
	if _observed_tile_set != null and _observed_tile_set.changed.is_connected(_on_tile_set_changed):
		_observed_tile_set.changed.disconnect(_on_tile_set_changed)

	_observed_tile_set = null

func _on_tile_set_changed() -> void:
	_ground_variants_dirty = true
	_queue_regenerate()
	update_internals()

func _ensure_ground_variants() -> void:
	if not _ground_variants_dirty:
		return

	_ground_variants.clear()
	_ground_total_weight = 0.0
	_ground_variants_dirty = false

	if tile_set == null:
		return

	for source_index: int in range(tile_set.get_source_count()):
		var source_id := tile_set.get_source_id(source_index)
		var source := tile_set.get_source(source_id)
		if source == null or not source is TileSetAtlasSource:
			continue

		var atlas_source: TileSetAtlasSource = source
		for tile_index: int in range(atlas_source.get_tiles_count()):
			var atlas_coords: Vector2i = atlas_source.get_tile_id(tile_index)
			for alternative_index: int in range(atlas_source.get_alternative_tiles_count(atlas_coords)):
				var alternative_id := atlas_source.get_alternative_tile_id(atlas_coords, alternative_index)
				if not _is_pure_ground_variant(atlas_source, atlas_coords, alternative_id):
					continue

				var probability := float(atlas_source.get("%d:%d/%d/probability" % [atlas_coords.x, atlas_coords.y, alternative_id]))
				var weight := maxf(probability, 0.001)
				_ground_total_weight += weight
				_ground_variants.append({
					"source_id": source_id,
					"atlas_coords": atlas_coords,
					"alternative_id": alternative_id,
					"weight": weight,
					"threshold": _ground_total_weight,
				})

func _is_pure_ground_variant(
		atlas_source: TileSetAtlasSource,
		atlas_coords: Vector2i,
		alternative_id: int
	) -> bool:
	var base_path := "%d:%d/%d/" % [atlas_coords.x, atlas_coords.y, alternative_id]
	if int(atlas_source.get(base_path + "terrain_set")) != TERRAIN_SET_ID:
		return false

	if int(atlas_source.get(base_path + "terrain")) != 0:
		return false

	for bit_name: String in TERRAIN_BIT_NAMES:
		if int(atlas_source.get(base_path + "terrains_peering_bit/" + bit_name)) != 0:
			return false

	return true

func _apply_ground_tile(cell: Vector2i) -> void:
	var selected_variant := _pick_ground_variant(cell)
	if selected_variant.is_empty():
		set_cell(cell, ground_source_id, ground_atlas_coords)
		return

	set_cell(
		cell,
		int(selected_variant["source_id"]),
		selected_variant["atlas_coords"],
		int(selected_variant["alternative_id"])
	)

func _pick_ground_variant(cell: Vector2i) -> Dictionary:
	if _ground_variants.is_empty() or _ground_total_weight <= 0.0:
		return {}

	var sample := _cell_sample(cell) * _ground_total_weight
	for variant: Dictionary in _ground_variants:
		if sample <= float(variant["threshold"]):
			return variant

	return _ground_variants.back()

func _cell_sample(cell: Vector2i) -> float:
	var value := hash([noise_seed, cell.x, cell.y, "ground"])
	return float(abs(value % 1000000)) / 1000000.0
