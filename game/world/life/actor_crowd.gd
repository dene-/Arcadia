class_name ActorCrowd
extends RefCounted

## One spatial snapshot per physics frame; steering predicts all nearby bodies, not just one.
const BUCKET: float = 48.0
const HORIZON: float = 0.4
var _frame: int = -1
var _buckets: Dictionary = {}
var _samples: Dictionary = {}
var _previous: Dictionary[String, Vector2] = {}
var _waiting: Dictionary[String, float] = {}
var neighbor_checks: int = 0
var steering_calls: int = 0
var steering_usec: int = 0

func invalidate() -> void:
	_frame = -1

func forget(id: String) -> void:
	_previous.erase(id)
	_waiting.erase(id)
	invalidate()

func steer(navigation: TownNavigation, occupants: Dictionary[String, WeakRef], id: String,
		position: Vector2, desired: Vector2, delta: float) -> Vector2:
	var started: int = Time.get_ticks_usec()
	var result: Vector2 = _steer(navigation, occupants, id, position, desired, delta)
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
	var neighbors: Array[Dictionary] = _neighbors(id, position)
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
	_waiting[id] = waited + delta if best.dot(desired) < speed * speed * 0.2 else 0.0
	# Smooth steering for autonomous bodies, but stop promptly if smoothing would cause contact.
	var smoothed: Vector2 = previous.move_toward(best, maxf(speed * 8.0, 120.0) * delta)
	if best != Vector2.ZERO and _risk(position, smoothed, radius, neighbors) < 10.0 \
		and navigation.can_travel(position, position + smoothed * minf(HORIZON, 10.0 / speed)):
		best = smoothed
	_previous[id] = best
	return best

func yield_to_player(navigation: TownNavigation, occupants: Dictionary[String, WeakRef],
		id: String, position: Vector2, delta: float) -> Vector2:
	_refresh(occupants)
	for other: Dictionary in _neighbors(id, position):
		if not other.player or other.velocity.length() < 2.0:
			continue
		var to_self: Vector2 = position - other.position
		var radius: float = _samples.get(id, {}).get("radius", navigation.clearance)
		var warning_distance: float = maxf(22, radius + other.radius + other.velocity.length() * 0.65)
		if to_self.length() > warning_distance or other.velocity.normalized().dot(to_self.normalized()) < 0.6:
			continue
		var right: Vector2 = Vector2(-other.velocity.y, other.velocity.x).normalized()
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
