class_name ActorCrowd
extends RefCounted

## One spatial snapshot per physics frame; steering predicts all nearby bodies, not just one.
const BUCKET: float = 48.0
const HORIZON: float = 0.4
## Shortest look-ahead (pixels) an otherwise blocked walker may still advance along.
const SHORT_PROBE: float = 3.0
## Seconds a walker must be held up before a standing body steps out of its way.
const BLOCKED_WAIT: float = 0.6
## Seconds a walker may stay pressed against the same body before slipping past it. A housemate
## seated in a one-tile lane has nowhere to step aside to, so the walker squeezes by instead;
## Den is never squeezed past.
const SQUEEZE_WAIT: float = 1.5
## Pixels beyond touching within which a body counts as being in the walker's way; predictive
## steering already halts a walker about a body's length short of it.
const PRESS_RANGE: float = 12.0
var _frame: int = -1
var _buckets: Dictionary = {}
var _samples: Dictionary = {}
var _previous: Dictionary[String, Vector2] = {}
var _waiting: Dictionary[String, float] = {}
var _wanted: Dictionary[String, Vector2] = {}
var _wanted_frame: Dictionary[String, int] = {}
# walker id -> {"by": id of the body in its way, "time": seconds pressed against it}
var _pressed: Dictionary[String, Dictionary] = {}
# "walker|body" -> [walker, body] while the walker slips past; their bodies ignore each other.
var _squeezes: Dictionary[String, Array] = {}
var neighbor_checks: int = 0
var steering_calls: int = 0
var steering_usec: int = 0

func invalidate() -> void:
	_frame = -1

func forget(id: String) -> void:
	_previous.erase(id)
	_waiting.erase(id)
	_wanted.erase(id)
	_wanted_frame.erase(id)
	_pressed.erase(id)
	for key: String in _squeezes.keys():
		if id in key.split("|"):
			_end_squeeze(key)
	invalidate()

func steer(navigation: TownNavigation, occupants: Dictionary[String, WeakRef], id: String,
		position: Vector2, desired: Vector2, delta: float) -> Vector2:
	var started: int = Time.get_ticks_usec()
	var result: Vector2 = _steer(navigation, occupants, id, position, desired, delta)
	if desired.length() >= 0.01:
		_press(occupants, id, position, desired, result, delta)
	steering_calls += 1
	steering_usec += Time.get_ticks_usec() - started
	return result

