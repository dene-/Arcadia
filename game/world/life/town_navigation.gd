class_name TownNavigation
extends RefCounted

## Static geometry, temporary actor obstacles, and destination reservations have distinct lifetimes.
const CELL_SIZE: float = 8.0
const AREA := Rect2i(-34, -28, 93, 57)
const PERSONAL_SPACE: float = 20.0
var _grid := AStarGrid2D.new()
var _occupants: Dictionary[String, WeakRef] = {}
var _destinations: Dictionary[String, Vector2] = {}
var ready: bool = false
var area: Rect2i = AREA

func register(id: String, actor: Node2D) -> void:
	_occupants[id] = weakref(actor)

func release(id: String) -> void:
	_occupants.erase(id)
	_destinations.erase(id)

func build(space: PhysicsDirectSpaceState2D, actor_bodies: Array[RID] = []) -> void:
	_grid.region = area
	_grid.cell_size = Vector2.ONE * CELL_SIZE
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	var footprint := RectangleShape2D.new()
	footprint.size = Vector2(12, 10)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = footprint
	query.collision_mask = 1
	# CharacterBody2D also uses layer 1: baking residents would leave permanent phantom obstacles.
	query.exclude = actor_bodies
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			query.transform = Transform2D(0, Vector2(cell) * CELL_SIZE + Vector2(0, -1))
			_grid.set_point_solid(cell, not space.intersect_shape(query, 1).is_empty())
	ready = true

func nearest(point: Vector2) -> Vector2:
	return Vector2(_nearest_cell(point)) * CELL_SIZE

func reserve_destination(id: String, preferred: Vector2) -> Vector2:
	var center: Vector2i = _nearest_cell(preferred)
	for radius: int in range(10):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var point: Vector2 = Vector2(center + Vector2i(x, y)) * CELL_SIZE
				if is_clear(point) and _has_space(id, point):
					_destinations[id] = point
					return point
	# Keep the old safe destination if the venue cannot accommodate another person.
	return _destinations.get(id, nearest(preferred))

func route(from: Vector2, to: Vector2, id: String = "") -> PackedVector2Array:
	if not ready:
		return []
	var start: Vector2i = _nearest_cell(from)
	var end: Vector2i = _nearest_cell(to)
	var temporary: Array[Vector2i] = []
	if not id.is_empty():
		for other: String in _occupants:
			var actor: Node2D = _occupants[other].get_ref()
			if actor == null or other == id:
				continue
			var center := Vector2i((actor.global_position / CELL_SIZE).round())
			for y: int in range(-1, 2):
				for x: int in range(-1, 2):
					var cell: Vector2i = center + Vector2i(x, y)
					if cell != start and cell != end and area.has_point(cell) and not _grid.is_point_solid(cell):
						_grid.set_point_solid(cell, true)
						temporary.append(cell)
	var path: PackedVector2Array = _grid.get_point_path(start, end)
	for cell: Vector2i in temporary:
		_grid.set_point_solid(cell, false)
	# A tight crowd can cover every adjacent grid cell. Local steering must still be able to escape.
	if path.is_empty():
		path = _grid.get_point_path(start, end)
	return path

func avoid(id: String, position: Vector2, desired: Vector2) -> Vector2:
	if desired == Vector2.ZERO:
		return desired
	var nearest_other: Node2D
	var distance: float = 22.0
	for other: String in _occupants:
		var actor: Node2D = _occupants[other].get_ref()
		if actor == null or other == id:
			continue
		var offset: Vector2 = actor.global_position - position
		if offset.length() < distance and desired.dot(offset.normalized()) > 0.25:
			nearest_other = actor
			distance = offset.length()
	if nearest_other == null:
		return desired
	# Both oncoming walkers keep to their own right, rather than pushing into one another.
	var right := Vector2(-desired.y, desired.x)
	for direction: Vector2 in [(desired + right * 1.8).normalized(), right, -right]:
		if is_clear(position + direction * 12.0) \
			and (position + direction * 5.0).distance_to(nearest_other.global_position) >= distance:
			return direction
	# Return a very small direction to yield without leaving the walk state and losing the route.
	return desired * 0.01

func is_clear(point: Vector2) -> bool:
	var cell := Vector2i((point / CELL_SIZE).round())
	return ready and area.has_point(cell) and not _grid.is_point_solid(cell)

func _has_space(id: String, point: Vector2) -> bool:
	for other: String in _destinations:
		if other != id and point.distance_to(_destinations[other]) < PERSONAL_SPACE:
			return false
	for other: String in _occupants:
		var actor: Node2D = _occupants[other].get_ref()
		if other != id and actor != null and point.distance_to(actor.global_position) < PERSONAL_SPACE:
			return false
	return true

func _nearest_cell(point: Vector2) -> Vector2i:
	var center := Vector2i((point / CELL_SIZE).round())
	center.x = clampi(center.x, area.position.x, area.end.x - 1)
	center.y = clampi(center.y, area.position.y, area.end.y - 1)
	for radius: int in range(12):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var cell: Vector2i = center + Vector2i(x, y)
				if area.has_point(cell) and not _grid.is_point_solid(cell):
					return cell
	return center
