class_name NpcDailyRoutine
extends RefCounted

## Optional movement component. Actor states remain responsible for animation and physics.
var navigation: TownNavigation
var npc_id: String = ""
var activity: String = "rest"
var place: String = "home"
var destination: Vector2
var _path: PackedVector2Array = []
var _index: int = 0
var _held: bool = false
var _last_position: Vector2
var _stuck_seconds: float = 0.0
var _retry_seconds: float = 0.0

func travel(from: Vector2, to: Vector2, kind: String, place_name: String) -> void:
	activity = kind
	place = place_name
	destination = navigation.nearest(to)
	_repath(from)
	_last_position = from
	_stuck_seconds = 0.0

func hold(value: bool) -> void:
	_held = value

func has_route(position: Vector2) -> bool:
	_advance(position)
	return not _held and _index < _path.size()

func direction(position: Vector2) -> Vector2:
	if not has_route(position):
		return Vector2.ZERO
	return navigation.avoid(npc_id, position, position.direction_to(_path[_index]))

func update(position: Vector2, delta: float, interrupted: bool) -> void:
	_retry_seconds += delta
	if not interrupted and not _held and _retry_seconds >= 1.0 \
		and position.distance_to(destination) > 3.0:
		_retry_seconds = 0.0
		_repath(position)
	if interrupted or _held or not has_route(position):
		_stuck_seconds = 0.0
		_last_position = position
		return
	if position.distance_to(_last_position) < delta:
		_stuck_seconds += delta
	else:
		_stuck_seconds = 0.0
	_last_position = position
	if _stuck_seconds >= 2.5:
		travel(position, destination, activity, place)

func context(position: Vector2) -> Dictionary:
	return {"activity": activity, "location": place,
		"traveling": has_route(position), "destination": place}

func _advance(position: Vector2) -> void:
	while _index < _path.size() and position.distance_to(_path[_index]) <= 2.5:
		_index += 1

func _repath(position: Vector2) -> void:
	_path = navigation.route(position, destination, npc_id)
	# The first cell is the walker's current cell, not a new waypoint behind their feet.
	_index = 1 if _path.size() > 1 else 0
