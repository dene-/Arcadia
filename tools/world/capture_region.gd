extends SceneTree

## Renders the generated region to PNGs for visual review. Needs a display (not --headless).
## Usage: Godot --path . --script res://tools/world/capture_region.gd -- <out_dir> [zoom] [x,y ...]
## Without positions it writes an overview plus a grid covering the whole region.
## Uses an isolated temporary save; never touches the player's save or providers.
const SIZE := Vector2i(1920, 1080)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else OS.get_temp_dir().path_join("arcadia-capture")
	var zoom: float = float(args[1]) if args.size() > 1 else 2.0
	DirAccess.make_dir_recursive_absolute(out_dir)
	var cognition: Node = root.get_node("NpcCognition")
	cognition.save_game.path = OS.get_temp_dir().path_join("arcadia-capture-%s.json" % OS.get_process_id())
	cognition.save_game.region_seed = 274415
	cognition.save_game.dead_npcs.clear()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = SIZE
	var world: Node2D = load("res://game/world/scenes/world.tscn").instantiate()
	world.town_life_enabled = false
	root.add_child(world)
	current_scene = world
	world.get_node("UI").visible = false
	var player: Node2D = world.get_node("BasePlayer")
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	for frame: int in range(10):
		await process_frame
	for actor: Node in get_nodes_in_group("npc_observers") + get_nodes_in_group("enemies"):
		actor.process_mode = Node.PROCESS_MODE_DISABLED
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var bounds := Rect2(RegionLayout.BOUNDS.position * 8, RegionLayout.BOUNDS.size * 8)
	var shots: Array[Vector2] = []
	for index: int in range(2, args.size()):
		var parts: PackedStringArray = args[index].split(",")
		shots.append(Vector2(float(parts[0]), float(parts[1])))
	if shots.is_empty():
		await _shot(camera, bounds.get_center(), 0.5, out_dir.path_join("overview.png"))
		var step := Vector2(SIZE) / zoom
		var y: float = bounds.position.y + step.y * 0.5
		while y - step.y * 0.5 < bounds.end.y:
			var x: float = bounds.position.x + step.x * 0.5
			while x - step.x * 0.5 < bounds.end.x:
				shots.append(Vector2(x, y))
				x += step.x
			y += step.y
	for shot: Vector2 in shots:
		await _shot(camera, shot, zoom, out_dir.path_join("shot_%d_%d.png" % [shot.x, shot.y]))
	DirAccess.remove_absolute(cognition.save_game.path)
	quit(0)

func _shot(camera: Camera2D, center: Vector2, zoom: float, path: String) -> void:
	camera.zoom = Vector2(zoom, zoom)
	camera.global_position = center
	camera.reset_physics_interpolation()
	for frame: int in range(3):
		await process_frame
	root.get_texture().get_image().save_png(path)
	print("Captured ", path)
