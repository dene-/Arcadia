extends "res://tests/test_case.gd"

var _scene: Node2D
var _actor: CharacterBody2D
var _navigation: TownNavigation

func before_each() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	_scene = Node2D.new()
	tree.root.add_child(_scene)
	_actor = CharacterBody2D.new()
	_actor.position = Vector2(16, 0)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(10, 8)
	shape.shape = rectangle
	_actor.add_child(shape)
	_scene.add_child(_actor)
	_navigation = TownNavigation.new()

func after_each() -> void:
	_scene.free()

func test_moving_actors_are_not_baked_and_live_routes_detour_around_them() -> void:
	await _scene.get_tree().physics_frame
	_navigation.build(_scene.get_world_2d().direct_space_state, [_actor.get_rid()])
	_navigation.register("standing", _actor)
	assert_true(_navigation.is_clear(Vector2(16, 0)), "Resident was baked into static obstacles")
	var path: PackedVector2Array = _navigation.route(Vector2.ZERO, Vector2(48, 0), "walker")
	assert_false(path.is_empty())
	for point: Vector2 in path:
		assert_true(point.distance_to(_actor.position) >= 12, "Route crosses a stationary neighbor")
	_actor.position = Vector2(16, 80)
	var clear_path: PackedVector2Array = _navigation.route(Vector2.ZERO, Vector2(48, 0), "walker")
	for point: Vector2 in clear_path:
		assert_eq(point.y, 0.0, "Moving a resident left a phantom obstacle")

func test_shared_venues_reserve_distinct_destinations_and_release_departures() -> void:
	await _scene.get_tree().physics_frame
	_navigation.build(_scene.get_world_2d().direct_space_state, [_actor.get_rid()])
	var destinations: Array[Vector2] = []
	for index: int in range(9):
		var point: Vector2 = _navigation.reserve_destination(str(index), Vector2.ZERO)
		for previous: Vector2 in destinations:
			assert_true(point.distance_to(previous) >= TownNavigation.PERSONAL_SPACE)
		destinations.append(point)
	_navigation.release("0")
	assert_eq(_navigation.reserve_destination("new", Vector2.ZERO), Vector2.ZERO)

func test_oncoming_walkers_steer_to_opposite_sides() -> void:
	await _scene.get_tree().physics_frame
	_navigation.build(_scene.get_world_2d().direct_space_state, [_actor.get_rid()])
	var other := Node2D.new()
	_scene.add_child(other)
	_navigation.register("a", other)
	_navigation.register("b", _actor)
	var first: Vector2 = _navigation.avoid("a", Vector2.ZERO, Vector2.RIGHT)
	var second: Vector2 = _navigation.avoid("b", _actor.position, Vector2.LEFT)
	assert_true(first.y > 0 and second.y < 0, "Oncoming walkers must not choose the same side")
