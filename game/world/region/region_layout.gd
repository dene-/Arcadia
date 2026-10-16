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
const DRY_PROPS: Array[String] = ["boulder", "boulder", "stump", "stump", "log", "log_b",
	"menhir", "standing_stone", "standing_stone_b", "standing_stone_c"]
const WET_PROPS: Array[String] = ["boulder_mossy", "stump", "log", "snag", "snag_b", "log_b"]

var region_seed: int
var roads: Dictionary[Vector2i, bool] = {}
var stone: Array[Vector2i] = []
var trees: Array[Dictionary] = []
var details: Array[Dictionary] = []
## Colliding forest props (rocks, logs, stumps): {"cell", "name"}.
var props: Array[Dictionary] = []
## Ground cover without collision: {"cell", "name", "mirrored"}.
var cover: Array[Dictionary] = []
var enemies: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _camp_roads: Dictionary[Vector2i, Vector2i] = {}
var _paths: Dictionary[Vector2i, bool] = {}

func generate(value: int) -> void:
	region_seed = value
	_rng.seed = value
	roads.clear()
	stone.clear()
	trees.clear()
	details.clear()
	props.clear()
	cover.clear()
	enemies.clear()
	_camp_roads.clear()
	_paths.clear()
	# Connected loops with three permanent river crossings.
	_road([Vector2i(-145, 4), Vector2i(145, 4)], 2)
	_road([Vector2i(0, -113), Vector2i(0, 111)], 2)
	_road([Vector2i(-15, 45), Vector2i(0, 45)], 1)
	_road([Vector2i(-110, 4), Vector2i(-110, -70), Vector2i(-42, -68),
		Vector2i(108, -68), Vector2i(108, 4)], 1)
	_road([Vector2i(-100, 4), Vector2i(-100, 56), Vector2i(-48, 76),
		Vector2i(105, 76), Vector2i(108, 4)], 1)
	for home: Dictionary in HOMES:
		var cell: Vector2i = home.cell
		if cell.y > 4:
			# Side lanes stay inside the fence: homes near the west edge turn toward the square.
			var side: int = -7 if cell.x - 7 > TOWN.position.x + 4 else 7
			_road([cell + Vector2i(0, 3), cell + Vector2i(side, 3),
				Vector2i(cell.x + side, 4)], 1)
		else:
			_road([cell + Vector2i(0, 3), Vector2i(cell.x, 4)], 1)
		# A tidy dooryard rather than a round clearing hides the house's base.
		for y: int in range(0, 4):
			for x: int in range(-3, 4):
				roads[cell + Vector2i(x, y)] = true
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
		_camp_roads[camp] = closest
		for index: int in range(3):
			enemies.append({"cell": camp + Vector2i(index * 3 - 3, 0),
				"kind": _rng.randi_range(0, 2)})
	# Small encounters are visible soon after leaving each town approach.
	# Their enemy types are fixed, independent of the forest seed.
	for camp: Vector2i in APPROACH_CAMPS:
		_disc(camp, 5)
		var entrance := Vector2i(camp.x, 4) if camp.x in [-68, 83] else Vector2i(0, camp.y)
		_road([camp, entrance], 1)
		_camp_roads[camp] = entrance
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
	_scatter(value)

## The south-east wetland: a wavy western bank and a wavy northern edge.
static func is_swamp(cell: Vector2i) -> bool:
	var top: int = 32 + roundi(sin(cell.x * 0.11) * 3.0 + sin(cell.x * 0.29 + 1.3) * 1.5)
	return cell.y >= top and cell.x >= 76 + roundi(sin(cell.y * 0.045) * 4.0)

func is_water(cell: Vector2i) -> bool:
	return cell.x >= river_left_at(cell.y) and cell.x <= river_left_at(cell.y) + 8

static func river_left_at(row: int) -> int:
	return RIVER_LEFT + roundi(sin(row * 0.035) * 6.0)

func is_bridge(cell: Vector2i) -> bool:
	if not is_water(cell):
		return false
	# Only the deck between the parapets is open; the arches below stay water.
	for row: int in BRIDGES:
		if absi(cell.y - row) <= 1:
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
			_disc(Vector2i(point.round()), radius, true)

func _disc(center: Vector2i, radius: int, path: bool = false) -> void:
	for y: int in range(-radius, radius + 1):
		for x: int in range(-radius, radius + 1):
			if x * x + y * y <= radius * radius:
				roads[center + Vector2i(x, y)] = true
				if path:
					_paths[center + Vector2i(x, y)] = true

