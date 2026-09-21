extends SceneTree

## Real player movement plus rendered frame comparisons. No world saves or providers.
## Run with --fixed-fps 60; omit --headless to check rendering and interpolation.
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node2D.new()
	world.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(world)
	current_scene = world
	var player: BasePlayer = load("res://game/actors/player/base_player.tscn").instantiate()
	world.add_child(player)
	await _check_movement(player)
	player.set_physics_process(false)
	player.animated_sprite.hide()
	if DisplayServer.get_name() != "headless":
		_build_static_scene(world)
		await _check_rendering(player)
		await _check_interpolation(player)
	else:
		print("Pixel frame comparisons require a rendered run; movement checked headlessly.")
	print("Pixel camera failures: ", _failures)
	world.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)

func _check_movement(player: BasePlayer) -> void:
	var distances: Array[float] = []
	for actions: Array in [["player_right"], ["player_down"], ["player_right", "player_down"]]:
		player.position = Vector2.ZERO
		for action: String in actions:
			Input.action_press(action)
		player.state_machine.transition_to(&"walk", {}, true)
		for frame: int in range(60):
			await physics_frame
		await process_frame
		distances.append(player.position.length())
		for action: String in actions:
			Input.action_release(action)
		player.state_machine.transition_to(&"idle", {}, true)
	var expected: float = player.current_walk_speed() * 60.0 / Engine.physics_ticks_per_second
	for distance: float in distances:
		if absf(distance - expected) > 0.02:
			_failures.append("Direction changes travel speed: %s vs %s" % [distance, expected])
	print("Cardinal/diagonal distances: ", distances)

func _build_static_scene(world: Node2D) -> void:
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(8, 8)
	var source := TileSetAtlasSource.new()
	source.texture = load("res://assets/art/tilesets/towns/Minifantasy_TownsTileset.png")
	source.texture_region_size = Vector2i(8, 8)
	for x: int in [2, 3]:
		source.create_tile(Vector2i(x, 9))
	tiles.add_source(source, 0)
	var floor_layer := TileMapLayer.new()
	floor_layer.tile_set = tiles
	world.add_child(floor_layer)
	for y: int in range(-20, 20):
		for x: int in range(-20, 20):
			floor_layer.set_cell(Vector2i(x, y), 0, Vector2i(2 + posmod(x, 2), 9))
	var art := RegionArt.new()
	# The furnace's 17px collision footprint previously introduced a half-pixel art origin.
	art.sprite(world, "Minifantasy_CraftingAndProfessionsBlacksmithProps.png",
		Rect2i(40, 0, 24, 32), Vector2(-32, 0), Rect2(0, 24, 17, 6))
	art.sprite(world, RegionArt.TOWN_II, Rect2i(8, 8, 24, 8),
		Vector2(16, 0), Rect2(1, 5, 22, 3))
	var label := Label.new()
	label.theme = load("res://assets/art/ui/theme.tres")
	label.text = "Den's shop"
	label.position = Vector2(-30, 20)
	world.add_child(label)

func _check_rendering(player: BasePlayer) -> void:
	var camera: Camera2D = player.get_node("Camera2D")
	var native_frame: Image
	for scale: int in [1, 3, 6]:
		root.size = Vector2i(240, 160) * scale
		await process_frame
		var reference: Image = await _capture_at(player, Vector2.ZERO)
		if reference.get_size() != root.size:
			_failures.append("The world is not rendered at display resolution")
			return
		if scale == 1:
			native_frame = reference
		else:
			var enlarged: Image = native_frame.duplicate()
			enlarged.resize(root.size.x, root.size.y, Image.INTERPOLATE_NEAREST)
			if reference.get_data() != enlarged.get_data():
				_failures.append("Art or theme font blurred at %dx scale" % scale)
		var origin: Vector2 = root.canvas_transform.origin
		var sample := Rect2i(Vector2i(16, 16) * scale, Vector2i(200, 120) * scale)
		for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.ONE, -Vector2.ONE,
			Vector2(1, -1), Vector2(-1, 1)]:
			for index: int in range(1, 16):
				var point: Vector2 = direction * index * 0.25
				var frame: Image = await _capture_at(player, point)
				var rendered_shift: Vector2 = (origin - root.canvas_transform.origin) * scale
				if rendered_shift.distance_to(rendered_shift.round()) > 0.001:
					_failures.append("Camera origin is not aligned to display pixels")
				if (rendered_shift - point * scale).abs().x > 0.51 \
					or (rendered_shift - point * scale).abs().y > 0.51:
					_failures.append("Camera still steps in coarse game pixels")
				var shifted := Rect2i(sample.position + Vector2i(rendered_shift.round()), sample.size)
				if frame.get_region(sample).get_data() != reference.get_region(shifted).get_data():
					_failures.append("Scenery or font wobbled at %s, scale %d" % [point, scale])
					break
	# Door teleports and camera limits must still take effect immediately.
	camera.limit_left = 3976
	camera.limit_right = 4216
	camera.limit_top = 4016
	camera.limit_bottom = 4176
	await _capture_at(player, Vector2(4112, 4104))
	if camera.get_screen_center_position().distance_to(Vector2(4096, 4096)) > 0.01:
		_failures.append("Camera limits or teleport reset regressed")
	camera.limit_left = -10000000
	camera.limit_right = 10000000
	camera.limit_top = -10000000
	camera.limit_bottom = 10000000

func _capture_at(player: BasePlayer, point: Vector2) -> Image:
	player.position = point
	player.reset_physics_interpolation()
	var camera: Camera2D = player.get_node("Camera2D")
	camera.force_update_scroll()
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _check_interpolation(player: BasePlayer) -> void:
	# Exaggerate the physics/render mismatch: camera movement must continue between ticks.
	var marker := ColorRect.new()
	marker.color = Color.MAGENTA
	marker.size = Vector2.ONE
	marker.z_index = 100
	player.add_child(marker)
	var original_tick_rate: int = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 10
	await _capture_at(player, Vector2(0.23, 32.81))
	player.set_physics_process(true)
	Input.action_press("player_right")
	Input.action_press("player_down")
	player.state_machine.transition_to(&"walk", {}, true)
	await physics_frame
	await physics_frame
	var previous: Vector2 = root.canvas_transform.origin
	var moving_frames: int = 0
	var largest_step: float = 0
	var marker_drift: bool = false
	for frame: int in range(60):
		await process_frame
		await RenderingServer.frame_post_draw
		var step: Vector2 = (previous - root.canvas_transform.origin) * 6.0
		if step.length() > 0.01:
			moving_frames += 1
		largest_step = maxf(largest_step, step.length())
		previous = root.canvas_transform.origin
		# The followed actor must remain centered while both actor and camera interpolate.
		var frame_image: Image = root.get_texture().get_image()
		var marker_pixels: int = 0
		for y: int in range(479, 487):
			for x: int in range(719, 727):
				if frame_image.get_pixel(x, y).is_equal_approx(Color.MAGENTA):
					marker_pixels += 1
		marker_drift = marker_drift or marker_pixels != 36
	Input.action_release("player_right")
	Input.action_release("player_down")
	player.set_physics_process(false)
	Engine.physics_ticks_per_second = original_tick_rate
	print("Interpolated diagonal motion: %d moving frames, maximum step %.2fpx" %
		[moving_frames, largest_step])
	if moving_frames < 30 or largest_step > 8.0:
		_failures.append("Camera motion stalled or jumped between physics ticks")
	if marker_drift:
		_failures.append("The followed actor jittered relative to the camera")
	marker.queue_free()
