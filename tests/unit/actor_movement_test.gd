extends "res://tests/test_case.gd"

var _stage: Node2D
var _navigation: TownNavigation

func before_each() -> void:
	_stage = Node2D.new()
	var tree: SceneTree = Engine.get_main_loop()
	tree.root.add_child(_stage)
	_navigation = TownNavigation.new()
	_navigation.area = Rect2i(-12, -12, 25, 25)

func after_each() -> void:
	_stage.free()

func _npc(at: Vector2) -> BaseNpc:
	var npc: BaseNpc = load("res://game/actors/enemies/scenes/goblin.tscn").instantiate()
	npc.npc_data = npc.npc_data.duplicate()
	npc.npc_data.ai_enabled = false
	npc.npc_data.roam_radius = 0
	npc.position = at
	_stage.add_child(npc)
	npc.set_physics_process(false)
	return npc

func test_rounded_footprints_preserve_scene_extents_and_separate_geometry_layers() -> void:
	for size: Vector2 in [Vector2(6, 6), Vector2(10, 8), Vector2(8, 12)]:
		var actor := CharacterBody2D.new()
		var collider := CollisionShape2D.new()
		collider.name = "CollisionShape2D"
		var rectangle := RectangleShape2D.new()
		rectangle.size = size
		collider.shape = rectangle
		collider.position = Vector2(0, -1)
		actor.add_child(collider)
		_stage.add_child(actor)
		ActorFootprint.configure(actor)
		var bounds: Rect2 = Transform2D(collider.rotation, Vector2.ZERO) * collider.shape.get_rect()
		assert_true(bounds.size.is_equal_approx(size))
		assert_eq(collider.position, Vector2(0, -1))
		assert_false(collider.shape is RectangleShape2D)
		assert_eq(actor.collision_layer, ActorFootprint.ACTORS)
		assert_eq(actor.collision_mask, ActorFootprint.WORLD | ActorFootprint.ACTORS)

func test_route_reuses_progress_and_limits_searches_per_physics_frame() -> void:
	_navigation.build(_stage.get_world_2d().direct_space_state)
	var route := ActorRoute.new()
	route.navigation = _navigation
	route.id = "walker"
	var position := Vector2(-64, 0)
	route.travel(position, Vector2(64, 0))
	for tick: int in range(200):
		route.update(position, 1.0 / 60.0)
		position = position.move_toward(route.waypoint(position), 1.0)
	assert_true(position.distance_to(route.goal) <= 2.5)
	assert_eq(_navigation.route_searches, 1, "Progressing actor unnecessarily rerouted")
	for count: int in range(TownNavigation.MAX_SEARCHES_PER_FRAME - 1):
		assert_true(_navigation.take_route_budget())
	assert_false(_navigation.take_route_budget())

func test_overlapping_movers_can_choose_an_escape_direction() -> void:
	var first: BaseNpc = _npc(Vector2.ZERO)
	var second: BaseNpc = _npc(Vector2.ZERO)
	# Ready-state collision recovery may already have separated the second body.
	first.position = Vector2.ZERO
	second.position = Vector2.ZERO
	_navigation.register("a", first)
	_navigation.register("b", second)
	_navigation.build(_stage.get_world_2d().direct_space_state)
	var motion: Vector2 = _navigation.steer("a", Vector2.ZERO, Vector2(28, 0), 1.0 / 60.0)
	assert_true(motion.x < 0, "Exact overlap froze the mover instead of choosing a stable escape")

func test_landing_uses_close_free_space_and_refuses_a_fully_blocked_threshold() -> void:
	var arriving: BaseNpc = _npc(Vector2(-48, 0))
	var blocking: BaseNpc = _npc(Vector2.ZERO)
	_navigation.register("arriving", arriving)
	_navigation.register("blocking", blocking)
	await _stage.get_tree().physics_frame
	_navigation.build(_stage.get_world_2d().direct_space_state)
	var point: Vector2 = _navigation.landing(arriving, Vector2.ZERO)
	assert_ne(point, Vector2.INF)
	assert_true(point.length() <= 12 and point.length() >= 6)
	# Query the actual collider, not just whether the grid cell is walkable.
	RegionArt.barrier(_stage, Vector2.ZERO, Vector2(32, 32))
	await _stage.get_tree().physics_frame
	assert_eq(_navigation.landing(arriving, Vector2.ZERO), Vector2.INF)
	assert_eq(arriving.global_position, Vector2(-48, 0))

func test_melee_contact_respects_walls_spaces_and_one_hit_per_swing() -> void:
	var attacker: BaseNpc = _npc(Vector2(-12, 0))
	var victim: BaseNpc = _npc(Vector2.ZERO)
	victim.hurt_box.monitoring = false
	var wall: StaticBody2D = RegionArt.barrier(_stage, Vector2(-6, 0), Vector2(2, 32))
	await _stage.get_tree().physics_frame
	attacker.set_hitbox_enabled(true)
	assert_false(attacker.consume_melee_hit(victim))
	wall.queue_free()
	await _stage.get_tree().physics_frame
	await _stage.get_tree().process_frame
	# Keep physical area callbacks from consuming this deterministic assertion's hit.
	attacker.hit_box.monitorable = false
	assert_true(attacker.consume_melee_hit(victim))
	assert_false(attacker.consume_melee_hit(victim))
	attacker.set_hitbox_enabled(false)
	attacker.set_hitbox_enabled(true)
	victim.world_space = &"home:test"
	assert_false(attacker.consume_melee_hit(victim))
	victim.world_space = attacker.world_space
	assert_true(attacker.consume_melee_hit(victim))

func test_attack_approach_rejects_wall_between_slot_and_target() -> void:
	var attacker: BaseNpc = _npc(Vector2(-24, 0))
	var target: BaseNpc = _npc(Vector2.ZERO)
	RegionArt.barrier(_stage, Vector2(-6, 0), Vector2(1, 16))
	await _stage.get_tree().physics_frame
	_navigation.register("attacker", attacker)
	_navigation.build(_stage.get_world_2d().direct_space_state)
	var choice: Dictionary = _navigation.attack_destination("attacker", target, attacker.position, 12)
	assert_true(choice.attack)
	assert_true(choice.point.x > 0, "Attacker selected the approach behind a wall")
