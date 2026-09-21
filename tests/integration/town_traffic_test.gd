extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	var walkers: Array[BaseNpc] = []
	var bodies: Array[RID] = []
	var navigation := TownNavigation.new()
	for index: int in range(3):
		var npc: BaseNpc = load("res://game/actors/npcs/base_npc.tscn").instantiate()
		npc.npc_data = npc.npc_data.duplicate(true)
		npc.npc_data.profile = null
		npc.npc_data.ai_enabled = false
		npc.position = Vector2([-64, 64, 0][index], 0)
		stage.add_child(npc)
		walkers.append(npc)
		bodies.append(npc.get_rid())
		navigation.register(str(index), npc)
		if index == 2:
			npc.process_mode = Node.PROCESS_MODE_DISABLED
	await physics_frame
	await physics_frame
	navigation.build(stage.get_world_2d().direct_space_state, bodies)
	for index: int in range(2):
		var npc: BaseNpc = walkers[index]
		npc.daily_routine = NpcDailyRoutine.new()
		npc.daily_routine.navigation = navigation
		npc.daily_routine.npc_id = str(index)
		npc.daily_routine.travel(npc.position, -npc.position, "walk", "other side")
		npc.state_time_remaining = 0
	for frame: int in range(900):
		await physics_frame
		for index: int in range(2):
			walkers[index].daily_routine.update(walkers[index].position, 1.0 / 60.0, false)
	var failures: Array[String] = []
	for index: int in range(2):
		var npc: BaseNpc = walkers[index]
		if npc.position.distance_to(npc.daily_routine.destination) > 3:
			failures.append("Walker %d stuck at %s" % [index, npc.position])
	print("Town traffic failures: ", failures)
	stage.free()
	quit(0 if failures.is_empty() else 1)
