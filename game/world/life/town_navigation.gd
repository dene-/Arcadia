class_name TownNavigation
extends RefCounted

## Shared static A*, local crowd movement, and short-lived space reservations for one world space.
const CELL_SIZE: float = 8.0
const AREA := Rect2i(-34, -28, 93, 57)
const PERSONAL_SPACE: float = 20.0
const MAX_SEARCHES_PER_FRAME: int = 4
var ready: bool = false
var area: Rect2i = AREA
var clearance: float = 5.25
var route_searches: int = 0
var route_usec: int = 0
var build_usec: int = 0
var _grid := AStarGrid2D.new()
var _occupants: Dictionary[String, WeakRef] = {}
var _destinations: Dictionary[String, Vector2] = {}
var _attacks: Dictionary = {}
var _space: PhysicsDirectSpaceState2D
var _query := PhysicsShapeQueryParameters2D.new()
var _budget_frame: int = -1
var _searches_this_frame: int = 0
var _crowd := ActorCrowd.new()
var _has_footprint: bool = false

func register(id: String, actor: Node2D) -> void:
	_occupants[id] = weakref(actor)
	_crowd.invalidate()
	if actor is BaseActor:
		actor.movement_navigation = self
		actor.movement_id = id
		if not ready and actor is BaseNpc:
			clearance = maxf(clearance if _has_footprint else 0.0,
				ActorFootprint.radius(actor) + ActorFootprint.MARGIN)
			_has_footprint = true

func release(id: String) -> void:
	var actor: Node2D = _occupants[id].get_ref() if _occupants.has(id) else null
	if actor is BaseActor and actor.movement_navigation == self:
		actor.movement_navigation = null
	_occupants.erase(id)
	_destinations.erase(id)
	release_attack(id)
	_crowd.forget(id)

func build(space: PhysicsDirectSpaceState2D, actor_bodies: Array[RID] = []) -> void:
	var started: int = Time.get_ticks_usec()
	_space = space
	_grid.region = area
	_grid.cell_size = Vector2.ONE * CELL_SIZE
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	var footprint := CircleShape2D.new()
	footprint.radius = clearance
	_query.shape = footprint
	_query.collision_mask = ActorFootprint.WORLD
	# Also accepts exclusions for plain CharacterBody2D fixtures or older scenes.
	_query.exclude = actor_bodies
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			_grid.set_point_solid(cell, not clear_at(Vector2(cell) * CELL_SIZE))
	ready = true
	build_usec = Time.get_ticks_usec() - started

func clear_at(point: Vector2) -> bool:
	if _space == null or not area.has_point(Vector2i((point / CELL_SIZE).round())):
		return false
	_query.transform = Transform2D(0, point)
	_query.motion = Vector2.ZERO
	return _space.intersect_shape(_query, 1).is_empty()

func can_travel(from: Vector2, to: Vector2) -> bool:
	if _space == null or not clear_at(to):
		return false
	_query.transform = Transform2D(0, from)
	_query.motion = to - from
	var fractions: PackedFloat32Array = _space.cast_motion(_query)
	_query.motion = Vector2.ZERO
	return fractions[0] >= 0.999

func nearest(point: Vector2) -> Vector2:
	return Vector2(_nearest_cell(point, false)) * CELL_SIZE

func reserve_destination(id: String, preferred: Vector2) -> Vector2:
	var center: Vector2i = _nearest_cell(preferred, false)
	for radius: int in range(10):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var point: Vector2 = Vector2(center + Vector2i(x, y)) * CELL_SIZE
				if is_clear(point) and _has_space(id, point, PERSONAL_SPACE):
					_destinations[id] = point
					return point
	return _destinations.get(id, nearest(preferred))

func take_route_budget() -> bool:
	var frame: int = Engine.get_physics_frames()
	if _budget_frame != frame:
		_budget_frame = frame
		_searches_this_frame = 0
	if not ready or _searches_this_frame >= MAX_SEARCHES_PER_FRAME:
		return false
	_searches_this_frame += 1
	return true

func route(from: Vector2, to: Vector2, id: String = "") -> PackedVector2Array:
	if not ready:
		return []
	var started: int = Time.get_ticks_usec()
	route_searches += 1
	var start: Vector2i = _nearest_cell(from)
	var end: Vector2i = _nearest_cell(to, false)
	var temporary: Array[Vector2i] = []
	if not id.is_empty():
		for other: String in _occupants:
			var actor: Node2D = _occupants[other].get_ref()
			if actor == null or other == id or not ActorFootprint.active(actor):
				continue
			var center := Vector2i((actor.global_position / CELL_SIZE).round())
			var radius: float = ActorFootprint.radius(actor) + clearance
			var cells: int = ceili(radius / CELL_SIZE)
			for y: int in range(-cells, cells + 1):
				for x: int in range(-cells, cells + 1):
					var cell: Vector2i = center + Vector2i(x, y)
					if cell != start and cell != end and area.has_point(cell) \
						and not _grid.is_point_solid(cell) \
						and (Vector2(cell) * CELL_SIZE).distance_to(actor.global_position) < radius:
						_grid.set_point_solid(cell, true)
						temporary.append(cell)
	var path: PackedVector2Array = _grid.get_point_path(start, end)
	for cell: Vector2i in temporary:
		_grid.set_point_solid(cell, false)
	if path.is_empty():
		path = _grid.get_point_path(start, end)
	if not path.is_empty() and can_travel(path[-1], to):
		path.append(to)
	route_usec += Time.get_ticks_usec() - started
	return path

