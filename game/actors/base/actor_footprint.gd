class_name ActorFootprint
extends RefCounted

## Physical clearance comes from the scene's feet, independently of weapon reach or social space.
const WORLD: int = 1
const ACTORS: int = 2
const MARGIN: float = 0.25

static func configure(actor: CharacterBody2D) -> void:
	var collider: CollisionShape2D = actor.get_node("CollisionShape2D")
	if collider.shape is RectangleShape2D:
		var size: Vector2 = collider.shape.size
		if is_equal_approx(size.x, size.y):
			var circle := CircleShape2D.new()
			circle.radius = size.x * 0.5
			collider.shape = circle
		else:
			var capsule := CapsuleShape2D.new()
			capsule.radius = minf(size.x, size.y) * 0.5
			capsule.height = maxf(size.x, size.y)
			collider.shape = capsule
			if size.x > size.y:
				collider.rotation += PI * 0.5
	actor.collision_layer = ACTORS
	actor.collision_mask = WORLD | ACTORS

static func radius(actor: Node2D) -> float:
	var collider: CollisionShape2D = actor.get_node_or_null("CollisionShape2D")
	if collider == null or collider.shape == null:
		return 5.0
	var size: Vector2 = collider.shape.get_rect().size * collider.global_scale.abs()
	return maxf(size.x, size.y) * 0.5

static func active(actor: Node2D) -> bool:
	if actor is BaseActor and actor.health <= 0:
		return false
	var collider: CollisionShape2D = actor.get_node_or_null("CollisionShape2D")
	return collider == null or not collider.disabled

static func clear_landing(actor: BaseActor, point: Vector2, from: Vector2 = Vector2.INF) -> bool:
	var collider: CollisionShape2D = actor.get_node("CollisionShape2D")
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collider.shape
	query.transform = collider.global_transform
	query.transform.origin += point - actor.global_position
	query.collision_mask = WORLD | ACTORS
	query.margin = MARGIN
	query.exclude = [actor.get_rid()]
	var space: PhysicsDirectSpaceState2D = actor.get_world_2d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty():
		return false
	if from == Vector2.INF:
		return true
	# Nearby alternatives may step around occupants, but never through a wall.
	query.collision_mask = WORLD
	query.transform.origin += from - point
	query.motion = point - from
	return space.cast_motion(query)[0] >= 0.999
