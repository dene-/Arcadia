@tool
extends Node2D

## Fixed Rekala town with a deterministic surrounding region.
## Editor preview never reads or writes the player's save.
const WET_DETAILS: Array[Rect2i] = [Rect2i(8, 176, 16, 16), Rect2i(32, 176, 16, 16),
	Rect2i(56, 176, 16, 16), Rect2i(80, 176, 16, 16), Rect2i(112, 176, 16, 16)]
const DRY_DETAILS: Array[Rect2i] = [Rect2i(72, 32, 16, 32), Rect2i(88, 32, 16, 32),
	Rect2i(104, 32, 16, 32), Rect2i(120, 32, 16, 32), Rect2i(72, 64, 24, 16)]
## Ruin pieces try these offsets (pixels from the clearing centre) until one is off-road.
const RUBBLE_SPOTS: Array[Vector2] = [Vector2(30, -48), Vector2(-30, -48), Vector2(30, 56),
	Vector2(-30, 56), Vector2(56, 0), Vector2(-56, 0)]
const PILLAR_SPOTS: Array[Vector2] = [Vector2(-40, -8), Vector2(40, -8), Vector2(-24, -40),
	Vector2(24, -40), Vector2(-24, 44), Vector2(24, 44)]
@export var preview_seed: int = 274415
@export var preview_in_editor: bool = true
@export var town_life_enabled: bool = true
@export_tool_button("Rebuild region preview") var rebuild_preview: Callable = rebuild
var layout := RegionLayout.new()
var generated: Node2D

func _ready() -> void:
	if not Engine.is_editor_hint() or preview_in_editor:
		rebuild()

func rebuild() -> void:
	if is_instance_valid(generated):
		remove_child(generated)
		generated.queue_free()
	generated = Node2D.new()
	generated.name = "Region"
	generated.y_sort_enabled = true
	add_child(generated)
	y_sort_enabled = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var art := RegionArt.new()
	if not art.available():
		var warning := Label.new()
		warning.text = "World art missing. Run tools/art/import_world_packs.gd\nwith your owned Minifantasy ZIPs, then reopen Godot."
		warning.add_theme_font_size_override("font_size", 8)
		warning.position = Vector2(-110, -30)
		generated.add_child(warning)
		push_error(warning.text)
		return
	var world_seed: int = preview_seed
	if not Engine.is_editor_hint():
		var cognition: Node = get_node("/root/NpcCognition")
		if cognition.save_game.region_seed == 0:
			cognition.save_game.region_seed = randi_range(1, 2147483646)
			cognition.saves.flush(&"region_seed")
		world_seed = cognition.save_game.region_seed
	layout.generate(world_seed)
	RegionTerrain.new().build(generated, layout)
	RegionTown.new().build(generated, not Engine.is_editor_hint(), layout)
	_build_forest(art)
	_spawn_enemies()
	if not Engine.is_editor_hint():
		var navigation_world := WorldNavigation.new()
		navigation_world.name = "WorldNavigation"
		generated.add_child(navigation_world)
		if town_life_enabled:
			var buildings := TownBuildings.new()
			buildings.name = "Buildings"
			buildings.seed_value = world_seed
			generated.add_child(buildings)
			var life := TownLife.new()
			life.name = "TownLife"
			generated.add_child(life)
		var player: Node2D = get_node("BasePlayer")
		player.world_space = &"outdoors"
		player.world_space_label = "Rekala"
		player.position = RegionLayout.PLAYER_SPAWN
		player.reset_physics_interpolation()
		var camera: Camera2D = player.get_node("Camera2D")
		camera.limit_left = RegionLayout.BOUNDS.position.x * 8
		camera.limit_right = RegionLayout.BOUNDS.end.x * 8
		camera.limit_top = RegionLayout.BOUNDS.position.y * 8
		camera.limit_bottom = RegionLayout.BOUNDS.end.y * 8
		print("Rekala region: seed %s, %s trees, %s enemies" %
			[world_seed, layout.trees.size(), layout.enemies.size()])