# Rocks, fallen wood, undergrowth and bank reeds. A separate generator keeps the
# seeded trees, details and enemies identical to earlier versions of the region.
func _scatter(value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([value, "scatter"])
	var taken: Dictionary[Vector2i, bool] = {}
	for tree: Dictionary in trees:
		for y: int in range(-1, 2):
			for x: int in range(-2, 3):
				taken[tree.cell + Vector2i(x, y)] = true
	for detail: Dictionary in details:
		taken[detail.cell] = true
	for y: int in range(BOUNDS.position.y + 3, BOUNDS.end.y - 3, 4):
		for x: int in range(BOUNDS.position.x + 3, BOUNDS.end.x - 3, 4):
			var cell := Vector2i(x + rng.randi_range(-1, 1), y + rng.randi_range(-1, 1))
			if is_reserved(cell, 1) or taken.has(cell):
				continue
			var wet: bool = is_swamp(cell)
			var roll: float = rng.randf()
			# Solid props keep clear of trunks and roads; plants may grow at their feet.
			if roll < 0.2 and not is_reserved(cell, 2) and not _near(taken, cell, 1):
				var names: Array[String] = WET_PROPS if wet else DRY_PROPS
				props.append({"cell": cell, "name": names[rng.randi() % names.size()],
					"mirrored": rng.randf() < 0.5})
				_take(taken, cell, 2)
			elif roll < 0.75:
				_cover_cluster(rng, cell, wet, taken)
	# Reeds line both river banks, leaving the bridge approaches clear.
	for row: int in range(BOUNDS.position.y, BOUNDS.end.y):
		var near_bridge: bool = false
		for bridge: int in BRIDGES:
			near_bridge = near_bridge or absi(row - bridge) <= 5
		if near_bridge:
			continue
		for x: int in [river_left_at(row) - 2, river_left_at(row) + 10]:
			if rng.randf() < 0.3:
				var names: Array[String] = ["reed", "reeds", "reeds", "weeds", "sprouts", "cattail"]
				cover.append({"cell": Vector2i(x, row), "name": names[rng.randi() % names.size()],
					"mirrored": rng.randf() < 0.5})
	# Fallen logs and stones ring each clearing, away from its entrance and the enemies.
	for camp: Vector2i in _camp_roads:
		var entrance := Vector2(_camp_roads[camp] - camp)
		var seats: int = 0
		for direction: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1),
			Vector2(0, -1), Vector2(0, 1)]:
			if seats >= 3:
				break
			if entrance.length() > 0.5 and direction.normalized().dot(entrance.normalized()) > 0.4:
				continue
			if rng.randf() < 0.3:
				continue
			var spot: Vector2i = camp + Vector2i((direction.normalized() * 4.5).round())
			# Clearings on a through-route keep that route clear, not just the entrance.
			if _on_path(spot):
				continue
			props.append({"cell": spot, "name": ["log", "log_b", "stump"][seats % 3],
				"mirrored": direction.x > 0})
			seats += 1

func _on_path(cell: Vector2i) -> bool:
	for y: int in range(-2, 3):
		for x: int in range(-2, 3):
			if _paths.has(cell + Vector2i(x, y)):
				return true
	return false

func _cover_cluster(rng: RandomNumberGenerator, cell: Vector2i, wet: bool,
		taken: Dictionary[Vector2i, bool]) -> void:
	var names: Array[String]
	if wet:
		names = ["fern", "fern_b", "rush", "cattail", "mushroom", "pebble"]
	else:
		names = ["flowers", "flower_red", "flower_purple", "flower_white", "sprouts", "sprouts",
			"weeds", "bush", "bush_small", "fern", "mushroom", "daisy", "pebbles", "weeds"]
	var first: String = names[rng.randi() % names.size()]
	for index: int in range(rng.randi_range(1, 4)):
		var spot: Vector2i = cell + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-1, 1))
		if taken.has(spot) or is_reserved(spot, 1):
			continue
		# Clusters repeat their first plant so patches read as one kind of growth.
		var plant: String = first if rng.randf() < 0.6 else names[rng.randi() % names.size()]
		cover.append({"cell": spot, "name": plant, "mirrored": rng.randf() < 0.5})
		taken[spot] = true

func _near(taken: Dictionary[Vector2i, bool], cell: Vector2i, radius: int) -> bool:
	for y: int in range(-radius, radius + 1):
		for x: int in range(-radius, radius + 1):
			if taken.has(cell + Vector2i(x, y)):
				return true
	return false

func _take(taken: Dictionary[Vector2i, bool], cell: Vector2i, radius: int) -> void:
	for y: int in range(-radius, radius + 1):
		for x: int in range(-radius, radius + 1):
			taken[cell + Vector2i(x, y)] = true
