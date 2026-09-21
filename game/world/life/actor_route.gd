class_name ActorRoute
extends RefCounted

## Cached route shared by routines and pursuit. A moving crowd does not force periodic A* searches.
var navigation: TownNavigation
var id: String = ""
var goal: Vector2
var arrival_distance: float = 2.5
var _points: PackedVector2Array = []
var _index: int = 0
var _pending: bool = false
var _retry: float = 0.0
var _stalled: float = 0.0
var _progress_index: int = -1
var _best_distance: float = INF

func travel(from: Vector2, to: Vector2) -> void:
	goal = to
	_pending = true
	_points.clear()
	_index = 0
	_best_distance = from.distance_to(to)
	_progress_index = -1
	_stalled = 0.0
	_retry = 0.0

func retarget(from: Vector2, to: Vector2) -> void:
	if not _points.is_empty() and goal.distance_to(to) <= TownNavigation.CELL_SIZE \
		and navigation.can_travel(_points[maxi(0, _points.size() - 2)], to):
		goal = to
		_points[-1] = to
		_index = mini(_index, _points.size() - 1)
	else:
		travel(from, to)

func update(position: Vector2, delta: float, paused: bool = false) -> void:
	_retry = maxf(0, _retry - delta)
	if paused:
		_stalled = 0.0
		_progress_index = -1
		return
	if position.distance_to(goal) > arrival_distance:
		var distance: float = position.distance_to(_points[_index]) if _index < _points.size() else INF
		if _progress_index != _index or distance < _best_distance - 0.25:
			_stalled = 0.0
			_best_distance = distance
			_progress_index = _index
		else:
			_stalled += delta
		if (_points.is_empty() or _stalled > 0.8) and _retry <= 0:
			_pending = true
	_resolve(position)

func active(position: Vector2) -> bool:
	_advance(position)
	return position.distance_to(goal) > arrival_distance and (_pending or _index < _points.size())

func waypoint(position: Vector2) -> Vector2:
	_resolve(position)
	_advance(position)
	return _points[_index] if _index < _points.size() else position

func _resolve(position: Vector2) -> void:
	if not _pending or navigation == null or not navigation.take_route_budget():
		return
	_points = navigation.route(position, goal, id)
	_index = 1 if _points.size() > 1 and position.distance_to(_points[0]) <= 6 else 0
	_pending = false
	_retry = 1.0
	_stalled = 0.0
	_progress_index = -1

func _advance(position: Vector2) -> void:
	while _index < _points.size() and position.distance_to(_points[_index]) <= \
		(arrival_distance if _index == _points.size() - 1 else 2.0):
		_index += 1
	# Look through clear intermediate cells instead of making opposing walkers orbit
	# the same grid point. Shape sweeps prevent shortcuts through walls or corners.
	while _index < _points.size() - 1 and position.distance_to(_points[_index]) < 16.0 \
		and navigation.can_travel(position, _points[_index + 1]):
		_index += 1