func _build_forest(art: RegionArt) -> void:
	for tree: Dictionary in layout.trees:
		var cell: Vector2i = tree.cell
		var variation: int = absi(hash(cell))
		# Species follow the wetland's actual outline; a few dead snags break up willows.
		var prop_name: String = ["tree", "tree_fruit"][variation % 2]
		if RegionLayout.is_swamp(cell):
			prop_name = "willow"
			if variation % 7 == 0:
				prop_name = "snag" if variation % 2 == 0 else "snag_b"
		elif tree.kind < 2:
			prop_name = ["tree", "tree_fruit"][tree.kind]
		var prop: Sprite2D = art.prop(generated, prop_name, Vector2(cell * 8), variation % 2 == 1)
		# Slight tint differences keep dense stands from reading as one stamped tile.
		var shade: float = 0.92 + float(variation % 9) * 0.02
		prop.modulate = Color(shade, shade + 0.01 * float(variation % 3), shade)
	for detail: Dictionary in layout.details:
		var sheet: String = RegionArt.SWAMP if detail.wet else RegionArt.PLAINS
		var region: Rect2i = WET_DETAILS[detail.kind] if detail.wet else DRY_DETAILS[detail.kind]
		var decoration: Sprite2D = art.decoration(generated, sheet, region, Vector2(detail.cell * 8))
		decoration.flip_h = absi(hash(detail.cell)) % 2 == 1
	for item: Dictionary in layout.props:
		art.prop(generated, item.name, Vector2(item.cell * 8) + Vector2(4, 8), item.mirrored)
	for item: Dictionary in layout.cover:
		art.cover(generated, item.name, Vector2(item.cell * 8) + Vector2(4, 8), item.mirrored)
	# Stone ruins mark encounter clearings, set beside the clearing rather than on its path.
	for index: int in range(RegionLayout.CAMPS.size()):
		var camp: Vector2 = Vector2(RegionLayout.CAMPS[index] * 8)
		art.prop(generated, "rubble", camp + _off_road(camp, RUBBLE_SPOTS, Vector2i(5, 1)))
		art.prop(generated, "pillar", camp + _off_road(camp, PILLAR_SPOTS, Vector2i(1, 1)))

# The first offset whose base cells (half-extent `size`) avoid every road cell.
func _off_road(center: Vector2, offsets: Array[Vector2], size: Vector2i) -> Vector2:
	for offset: Vector2 in offsets:
		var base := Vector2i(((center + offset) / 8.0).floor())
		var clear: bool = true
		for y: int in range(-size.y - 1, 1):
			for x: int in range(-size.x, size.x + 1):
				clear = clear and not layout.roads.has(base + Vector2i(x, y))
		if clear:
			return offset
	return offsets[0]

func _spawn_enemies() -> void:
	var scenes: Array[PackedScene] = [preload("res://game/actors/enemies/scenes/goblin.tscn"),
		preload("res://game/actors/enemies/scenes/base_orc.tscn"),
		preload("res://game/actors/enemies/scenes/wild_orc.tscn")]
	var data: Array[NpcData] = [preload("res://game/resources/actors/enemies/goblin_npc_data.tres"),
		preload("res://game/resources/actors/enemies/base_orc_npc_data.tres"),
		preload("res://game/resources/actors/enemies/wild_orc_npc_data.tres")]
	var index: int = 0
	for spawn: Dictionary in layout.enemies:
		var label: String = "Enemy%02d" % index
		index += 1
		if Engine.is_editor_hint():
			RegionArt.actor_preview(generated, data[spawn.kind], Vector2(spawn.cell * 8), label)
			continue
		var npc: BaseNpc = scenes[spawn.kind].instantiate()
		npc.name = label
		npc.npc_data = npc.npc_data.duplicate()
		npc.npc_data.roam_radius = 16.0
		npc.position = Vector2(spawn.cell * 8)
		generated.add_child(npc)
