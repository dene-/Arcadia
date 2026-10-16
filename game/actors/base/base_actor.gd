class_name BaseActor
extends CharacterBody2D

## Shared CharacterBody2D mechanics for player and NPC actor scenes.

signal state_changed(new_state: StringName)
signal attack_connected(target: Area2D)
signal hurtbox_triggered(source: Area2D)
signal health_changed(current_health: int, max_health: int)
signal died

enum Facing {
	LEFT,
	RIGHT,
}

## Heading up the screen above this sine turns the actor to show its back.
const UP_FACING_ENTER: float = 0.5
## Heading below this sine brings the front view back.
const UP_FACING_EXIT: float = 0.2
## Seconds a freshly hit actor stays whitened.
const HIT_FLASH_SECONDS: float = 0.1
## Overbright modulate: texture colors are multiplied, so the whole figure reads white.
const HIT_FLASH_TINT := Color(3.0, 3.0, 3.0)

var facing: Facing = Facing.RIGHT
## True while the actor looks up the screen, selecting "<animation>_up" variants.
var facing_up: bool = false
var max_health: int = 1
var health: int = 1
## Rooms share a running simulation but remain separate sensory and interaction spaces.
var world_space: StringName = &"outdoors"
var world_space_label: String = "Rekala"
var movement_navigation: TownNavigation
var movement_id: String = ""

var _attack_hitbox_enabled: bool = false
var _current_attack_damage: int = 1
var _hit_box_shape_base_position: Vector2 = Vector2.ZERO
var _sprite_frames: SpriteFrames
var _hit_targets: Dictionary[int, bool] = {}
var _hit_flash_remaining: float = 0.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hit_box: Area2D = $HitBox
@onready var hit_box_shape: CollisionShape2D = $HitBox/CollisionShape2D
@onready var hurt_box: Area2D = $HurtBox
@onready var state_machine: StateMachine = $StateMachine

func _physics_process(delta: float) -> void:
	state_machine.physics_update(delta)
	_update_sprite_tint(delta)

func setup_actor(
	max_health: int,
	starting_facing: int,
	sprite_frames: SpriteFrames,
	combat_layers: CombatLayers,
	attack_damage: int
) -> void:
	ActorFootprint.configure(self)
	add_to_group(&"actors")
	var navigation_world: Node = get_tree().get_first_node_in_group(&"actor_navigation_world")
	if navigation_world != null:
		navigation_world.register_actor.call_deferred(self)
	facing = Facing.LEFT if starting_facing == Facing.LEFT else Facing.RIGHT
	self.max_health = maxi(max_health, 1)
	health = self.max_health
	_sprite_frames = sprite_frames
	_current_attack_damage = attack_damage

	if _sprite_frames.has_method("ensure_built"):
		_sprite_frames.call("ensure_built")
	animated_sprite.sprite_frames = _sprite_frames

	_hit_box_shape_base_position = hit_box_shape.position
	if combat_layers != null:
		hit_box.collision_layer = combat_layers.hit_box_layer
		hit_box.collision_mask = combat_layers.hit_box_mask
		hurt_box.collision_layer = combat_layers.hurt_box_layer
		hurt_box.collision_mask = combat_layers.hurt_box_mask
	_update_hit_box_facing()

	hit_box.add_to_group("hitboxes")
	hurt_box.add_to_group("hurtboxes")
	hit_box.monitorable = true
	set_hitbox_enabled(false)
	_connect_actor_signals()
	call_deferred("_emit_health_changed")

func _exit_tree() -> void:
	if movement_navigation != null:
		movement_navigation.release(movement_id)

func set_hitbox_enabled(enabled: bool) -> void:
	if enabled and not _attack_hitbox_enabled:
		_hit_targets.clear()
	_attack_hitbox_enabled = enabled
	hit_box.set_meta("owner", self)
	hit_box.set_meta("damage", _current_attack_damage)
	# Keep the area discoverable and toggle its geometry. Changing monitorable during
	# a swing can deliver contact only after deactivation, too late to accept the hit.
	hit_box_shape.set_deferred("disabled", not enabled)

