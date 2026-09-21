extends SceneTree

var _failures: Array[String] = []
var _stage: Node2D
var _navigation: TownNavigation
var _target: CharacterBody2D
var _enemies: Array[BaseNpc] = []
var _attacks: Dictionary = {}

func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if not arguments.is_empty():
		Engine.physics_ticks_per_second = int(arguments[0])
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _setup(positions: Array[Vector2]) -> void:
	_stage = Node2D.new()
	root.add_child(_stage)
	_target = CharacterBody2D.new()
	_target.collision_layer = ActorFootprint.ACTORS
	_target.collision_mask = ActorFootprint.WORLD | ActorFootprint.ACTORS
	var collider := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5
	collider.shape = circle
	_target.add_child(collider)
	_stage.add_child(_target)
	_target.add_to_group(&"navigation_test_target")
	_enemies.clear()
	_attacks.clear()
	for index: int in range(positions.size()):
		var npc: BaseNpc = load("res://game/actors/enemies/scenes/goblin.tscn").instantiate()
		npc.npc_data = npc.npc_data.duplicate()
		npc.npc_data.target_group = &"navigation_test_target"
		npc.npc_data.roam_radius = 0
		npc.npc_data.drop_table = null
		npc.position = positions[index]
		_stage.add_child(npc)
		# This scenario measures locomotion, not damage between pack members.
		npc.hurt_box.collision_mask = 0
		npc.hurt_box.collision_layer = 0
		var id: String = str(index)
		_attacks[id] = 0
		npc.state_changed.connect(func(state: StringName) -> void:
			if state == &"attack":
				_attacks[id] += 1)
		_enemies.append(npc)

func _bind_navigation() -> void:
	_navigation = TownNavigation.new()
	_navigation.area = Rect2i(-16, -16, 33, 33)
	_navigation.register("target", _target)
	for index: int in range(_enemies.size()):
		_navigation.register(str(index), _enemies[index])
	_navigation.build(_stage.get_world_2d().direct_space_state)

func _run() -> void:
	_setup([Vector2(-48, 0)])
	for frame: int in range(3):
		await physics_frame
	RegionArt.barrier(_stage, Vector2(-24, 0), Vector2(4, 40))
	await physics_frame
	_bind_navigation()
	for frame: int in range(Engine.physics_ticks_per_second * 8):
		await physics_frame
	_check(_attacks["0"] > 0, "Enemy failed to route around an intervening wall: %s" % _enemies[0].position)
	print("Obstacle route searches: ", _navigation.route_searches)
	_stage.queue_free()
	await process_frame
	_setup([Vector2(-48, 0)])
	_target.position = Vector2(80, 80)
	_enemies[0].npc_data.target_group = &"no_patrol_targets"
	RegionArt.barrier(_stage, Vector2(-24, 0), Vector2(4, 40))
	await physics_frame
	await physics_frame
	_bind_navigation()
	_enemies[0].patrol_target = Vector2.ZERO
	_enemies[0].state_machine.transition_to(&"run")
	for frame: int in range(Engine.physics_ticks_per_second * 4):
		await physics_frame
	_check(_enemies[0].position.length() <= 3, "Roaming enemy did not route around the wall")
	_stage.queue_free()
	await process_frame
	_setup([Vector2(-32, 0), Vector2(-46, 0), Vector2(-60, 0)])
	await physics_frame
	await physics_frame
	_bind_navigation()
	for frame: int in range(Engine.physics_ticks_per_second * 12):
		await physics_frame
	var attacking_members: int = 0
	for count: int in _attacks.values():
		if count > 0:
			attacking_members += 1
	_check(attacking_members >= 2, "Rear enemies never found the other attack approach: %s" % _attacks)
	for first: BaseNpc in _enemies:
		for second: BaseNpc in _enemies:
			if first != second:
				var spacing: float = ActorFootprint.radius(first) + ActorFootprint.radius(second)
				_check(first.position.distance_to(second.position) >= spacing - 0.2, "Pack members overlap")
	print("Pack attacks: ", _attacks, " positions: ", _enemies.map(func(npc: BaseNpc) -> Vector2: return npc.position))
	print("Pack route searches: ", _navigation.route_searches)
	_stage.queue_free()
	await process_frame
	print("Actor navigation failures: ", _failures)
	quit(0 if _failures.is_empty() else 1)
