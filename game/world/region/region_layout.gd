@tool

class_name RegionLayout
extends RefCounted

## Seeded placement data, independent of rendering and the scene tree.
## Coordinates are 8-pixel terrain cells. Town and landmarks are authored and stable.
const BOUNDS := Rect2i(-152, -120, 304, 240)
const TOWN := Rect2i(-48, -36, 106, 88)
const PLAYER_SPAWN := Vector2(-112, 48)
const RIVER_LEFT: int = 61
const BRIDGES: Array[int] = [-68, 4, 76]
const HOMES: Array[Dictionary] = [
	{"job": "alchemist", "cell": Vector2i(-19, -15)},
	{"job": "jeweller", "cell": Vector2i(9, -15)},
	{"job": "tailor", "cell": Vector2i(19, -15)},
	{"job": "blacksmith", "cell": Vector2i(-21, 1)},
	{"job": "cooker", "cell": Vector2i(21, 1)},
	{"job": "carpenter", "cell": Vector2i(-20, 18)},
	{"job": "dyer", "cell": Vector2i(9, 19)},
	{"job": "butcher", "cell": Vector2i(20, 18)},
	{"job": "furrier", "cell": Vector2i(42, -12)},
	{"job": "voss_house", "cell": Vector2i(-40, -14)},
	{"job": "watch_house", "cell": Vector2i(-40, 22)},
	{"job": "rowan_farm", "cell": Vector2i(21, 37)},
]
const CAMPS: Array[Vector2i] = [Vector2i(-110, -70), Vector2i(-70, -45),
	Vector2i(-100, 56), Vector2i(-48, 83), Vector2i(19, -86),
	Vector2i(108, -70), Vector2i(118, -22), Vector2i(105, 67), Vector2i(23, 84)]
const APPROACH_CAMPS: Array[Vector2i] = [Vector2i(-68, 4), Vector2i(-2, -54),
	Vector2i(83, 4), Vector2i(-2, 68)]

var region_seed: int
var roads: Dictionary[Vector2i, bool] = {}
var stone: Array[Vector2i] = []
var trees: Array[Dictionary] = []
var details: Array[Dictionary] = []
var enemies: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

func generate(value: int) -> void:
	region_seed = value
	_rng.seed = value
	roads.clear()
	stone.clear()
	trees.clear()
	details.clear()
	enemies.clear()
	# Connected loops with three permanent river crossings.
	_road([Vector2i(-145, 4), Vector2i(145, 4)], 2)
	_road([Vector2i(0, -113), Vector2i(0, 111)], 2)
	_road([Vector2i(-110, 4), Vector2i(-110, -70), Vector2i(-42, -68),
		Vector2i(108, -68), Vector2i(108, 4)], 1)
	_road([Vector2i(-100, 4), Vector2i(-100, 56), Vector2i(-48, 76),
		Vector2i(105, 76), Vector2i(108, 4)], 1)
	for home: Dictionary in HOMES:
		var cell: Vector2i = home.cell
		if cell.y > 4:
			_road([cell + Vector2i(0, 3), cell + Vector2i(-7, 3),
				Vector2i(cell.x - 7, 4)], 1)
		else:
			_road([cell + Vector2i(0, 3), Vector2i(cell.x, 4)], 1)
		_disc(cell + Vector2i(0, 2), 5)
	for camp: Vector2i in CAMPS:
		var closest := Vector2i.ZERO
		var distance: float = INF
		for cell: Vector2i in roads:
			var next: float = Vector2(cell - camp).length_squared()
			if next < distance:
				distance = next
				closest = cell
		_road([closest, camp], 1)
		_disc(camp, 6)
		for index: int in range(3):
			enemies.append({"cell": camp + Vector2i(index * 3 - 3, 0),
				"kind": _rng.randi_range(0, 2)})
	# Small encounters are visible soon after leaving each town approach.
	# Their enemy types are fixed, independent of the forest seed.
	for camp: Vector2i in APPROACH_CAMPS:
		_disc(camp, 5)
		var entrance := Vector2i(camp.x, 4) if camp.x in [-68, 83] else Vector2i(0, camp.y)
		_road([camp, entrance], 1)
		for index: int in range(2):
			enemies.append({"cell": camp + Vector2i(index * 4 - 2, 0), "kind": index})
	for y: int in range(-5, 13):
		for x: int in range(-9, 10):
			stone.append(Vector2i(x, y))
	var noise := FastNoiseLite.new()
	noise.seed = value
	noise.frequency = 0.055
	for y: int in range(BOUNDS.position.y + 2, BOUNDS.end.y - 2, 3):
		for x: int in range(BOUNDS.position.x + 2, BOUNDS.end.x - 2, 3):
			var cell := Vector2i(x, y) + Vector2i(_rng.randi_range(-1, 1), _rng.randi_range(-1, 1))
			if is_reserved(cell, 3):
				continue
			var wet: bool = cell.x > 74 and cell.y > 30
			var density: float = 0.66 + noise.get_noise_2d(x, y) * 0.7
			if _rng.randf() < density:
				trees.append({"cell": cell, "kind": 2 if wet else _rng.randi_range(0, 1)})
			elif _rng.randf() < 0.65:
				details.append({"cell": cell, "kind": _rng.randi_range(0, 4), "wet": wet})

func is_water(cell: Vector2i) -> bool:
	return cell.x >= river_left_at(cell.y) and cell.x <= river_left_at(cell.y) + 8

static func river_left_at(row: int) -> int:
	return RIVER_LEFT + roundi(sin(row * 0.035) * 6.0)

func is_bridge(cell: Vector2i) -> bool:
	if not is_water(cell):
		return false
	for row: int in BRIDGES:
		if absi(cell.y - row) <= 2:
			return true
	return false

func is_reserved(cell: Vector2i, margin: int = 0) -> bool:
	if TOWN.grow(margin).has_point(cell) or Rect2i(33, -24, 25, 43).grow(margin).has_point(cell):
		return true
	if cell.x >= river_left_at(cell.y) - margin - 2 and cell.x <= river_left_at(cell.y) + 10 + margin:
		return true
	for y: int in range(-margin, margin + 1):
		for x: int in range(-margin, margin + 1):
			if roads.has(cell + Vector2i(x, y)):
				return true
	return false

func _road(points: Array[Vector2i], radius: int) -> void:
	for index: int in range(points.size() - 1):
		var start: Vector2 = points[index]
		var end: Vector2 = points[index + 1]
		var steps: int = ceili(start.distance_to(end))
		var normal: Vector2 = (end - start).normalized().orthogonal()
		for step: int in range(steps + 1):
			var weight: float = float(step) / maxi(steps, 1)
			var point: Vector2 = start.lerp(end, weight)
			if not TOWN.grow(14).has_point(Vector2i(point)):
				var bank_distance: float = absf(point.x - 65.0)
				var town_distance: float = maxf(absf(point.x) - 46, absf(point.y) - 40)
				var bend: float = sin(weight * PI) * sin(weight * TAU) * minf(steps * 0.12, 9.0)
				var fade: float = smoothstep(14.0, 30.0, bank_distance)
				point += normal * bend * fade * smoothstep(0.0, 12.0, town_distance)
			_disc(Vector2i(point.round()), radius)

func _disc(center: Vector2i, radius: int) -> void:
	for y: int in range(-radius, radius + 1):
		for x: int in range(-radius, radius + 1):
			if x * x + y * y <= radius * radius:
				roads[center + Vector2i(x, y)] = true