func apply_velocity(next_velocity: Vector2) -> void:
	velocity = next_velocity
	move_and_slide()

func has_clear_melee_path(target: Node2D) -> bool:
	if not is_instance_valid(target) or not is_inside_tree():
		return false
	if target is BaseActor and target.world_space != world_space:
		return false
	var ray := PhysicsRayQueryParameters2D.create(global_position, target.global_position, ActorFootprint.WORLD)
	ray.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()

## The receiver consumes contact once per swing, including exit/re-entry caused by sliding.
func consume_melee_hit(target: BaseActor) -> bool:
	var id: int = target.get_instance_id()
	if not _attack_hitbox_enabled or _hit_targets.has(id) or not has_clear_melee_path(target):
		return false
	_hit_targets[id] = true
	attack_connected.emit(target.hurt_box)
	return true

func set_health(next_health: int) -> void:
	var clamped_health := clampi(next_health, 0, max_health)
	if health == clamped_health:
		return

	health = clamped_health
	_emit_health_changed()

func get_perceived_name() -> String:
	return "the player" if is_in_group("players") else "someone"

## Deliver successful damage once, while the participants still exist in the world.
func report_damage_event(source: Area2D) -> void:
	var attacker: BaseActor
	if is_instance_valid(source):
		var source_owner: Variant = source.get_meta("owner", null)
		if is_instance_valid(source_owner):
			attacker = source_owner as BaseActor
	get_node("/root/WorldEvents").publish(WorldEvent.damage(self, attacker))

func play_animation(animation_name: StringName, restart: bool = false, speed_scale: float = 1.0) -> void:
	var resolved_animation := _directional_animation(resolve_animation_name(animation_name))
	if resolved_animation.is_empty():
		return

	animated_sprite.speed_scale = speed_scale
	animated_sprite.flip_h = _should_flip_sprite(resolved_animation)

	if restart:
		animated_sprite.play(resolved_animation)
		return

	if animated_sprite.animation != resolved_animation:
		_switch_animation(resolved_animation)
	elif not animated_sprite.is_playing():
		animated_sprite.play()

## Face away from the camera while heading up the screen. The band between the two
## thresholds keeps the current view so a wobbling path does not flicker between rows.
func set_vertical_facing(direction: Vector2) -> void:
	if direction.length_squared() <= 0.0001:
		return
	var rise: float = -direction.normalized().y
	if rise > UP_FACING_ENTER:
		facing_up = true
	elif rise < UP_FACING_EXIT:
		facing_up = false

func stop_animation() -> void:
	animated_sprite.stop()

func resolve_animation_name(animation_name: StringName) -> StringName:
	if _sprite_frames == null:
		return &""

	if _sprite_frames.has_animation(animation_name):
		return animation_name

	return &""

func _set_attack_damage(damage: int) -> void:
	_current_attack_damage = damage
	hit_box.set_meta("damage", _current_attack_damage)

func _emit_health_changed() -> void:
	health_changed.emit(health, max_health)

func _receive_hit(_area: Area2D, _damage: int) -> void:
	pass

func _connect_actor_signals() -> void:
	if not animated_sprite.animation_finished.is_connected(_on_animated_sprite_2d_animation_finished):
		animated_sprite.animation_finished.connect(_on_animated_sprite_2d_animation_finished)
	if not hurt_box.area_entered.is_connected(_on_hurt_box_area_entered):
		hurt_box.area_entered.connect(_on_hurt_box_area_entered)
	if not state_machine.transitioned.is_connected(_on_state_machine_transitioned):
		state_machine.transitioned.connect(_on_state_machine_transitioned)

func _update_hit_box_facing() -> void:
	var horizontal_offset := absf(_hit_box_shape_base_position.x)
	if facing == Facing.LEFT:
		horizontal_offset *= -1.0
	hit_box_shape.position = Vector2(horizontal_offset, _hit_box_shape_base_position.y)