func steer(id: String, position: Vector2, desired_velocity: Vector2, delta: float) -> Vector2:
	return _crowd.steer(self, _occupants, id, position, desired_velocity, delta)

## Compatibility for callers that use a direction; movement states use velocity to preserve yielding.
func avoid(id: String, position: Vector2, desired: Vector2) -> Vector2:
	return steer(id, position, desired * 28.0, 1.0 / 60.0) / 28.0

func yield_velocity(id: String, position: Vector2, delta: float) -> Vector2:
	return _crowd.yield_to_player(self, _occupants, id, position, delta)

func is_clear(point: Vector2) -> bool:
	var cell := Vector2i((point / CELL_SIZE).round())
	return ready and area.has_point(cell) and not _grid.is_point_solid(cell)

func has_clear_sight(from: Vector2, to: Vector2) -> bool:
	if _space == null:
		return false
	var ray := PhysicsRayQueryParameters2D.create(from, to, ActorFootprint.WORLD)
	return _space.intersect_ray(ray).is_empty()

func attack_destination(id: String, target: Node2D, from: Vector2, reach: float) -> Dictionary:
	var target_key: int = target.get_instance_id()
	if not _attacks.has(target_key):
		_attacks[target_key] = {}
	var slots: Dictionary = _attacks[target_key]
	# Expire abandoned approaches; healthy active pursuers renew their lease each tick.
	for key: String in slots.keys():
		if slots[key].until < Engine.get_physics_frames():
			slots.erase(key)
	var preferred: int = -1 if from.x < target.global_position.x else 1
	for key: String in slots:
		if slots[key].id == id:
			preferred = int(key)
			break
	for side: int in [preferred, -preferred]:
		var key: String = str(side)
		var point: Vector2 = target.global_position + Vector2(side * reach, 0)
		if slots.has(key) and slots[key].id != id:
			continue
		if clear_at(point) and has_clear_sight(point, target.global_position):
			# Changing sides replaces the old claim instead of reserving both approaches.
			for old: String in slots.keys():
				if old != key and slots[old].id == id:
					slots.erase(old)
			slots[key] = {"id": id, "until": Engine.get_physics_frames() + Engine.physics_ticks_per_second * 2}
			_destinations.erase(id)
			return {"point": point, "attack": true, "slot": key}
	# Waiting attackers occupy separate nearby positions instead of running into the front rank.
	var point: Vector2 = reserve_destination(id, target.global_position + Vector2(preferred * (reach + 20), 16))
	return {"point": point, "attack": false, "slot": "wait"}

func release_attack(id: String) -> void:
	_destinations.erase(id)
	for target: int in _attacks.keys():
		for key: String in _attacks[target].keys():
			if _attacks[target][key].id == id:
				_attacks[target].erase(key)
		if _attacks[target].is_empty():
			_attacks.erase(target)

func landing(actor: BaseActor, preferred: Vector2) -> Vector2:
	# Stay at the visible threshold. Never send a blocked arrival to a distant free grid cell.
	for offset: Vector2 in [Vector2.ZERO, Vector2(-8, 0), Vector2(8, 0), Vector2(0, -8),
		Vector2(0, 8), Vector2(-8, -8), Vector2(8, -8), Vector2(-8, 8), Vector2(8, 8)]:
		var point: Vector2 = preferred + offset
		if not ready or not area.has_point(Vector2i((point / CELL_SIZE).round())) \
			or not ActorFootprint.clear_landing(actor, point, preferred):
			continue
		var occupied: bool = false
		for reference: WeakRef in _occupants.values():
			var other: Node2D = reference.get_ref()
			if other != null and other != actor and ActorFootprint.active(other) \
				and point.distance_to(other.global_position) < ActorFootprint.radius(actor) + ActorFootprint.radius(other) + 0.5:
				occupied = true
				break
		if not occupied:
			return point
	return Vector2.INF

func metrics() -> Dictionary:
	return {"build_ms": build_usec / 1000.0, "route_searches": route_searches,
		"route_ms": route_usec / 1000.0, "steering_calls": _crowd.steering_calls,
		"steering_ms": _crowd.steering_usec / 1000.0, "neighbor_checks": _crowd.neighbor_checks}

func _has_space(id: String, point: Vector2, spacing: float) -> bool:
	for other: String in _destinations:
		if other != id and point.distance_to(_destinations[other]) < spacing:
			return false
	for other: String in _occupants:
		var actor: Node2D = _occupants[other].get_ref()
		if other != id and actor != null and ActorFootprint.active(actor) and point.distance_to(actor.global_position) < spacing:
			return false
	return true

func _nearest_cell(point: Vector2, require_accessible: bool = true) -> Vector2i:
	var center := Vector2i((point / CELL_SIZE).round())
	center.x = clampi(center.x, area.position.x, area.end.x - 1)
	center.y = clampi(center.y, area.position.y, area.end.y - 1)
	for radius: int in range(12):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var cell: Vector2i = center + Vector2i(x, y)
				if area.has_point(cell) and not _grid.is_point_solid(cell) \
					and (not require_accessible or can_travel(point, Vector2(cell) * CELL_SIZE)):
					return cell
	return center