func _steer(navigation: TownNavigation, occupants: Dictionary[String, WeakRef], id: String,
		position: Vector2, desired: Vector2, delta: float) -> Vector2:
	_refresh(occupants)
	var speed: float = desired.length()
	if speed < 0.01:
		_previous[id] = Vector2.ZERO
		return Vector2.ZERO
	_wanted[id] = desired
	_wanted_frame[id] = Engine.get_physics_frames()
	var neighbors: Array[Dictionary] = _neighbors(id, position)
	if not _squeezes.is_empty():
		# A walker slipping past a body, and that body, no longer steer around each other.
		var kept: Array[Dictionary] = []
		for other: Dictionary in neighbors:
			if not _squeezes.has(_pair(id, other.id)) and not _squeezes.has(_pair(other.id, id)):
				kept.append(other)
		neighbors = kept
	var radius: float = _samples.get(id, {}).get("radius", navigation.clearance)
	var previous: Vector2 = _previous.get(id, desired)
	var lookahead: float = minf(HORIZON, 10.0 / speed)
	if _risk(position, desired, radius, neighbors) == 0.0 \
		and navigation.can_travel(position, position + desired * lookahead):
		var gentle: Vector2 = previous.move_toward(desired, maxf(speed * 8.0, 120.0) * delta)
		if _risk(position, gentle, radius, neighbors) >= 10.0 \
			or not navigation.can_travel(position, position + gentle * lookahead):
			gentle = desired
		_previous[id] = gentle
		_waiting[id] = 0.0
		return gentle
	var best: Vector2 = Vector2.ZERO
	var best_score: float = -2.0
	# Stable right-hand preference breaks symmetric head-on encounters.
	var candidates: Array[Vector2] = [desired, desired * 0.45]
	for other: Dictionary in neighbors:
		if position.distance_to(other.position) < radius + other.radius:
			candidates.append(-desired * 0.4)
			break
	for angle: float in [PI / 6, -PI / 6, PI / 3, -PI / 3, PI / 2, -PI / 2]:
		candidates.append(desired.rotated(angle))
	var waited: float = _waiting.get(id, 0.0)
	if waited > 0.6:
		# In a bottleneck one person backs up; stable IDs prevent both repeatedly swapping roles.
		for other: Dictionary in neighbors:
			if id > other.id and position.distance_to(other.position) < 20:
				candidates.append(-desired * 0.4)
				break
	for candidate: Vector2 in candidates:
		var probe: Vector2 = position + candidate * minf(HORIZON, 10.0 / speed)
		if not navigation.can_travel(position, probe):
			continue
		var risk: float = _risk(position, candidate, radius, neighbors)
		if risk >= 10.0:
			continue
		var alignment: float = candidate.dot(desired) / (speed * speed)
		var score: float = alignment * 3.0 - risk - (candidate - previous).length() / speed * 0.35
		if desired.cross(candidate) > 0:
			score += 0.15
		if score > best_score:
			best_score = score
			best = candidate
	# Inching through a pocket still counts as held up, so standing bodies can make way.
	var held_up: bool = best.dot(desired) < speed * speed * 0.2
	if best == Vector2.ZERO and _risk(position, desired, radius, neighbors) < 10.0 \
			and navigation.can_travel(position, position + desired.normalized() * SHORT_PROBE):
		# A tight pocket between two fixtures can reject every long probe while a short step is
		# still clear. Inch along instead of standing pinned until someone else moves.
		best = desired
	_waiting[id] = waited + delta if held_up else 0.0
	# Smooth steering for autonomous bodies, but stop promptly if smoothing would cause contact.
	var smoothed: Vector2 = previous.move_toward(best, maxf(speed * 8.0, 120.0) * delta)
	if best != Vector2.ZERO and _risk(position, smoothed, radius, neighbors) < 10.0 \
		and navigation.can_travel(position, position + smoothed * minf(HORIZON, 10.0 / speed)):
		best = smoothed
	_previous[id] = best
	return best

## Bodies that stand still make way for Den as he approaches, and for a walker who has waited
## in front of them (`_waiting` for BLOCKED_WAIT seconds) with nowhere else to go.
func yield_to_player(navigation: TownNavigation, occupants: Dictionary[String, WeakRef],
		id: String, position: Vector2, delta: float) -> Vector2:
	_refresh(occupants)
	for other: Dictionary in _neighbors(id, position):
		var heading: Vector2 = other.velocity
		if not other.player:
			# Only a walker that is steering right now and has been held up asks for room.
			if float(_waiting.get(other.id, 0.0)) < BLOCKED_WAIT \
					or Engine.get_physics_frames() - int(_wanted_frame.get(other.id, -100)) > 2:
				continue
			heading = _wanted.get(other.id, Vector2.ZERO)
		if heading.length() < 2.0:
			continue
		var to_self: Vector2 = position - other.position
		var radius: float = _samples.get(id, {}).get("radius", navigation.clearance)
		var warning_distance: float = maxf(22, radius + other.radius + heading.length() * 0.65)
		if to_self.length() > warning_distance or heading.normalized().dot(to_self.normalized()) < 0.6:
			continue
		var right: Vector2 = Vector2(-heading.y, heading.x).normalized()
		return steer(navigation, occupants, id, position, right * 18.0, delta)
	return Vector2.ZERO

func _risk(position: Vector2, velocity: Vector2, radius: float, neighbors: Array[Dictionary]) -> float:
	var score: float = 0.0
	for other: Dictionary in neighbors:
		neighbor_checks += 1
		var offset: Vector2 = position - other.position
		var relative: Vector2 = velocity - other.velocity
		var when: float = clampf(-offset.dot(relative) / maxf(relative.length_squared(), 0.001), 0, HORIZON)
		var distance: float = (offset + relative * when).length()
		var spacing: float = radius + other.radius + 0.6
		if distance < spacing:
			# Permit escaping existing contact instead of freezing two overlapping arrivals.
			if offset.length() < spacing and offset.dot(relative) > 0.1:
				continue
			return 100.0
		score += maxf(0.0, (spacing + 3.0 - distance) / 3.0)
	return score

