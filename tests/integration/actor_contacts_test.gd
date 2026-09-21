extends SceneTree

var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check_player_courtesy(running: bool) -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	var player: BasePlayer = load("res://game/actors/player/base_player.tscn").instantiate()
	player.player_data = player.player_data.duplicate()
	player.position = Vector2(-40, 0)
	stage.add_child(player)
	var resident: BaseNpc = load("res://game/actors/npcs/base_npc.tscn").instantiate()
	resident.npc_data = resident.npc_data.duplicate()
	resident.npc_data.profile = null
	resident.npc_data.roam_radius = 0
	stage.add_child(resident)
	await physics_frame
	await physics_frame
	var navigation := TownNavigation.new()
	navigation.area = Rect2i(-20, -10, 41, 21)
	navigation.register("player", player)
	navigation.register("resident", resident)
	navigation.build(stage.get_world_2d().direct_space_state)
	Input.action_press(&"player_right")
	if running:
		Input.action_press(&"player_run")
	for frame: int in range(120):
		await physics_frame
	Input.action_release(&"player_right")
	Input.action_release(&"player_run")
	if player.position.x < (60 if running else 20):
		_failures.append("Idle resident did not yield to the player: player=%s resident=%s" % [player.position, resident.position])
	print("Courtesy positions: ", player.position, " / ", resident.position)
	print("Courtesy navigation: ", navigation.metrics())
	stage.queue_free()
	await process_frame

func _run() -> void:
	await _check_player_courtesy(false)
	await _check_player_courtesy(true)
	# A narrow corridor with a passing bay must allow opposing walkers through.
	var stage := Node2D.new()
	root.add_child(stage)
	for x: float in [-40, 40]:
		for y: float in [-7, 7]:
			RegionArt.barrier(stage, Vector2(x, y), Vector2(48, 2))
	var walkers: Array[BaseNpc] = []
	var navigation := TownNavigation.new()
	navigation.area = Rect2i(-12, -8, 25, 17)
	for index: int in range(2):
		var npc: BaseNpc = load("res://game/actors/npcs/base_npc.tscn").instantiate()
		npc.npc_data = npc.npc_data.duplicate()
		npc.npc_data.profile = null
		npc.npc_data.roam_radius = 0
		npc.position = Vector2(-56 if index == 0 else 56, 0)
		stage.add_child(npc)
		navigation.register(str(index), npc)
		walkers.append(npc)
	await physics_frame
	await physics_frame
	navigation.build(stage.get_world_2d().direct_space_state)
	for index: int in range(2):
		var npc: BaseNpc = walkers[index]
		npc.daily_routine = NpcDailyRoutine.new()
		npc.daily_routine.navigation = navigation
		npc.daily_routine.npc_id = str(index)
		npc.daily_routine.travel(npc.position, -npc.position, "walk", "other end")
		npc.state_time_remaining = 0
	for frame: int in range(1200):
		await physics_frame
		for npc: BaseNpc in walkers:
			npc.daily_routine.update(npc.position, 1.0 / 60.0, false)
	for npc: BaseNpc in walkers:
		if npc.position.distance_to(npc.daily_routine.destination) > 3:
			_failures.append("Corridor walker stuck: %s toward %s" % [npc.position, npc.daily_routine.destination])
	print("Corridor navigation: ", navigation.metrics())
	print("Actor contact failures: ", _failures)
	stage.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)
