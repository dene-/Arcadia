class_name NpcDailyRoutine
extends RefCounted

## Routine intent delegates path following to the same route component used by combat pursuit.
var navigation: TownNavigation
var npc_id: String = ""
var activity: String = "rest"
var place: String = "home"
var destination: Vector2
var _route := ActorRoute.new()
var _held: bool = false

func travel(from: Vector2, to: Vector2, kind: String, place_name: String) -> void:
	activity = kind
	place = place_name
	destination = navigation.nearest(to)
	_route.navigation = navigation
	_route.id = npc_id
	_route.travel(from, destination)

func hold(value: bool) -> void:
	_held = value

func has_route(position: Vector2) -> bool:
	return not _held and _route.active(position)

func direction(position: Vector2) -> Vector2:
	return velocity_for(position, 28.0, 1.0 / 60.0) / 28.0

func velocity_for(position: Vector2, speed: float, delta: float) -> Vector2:
	if not has_route(position) or delta <= 0.0:
		return Vector2.ZERO
	var offset: Vector2 = _route.waypoint(position) - position
	var desired: Vector2 = offset.normalized() * minf(speed, offset.length() / delta)
	return navigation.steer(npc_id, position, desired, delta)

func update(position: Vector2, delta: float, interrupted: bool) -> void:
	_route.update(position, delta, interrupted or _held)

func context(position: Vector2) -> Dictionary:
	return {"activity": activity, "location": place,
		"traveling": has_route(position), "destination": place}