func _refresh(occupants: Dictionary[String, WeakRef]) -> void:
	var frame: int = Engine.get_physics_frames()
	if _frame == frame:
		return
	_frame = frame
	_buckets.clear()
	_samples.clear()
	for id: String in occupants:
		var actor: Node2D = occupants[id].get_ref()
		if actor == null or not ActorFootprint.active(actor):
			continue
		var sample: Dictionary = {"id": id, "position": actor.global_position,
			"velocity": actor.velocity if actor is CharacterBody2D else Vector2.ZERO,
			"radius": ActorFootprint.radius(actor), "player": actor is BasePlayer}
		_samples[id] = sample
		var key := Vector2i((actor.global_position / BUCKET).floor())
		if not _buckets.has(key):
			_buckets[key] = []
		_buckets[key].append(sample)
	# A squeeze ends once the two bodies are apart again (or either left this space).
	for pair: String in _squeezes.keys():
		var ids: PackedStringArray = pair.split("|")
		var first: Dictionary = _samples.get(ids[0], {})
		var second: Dictionary = _samples.get(ids[1], {})
		if first.is_empty() or second.is_empty() or first.position.distance_to(second.position) \
				> first.radius + second.radius + PRESS_RANGE + 2.0:
			_end_squeeze(pair)

# Counts how long the walker has been held up against the same body in its way, and lets it slip
# past once that reaches SQUEEZE_WAIT. Free steps (a replanned step back) wear the count down
# instead of resetting it; it resets when no body presses on the walker any more.
func _press(occupants: Dictionary[String, WeakRef], id: String, position: Vector2,
		desired: Vector2, motion: Vector2, delta: float) -> void:
	var pressed: Dictionary = _pressed.get(id, {})
	var radius: float = _samples.get(id, {}).get("radius", 0.0)
	var blocker: Dictionary = {}
	for other: Dictionary in _neighbors(id, position):
		var offset: Vector2 = other.position - position
		if other.player or offset.length() > radius + other.radius + PRESS_RANGE \
				or _squeezes.has(_pair(id, other.id)) or _squeezes.has(_pair(other.id, id)):
			continue
		if other.id == pressed.get("by"):
			blocker = other
			break
		if blocker.is_empty() and offset.dot(desired) > 0.0:
			blocker = other
	if blocker.is_empty():
		_pressed.erase(id)
		return
	if blocker.id != pressed.get("by"):
		pressed = {"by": blocker.id, "time": 0.0}
		_pressed[id] = pressed
	var held_up: bool = motion.dot(desired) < desired.length_squared() * 0.2
	pressed.time = pressed.time + delta if held_up else maxf(0.0, pressed.time - delta)
	if pressed.time < SQUEEZE_WAIT:
		return
	_pressed.erase(id)
	var walker: PhysicsBody2D = occupants[id].get_ref() as PhysicsBody2D
	var body: PhysicsBody2D = occupants[blocker.id].get_ref() as PhysicsBody2D
	if walker != null and body != null:
		walker.add_collision_exception_with(body)
		body.add_collision_exception_with(walker)
		_squeezes[_pair(id, blocker.id)] = [weakref(walker), weakref(body)]

func _end_squeeze(pair: String) -> void:
	var bodies: Array = _squeezes[pair]
	_squeezes.erase(pair)
	var walker: PhysicsBody2D = bodies[0].get_ref() as PhysicsBody2D
	var body: PhysicsBody2D = bodies[1].get_ref() as PhysicsBody2D
	if walker != null and body != null:
		walker.remove_collision_exception_with(body)
		body.remove_collision_exception_with(walker)

static func _pair(walker: String, body: String) -> String:
	return walker + "|" + body

func _neighbors(id: String, position: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var center := Vector2i((position / BUCKET).floor())
	for y: int in range(-1, 2):
		for x: int in range(-1, 2):
			for sample: Dictionary in _buckets.get(center + Vector2i(x, y), []):
				if sample.id != id and position.distance_squared_to(sample.position) < BUCKET * BUCKET:
					if position.distance_squared_to(sample.position) < 0.001:
						var separated: Dictionary = sample.duplicate()
						separated.position += Vector2(0.05 if sample.id > id else -0.05, 0)
						result.append(separated)
					else:
						result.append(sample)
	return result