func _should_flip_sprite(animation_name: StringName) -> bool:
	var source_faces_right := false
	if _sprite_frames != null and _sprite_frames.has_method("source_faces_right"):
		source_faces_right = bool(_sprite_frames.call("source_faces_right", animation_name))

	if source_faces_right:
		return facing == Facing.LEFT

	return facing == Facing.RIGHT

func _directional_animation(animation_name: StringName) -> StringName:
	if animation_name.is_empty() or not facing_up:
		return animation_name
	var up_name := StringName(String(animation_name) + ActorSpriteFrames.UP_SUFFIX)
	return up_name if _sprite_frames.has_animation(up_name) else animation_name

## Swap to another animation, keeping the stride when only the viewing side changes.
func _switch_animation(animation_name: StringName) -> void:
	var previous: StringName = animated_sprite.animation
	var frame: int = animated_sprite.frame
	var progress: float = animated_sprite.frame_progress
	animated_sprite.play(animation_name)
	if _is_same_clip(previous, animation_name):
		animated_sprite.set_frame_and_progress(frame, progress)

func _is_same_clip(first: StringName, second: StringName) -> bool:
	if first.is_empty() or not _sprite_frames.has_animation(first):
		return false
	var suffix: String = ActorSpriteFrames.UP_SUFFIX
	var first_base: String = String(first).trim_suffix(suffix)
	var second_base: String = String(second).trim_suffix(suffix)
	return first_base == second_base \
		and _sprite_frames.get_frame_count(first) == _sprite_frames.get_frame_count(second)

func _get_area_damage(area: Area2D) -> int:
	if area.has_meta("damage"):
		return int(area.get_meta("damage"))
	return 1

## Unit vector pushing this actor away from whoever owns `source`.
func _get_hit_reaction_direction(source: Area2D) -> Vector2:
	var impact_origin := global_position - Vector2.RIGHT
	if source != null:
		if source.has_meta("owner"):
			var source_owner := source.get_meta("owner") as Node2D
			if source_owner != null:
				impact_origin = source_owner.global_position
			else:
				impact_origin = source.global_position
		else:
			impact_origin = source.global_position

	var reaction_direction := global_position - impact_origin
	if reaction_direction.length_squared() <= 0.001:
		reaction_direction = Vector2.RIGHT if facing == Facing.RIGHT else Vector2.LEFT

	return reaction_direction.normalized()

## Actors with recovery frames after a hit override this; the swing is not consumed while true.
func is_invulnerable() -> bool:
	return false

## Briefly whitens the sprite so a landed hit reads even without a hurt animation change.
func flash_hit() -> void:
	_hit_flash_remaining = HIT_FLASH_SECONDS

func _sprite_alpha() -> float:
	return 1.0

func _update_sprite_tint(delta: float) -> void:
	_hit_flash_remaining = maxf(_hit_flash_remaining - delta, 0.0)
	var tint: Color = HIT_FLASH_TINT if _hit_flash_remaining > 0.0 else Color.WHITE
	tint.a = _sprite_alpha()
	if animated_sprite.modulate != tint:
		animated_sprite.modulate = tint

func _on_animated_sprite_2d_animation_finished() -> void:
	state_machine.animation_finished()

func _on_state_machine_transitioned(current_state: StringName, _previous_state: StringName) -> void:
	state_changed.emit(current_state)

func _on_hurt_box_area_entered(area: Area2D) -> void:
	if state_machine.is_in_state(&"dead") or is_invulnerable():
		return

	if area.has_meta("owner") and area.get_meta("owner") == self:
		return

	if area == hit_box:
		return
	var attacker: Variant = area.get_meta("owner", null)
	if is_instance_valid(attacker) and attacker is BaseActor and not attacker.consume_melee_hit(self):
		return

	hurtbox_triggered.emit(area)
	if area.is_in_group("hitboxes"):
		_receive_hit(area, _get_area_damage(area))
