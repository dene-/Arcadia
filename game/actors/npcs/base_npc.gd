class_name BaseNpc
extends BaseActor

## Reusable NPC actor with a simple state machine, interaction placeholder, and combat areas.

const DropTableEntryResource = preload("res://game/items/drops/drop_table_entry.gd")

signal interacted(interactor: Node)

const RUN_ANIMATION_NAME: StringName = &"run"
const WALK_ANIMATION_NAME: StringName = &"walk"
const MEMORY_DEBUG_PROPERTIES: Dictionary[String, int] = {
	"npc_id": TYPE_STRING, "status": TYPE_STRING, "turn": TYPE_INT,
	"memories": TYPE_ARRAY, "recent_dialogue": TYPE_ARRAY,
	"relationship": TYPE_DICTIONARY, "recent_events": TYPE_ARRAY, "observations": TYPE_ARRAY,
}

## Data resource containing movement, combat, AI, interaction, and animation tuning.
@export var npc_data: NpcData

var spawn_position: Vector2 = Vector2.ZERO
var patrol_target: Vector2 = Vector2.ZERO
var current_move_direction: Vector2 = Vector2.ZERO
var state_time_remaining: float = 0.0
var daily_routine: NpcDailyRoutine
var life_context: Dictionary = {}
var life_revision: int = 0
var _awake_sprite_position: Vector2
var _awake_interaction_position: Vector2
var _awake_hurt_position: Vector2
var _awake_sprite_z: int
var _sleep_center := Vector2(0, -20)
var _sleeping: bool = false
var _woke_at: int = -90001
var _woke_world_minute: float = -100.0
var _woke_space: StringName
var _wake_reason: String = ""

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _patrol_index: int = 0
var _pending_death: bool = false
var _hurt_knockback_velocity: Vector2 = Vector2.ZERO
var _dialog_locked: bool = false
var _target: Node2D
var _target_attack_side_sign: int = 1
var _attack_cooldown_remaining: float = 0.0
var _drops_spawned: bool = false
var _reaction_cooldown_until: int = 0

@onready var blood_particles: CPUParticles2D = $BloodParticles
@onready var interaction_area: Area2D = $InteractionArea
@onready var body_collision_shape: CollisionShape2D = $CollisionShape2D

# -- Lifecycle ----------------------------------------------------------------

func _ready() -> void:
	assert(npc_data != null, "BaseNpc requires an NpcData resource.")
	assert(npc_data.sprite_frames != null, "BaseNpc requires a SpriteFrames resource.")

	var cognition: Node = get_node("/root/NpcCognition")
	var profile: NpcProfile = get_npc_profile()
	if profile != null and cognition.save_game.is_dead(profile.npc_id):
		# No death animation, event, loot or provider call is replayed during loading.
		hide()
		process_mode = Node.PROCESS_MODE_DISABLED
		queue_free()
		return

	spawn_position = global_position
	_rng.randomize()
	if npc_data.ai_enabled:
		add_to_group("enemies")
	setup_actor(
		npc_data.max_health,
		npc_data.starting_facing,
		npc_data.sprite_frames,
		npc_data.combat_layers,
		npc_data.attack_damage
	)
	_configure_blood_particles()
	_connect_dialog_manager()

	add_to_group("interactables")
	interaction_area.monitoring = npc_data.interaction_enabled
	interaction_area.monitorable = npc_data.interaction_enabled

	state_machine.initialize(self)
	if get_npc_profile() != null and not get_npc_profile().npc_id.is_empty():
		add_to_group(&"npc_observers")
		get_node("/root/NpcCognition").resume(self)

# -- Dialog & interaction -----------------------------------------------------

func interact(interactor: Node = null) -> void:
	if health <= 0 or not npc_data.interaction_enabled:
		return

	var dialog_manager := get_node_or_null("/root/DialogManager")
	if dialog_manager != null:
		dialog_manager.call("request_npc_dialog", self)
	interacted.emit(interactor)

func get_dialog_text() -> String:
	return ""

func get_backend_profile() -> Dictionary:
	if npc_data == null or npc_data.profile == null:
		return {}
	return npc_data.profile.to_backend_profile()

func get_npc_profile() -> NpcProfile:
	return npc_data.profile if npc_data != null else null

func get_perceived_name() -> String:
	var profile: NpcProfile = get_npc_profile()
	if profile != null:
		return "a person"
	return "a hostile creature" if npc_data != null and npc_data.ai_enabled else "a creature"

func can_speak_reaction() -> bool:
	return health > 0 and not _dialog_locked and not _sleeping \
		and Time.get_ticks_msec() >= _reaction_cooldown_until

func reserve_spoken_reaction() -> bool:
	if not can_speak_reaction():
		return false
	_reaction_cooldown_until = Time.get_ticks_msec() + int(npc_data.reaction_cooldown * 1000.0)
	return true

func show_spoken_reaction(text: String) -> bool:
	if health <= 0 or _dialog_locked or _sleeping:
		return false
	var bubble: Node2D = get_node_or_null("ReactionBubble") as Node2D
	if bubble == null:
		return false
	bubble.call("say", text)
	if get_npc_profile() != null:
		get_node("/root/WorldEvents").publish(WorldEvent.speech(self, text))
	return true

func get_cognitive_context() -> Dictionary:
	var profile: NpcProfile = get_npc_profile()
	var current: Dictionary = {"location": profile.home if profile != null else "",
		"activity": "conversation" if _dialog_locked else String(state_machine.get_current_state_name()),
		"physical_state": "injured" if health < max_health else "well",
		"sensory_cues": []}
	current.merge(life_context.duplicate(true), true)
	current.player_identity = preload("res://game/resources/actors/player_data.tres").social_identity()
	if is_inside_tree():
		if profile != null:
			current.recent_ambient = get_node("/root/NpcCognition").ambient.recent(String(profile.npc_id))
		var players: Array[Node] = get_tree().get_nodes_in_group(&"players")
		if not players.is_empty() and players[0] is BasePlayer:
			current.player_identity = players[0].get_social_identity()
	if daily_routine != null:
		current.merge(daily_routine.context(global_position), true)
		if _dialog_locked:
			current.activity = "conversation (interrupted " + daily_routine.activity + ")"
	current.world_space = String(world_space)
	current.location = world_space_label
	current.sleeping = _sleeping
	var awake_minutes: float = float(current.get("world_minute", 0)) - _woke_world_minute
	current.recently_awakened = not _sleeping and world_space == _woke_space \
		and awake_minutes >= 0 and awake_minutes < 5 and Time.get_ticks_msec() - _woke_at < 30000
	current.wake_reason = _wake_reason if current.recently_awakened else ""
	return current

func can_follow_routine() -> bool:
	return health > 0 and not _dialog_locked and state_machine.get_current_state_name() in [&"idle", &"walk", &"run", &"sleep"]

func sleep_at(center: Vector2) -> void:
	_sleep_center = center - global_position
	state_machine.transition_to(&"sleep", {}, true)

func show_sleep_pose(sleeping: bool) -> void:
	_sleeping = sleeping
	var indicator: Label = get_node_or_null("SleepIndicator")
	if indicator != null:
		indicator.visible = sleeping
	if sleeping:
		_wake_reason = ""
		_awake_sprite_position = animated_sprite.position
		_awake_sprite_z = animated_sprite.z_index
		_awake_interaction_position = interaction_area.position
		_awake_hurt_position = hurt_box.position
		# The bed supplies solid collision; interaction and damage follow the visible sleeper.
		body_collision_shape.set_deferred("disabled", true)
		interaction_area.position = _sleep_center + Vector2(0, 4)
		hurt_box.position = _sleep_center
		play_animation(&"idle", true, 1.0)
		animated_sprite.pause()
		animated_sprite.rotation = -PI / 2
		var frame: Texture2D = animated_sprite.sprite_frames.get_frame_texture(animated_sprite.animation, 0)
		var visible_pixels: Rect2i = frame.get_image().get_used_rect()
		var center: Vector2 = Vector2(visible_pixels.position) + Vector2(visible_pixels.size) * 0.5 - frame.get_size() * 0.5
		if animated_sprite.flip_h:
			center.x = -center.x
		animated_sprite.position = (_sleep_center - center.rotated(animated_sprite.rotation)).round()
		animated_sprite.z_index = 1
		if indicator != null:
			indicator.position = (_sleep_center + Vector2(5, -14)).round()
	else:
		_woke_at = Time.get_ticks_msec()
		_woke_world_minute = float(life_context.get("world_minute", 0))
		_woke_space = world_space
		body_collision_shape.set_deferred("disabled", health <= 0)
		interaction_area.position = _awake_interaction_position
		hurt_box.position = _awake_hurt_position
		animated_sprite.rotation = 0
		animated_sprite.position = _awake_sprite_position
		animated_sprite.z_index = _awake_sprite_z

func is_sleeping() -> bool:
	return _sleeping

func wake_from_noise(reason: String = "noise") -> void:
	if _sleeping:
		_wake_reason = reason
		life_revision += 1
		state_machine.transition_to(&"idle", {}, true)

func is_able_to_chat() -> bool:
	return npc_data != null and npc_data.able_to_chat

func enter_dialog() -> void:
	if state_machine.is_in_state(&"dead"):
		return

	_dialog_locked = true
	if _sleeping:
		_wake_reason = "conversation"
	life_revision += 1
	var bubble: Node2D = get_node_or_null("ReactionBubble") as Node2D
	if bubble != null:
		bubble.hide()
	set_hitbox_enabled(false)
	clear_hit_reaction()
	state_machine.transition_to(&"interaction", {}, true)

func exit_dialog() -> void:
	if not _dialog_locked:
		return

	_dialog_locked = false
	if state_machine.is_in_state(&"dead"):
		return

	state_machine.transition_to(&"idle", {}, true)

func interrupt_for_safety() -> void:
	if _dialog_locked:
		get_node("/root/DialogManager").interrupt_source(self)
	wake_from_noise("danger")

func get_interaction_prompt() -> String:
	return npc_data.interaction_text

func get_interaction_area() -> Area2D:
	return interaction_area

# -- Combat -------------------------------------------------------------------

func request_attack() -> void:
	if state_machine.is_in_state(&"dead"):
		return

	state_machine.transition_to(&"attack", {}, true)

func take_damage(amount: int = 1, source: Area2D = null) -> void:
	if health <= 0 or state_machine.is_in_state(&"dead"):
		return

	if amount > 0:
		wake_from_noise("injury")
	set_health(health - maxi(amount, 0))
	if amount > 0:
		life_revision += 1
		report_damage_event(source)
	apply_hit_reaction(source)
	set_hitbox_enabled(false)
	if health <= 0:
		_pending_death = true
		hurt_box.set_deferred("monitoring", false)
		hurt_box.set_deferred("monitorable", false)
		state_machine.transition_to(&"hurt", {}, true)
		return

	_pending_death = false
	state_machine.transition_to(&"hurt", {}, true)

func die() -> void:
	if state_machine.is_in_state(&"dead"):
		return

	_pending_death = false
	var bubble: Node2D = get_node_or_null("ReactionBubble") as Node2D
	if bubble != null:
		bubble.hide()
	_spawn_drops()
	set_hitbox_enabled(false)
	clear_hit_reaction()
	body_collision_shape.set_deferred("disabled", true)
	hit_box.set_deferred("monitoring", false)
	hit_box.set_deferred("monitorable", false)
	hurt_box.set_deferred("monitoring", false)
	hurt_box.set_deferred("monitorable", false)
	_emit_health_changed()
	state_machine.transition_to(&"dead", {}, true)
	velocity = Vector2.ZERO
	died.emit()

func is_pending_death() -> bool:
	return _pending_death

func set_hitbox_enabled(enabled: bool) -> void:
	if npc_data != null:
		_set_attack_damage(npc_data.attack_damage)
	super.set_hitbox_enabled(enabled)

func apply_hit_reaction(source: Area2D) -> void:
	var reaction_direction := _get_hit_reaction_direction(source)
	_hurt_knockback_velocity = reaction_direction * npc_data.hurt_knockback_speed
	current_move_direction = Vector2.ZERO
	_emit_blood_particles(reaction_direction)

func clear_hit_reaction() -> void:
	_hurt_knockback_velocity = Vector2.ZERO

func apply_hurt_reaction(delta: float) -> void:
	apply_velocity(_hurt_knockback_velocity)
	_hurt_knockback_velocity = _hurt_knockback_velocity.move_toward(
		Vector2.ZERO,
		npc_data.hurt_knockback_friction * delta
	)

# -- Enemy AI -----------------------------------------------------------------

func update_enemy_ai(delta: float) -> StringName:
	if not npc_data.ai_enabled:
		return &""

	_attack_cooldown_remaining = maxf(_attack_cooldown_remaining - delta, 0.0)
	_refresh_target()
	if _target == null:
		return &""

	var target_position := _target.global_position
	var target_offset := target_position - global_position
	var target_distance := target_offset.length()
	if target_distance > npc_data.lose_interest_range:
		_target = null
		current_move_direction = Vector2.ZERO
		return &"idle"

	if is_in_lateral_attack_position(target_position):
		current_move_direction = Vector2.ZERO
		set_facing_from_direction(target_offset)
		if _attack_cooldown_remaining <= 0.0:
			_attack_cooldown_remaining = npc_data.attack_cooldown
			return &"attack"
		return &"idle"

	if not can_see_target(_target):
		if target_distance > npc_data.detection_range:
			_target = null
			current_move_direction = Vector2.ZERO
			return &"idle"
		return &""

	current_move_direction = _get_direction_to_lateral_attack_position(target_position)
	_set_facing_toward_target(target_position)
	return &"run"

func get_enemy_chase_direction() -> Vector2:
	if _target == null or not is_instance_valid(_target):
		current_move_direction = Vector2.ZERO
		return Vector2.ZERO

	var target_position := _target.global_position
	if is_in_lateral_attack_position(target_position):
		current_move_direction = Vector2.ZERO
		return Vector2.ZERO

	current_move_direction = _get_direction_to_lateral_attack_position(target_position)
	_set_facing_toward_target(target_position)
	return current_move_direction

func get_enemy_chase_velocity(delta: float) -> Vector2:
	var direction := get_enemy_chase_direction()
	if direction == Vector2.ZERO or delta <= 0.0:
		return Vector2.ZERO
	# Reach the slot without stepping past it, including when spacing equals attack range.
	var distance := global_position.distance_to(get_lateral_attack_position(_target.global_position))
	return direction * minf(current_run_speed(), distance / delta)

func get_lateral_attack_position(target_position: Vector2) -> Vector2:
	var side_sign := _get_attack_side_sign(target_position)
	return target_position + Vector2(float(side_sign) * _get_attack_side_offset(), 0.0)

func is_in_lateral_attack_position(target_position: Vector2) -> bool:
	var target_offset := target_position - global_position
	if absf(target_offset.y) > npc_data.attack_vertical_tolerance:
		return false

	var horizontal_distance := absf(target_offset.x)
	var attack_side_offset := _get_attack_side_offset()
	var minimum_horizontal_distance := maxf(
		attack_side_offset - npc_data.attack_slot_arrival_distance,
		maxf(npc_data.soft_collision_distance, 1.0)
	)
	minimum_horizontal_distance = minf(minimum_horizontal_distance, npc_data.attack_range)
	return (
		horizontal_distance >= minimum_horizontal_distance
		and horizontal_distance <= npc_data.attack_range
	)

func can_see_target(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return false

	var distance := global_position.distance_to(target.global_position)
	if distance > npc_data.detection_range:
		return false

	if not npc_data.require_line_of_sight:
		return true

	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		global_position + npc_data.line_of_sight_origin_offset,
		target.global_position + npc_data.line_of_sight_target_offset,
		npc_data.line_of_sight_collision_mask
	)
	query.exclude = [get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return true

	var collider := hit.get("collider") as Node
	return collider == target or (collider != null and target.is_ancestor_of(collider))

# -- Movement & patrol --------------------------------------------------------

func choose_idle_duration() -> float:
	if daily_routine != null:
		return 0.2
	var minimum := minf(npc_data.idle_duration_range.x, npc_data.idle_duration_range.y)
	var maximum := maxf(npc_data.idle_duration_range.x, npc_data.idle_duration_range.y)
	return _rng.randf_range(minimum, maximum)

func choose_roam_state() -> StringName:
	if daily_routine != null:
		return &"walk"
	if npc_data.roam_radius <= 0.0 and npc_data.patrol_points.is_empty():
		return &"idle"

	if _rng.randf() <= clampf(npc_data.run_chance, 0.0, 1.0):
		return &"run"

	return &"walk"

func choose_next_patrol_target() -> bool:
	if daily_routine != null:
		return daily_routine.has_route(global_position)
	if not npc_data.patrol_points.is_empty():
		patrol_target = to_global(npc_data.patrol_points[_patrol_index % npc_data.patrol_points.size()])
		_patrol_index += 1
		return true

	if npc_data.roam_radius <= 0.0:
		patrol_target = global_position
		current_move_direction = Vector2.ZERO
		return false

	var angle := _rng.randf_range(0.0, TAU)
	var distance := _rng.randf_range(npc_data.roam_radius * 0.35, npc_data.roam_radius)
	patrol_target = spawn_position + Vector2.RIGHT.rotated(angle) * distance
	return true

func get_move_direction_to_target() -> Vector2:
	if daily_routine != null:
		current_move_direction = daily_routine.direction(global_position)
		if current_move_direction != Vector2.ZERO:
			set_facing_from_direction(current_move_direction)
		return current_move_direction
	var offset := patrol_target - global_position
	if offset.length() <= npc_data.arrival_distance:
		current_move_direction = Vector2.ZERO
		return Vector2.ZERO

	current_move_direction = offset.normalized()
	set_facing_from_direction(current_move_direction)
	return current_move_direction

func has_reached_patrol_target() -> bool:
	if daily_routine != null:
		return not daily_routine.has_route(global_position)
	return global_position.distance_to(patrol_target) <= npc_data.arrival_distance

func current_walk_speed() -> float:
	return npc_data.move_speed

func current_run_speed() -> float:
	return npc_data.move_speed * npc_data.run_speed_multiplier

func apply_action_velocity(stop_movement: bool) -> void:
	if stop_movement:
		apply_velocity(Vector2.ZERO)
		return

	apply_velocity(current_move_direction * npc_data.move_speed * npc_data.action_speed_multiplier)

func set_facing_from_direction(direction: Vector2) -> void:
	if direction.x < 0.0:
		facing = Facing.LEFT
	elif direction.x > 0.0:
		facing = Facing.RIGHT
	_update_hit_box_facing()

# -- Animation ----------------------------------------------------------------

func resolve_animation_name(animation_name: StringName) -> StringName:
	if npc_data.sprite_frames == null:
		return &""

	if npc_data.sprite_frames.has_animation(animation_name):
		return animation_name

	if animation_name == RUN_ANIMATION_NAME and npc_data.sprite_frames.has_animation(WALK_ANIMATION_NAME):
		return WALK_ANIMATION_NAME

	return &""

# -- Private helpers ----------------------------------------------------------

## Runtime-only properties, polled by the Remote Inspector without mutating the save.
func _get_property_list() -> Array[Dictionary]:
	if Engine.is_editor_hint() or not OS.is_debug_build():
		return []
	var properties: Array[Dictionary] = [{"name": "Runtime Memory", "type": TYPE_NIL,
		"usage": PROPERTY_USAGE_GROUP, "hint_string": "runtime_memory_"}]
	for field: String in MEMORY_DEBUG_PROPERTIES:
		properties.append({"name": "runtime_memory_" + field,
			"type": MEMORY_DEBUG_PROPERTIES[field],
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY})
	properties.append({"name": "Town Life", "type": TYPE_NIL,
		"usage": PROPERTY_USAGE_GROUP, "hint_string": "runtime_life"})
	properties.append({"name": "runtime_life", "type": TYPE_DICTIONARY,
		"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY})
	return properties

func _get(property: StringName) -> Variant:
	if property == &"runtime_life":
		var snapshot: Dictionary = life_context.duplicate(true)
		if daily_routine != null:
			snapshot.merge(daily_routine.context(global_position), true)
			snapshot.position = global_position
			snapshot.destination_position = daily_routine.destination
		return snapshot
	if not String(property).begins_with("runtime_memory_"):
		return null
	var field: String = String(property).trim_prefix("runtime_memory_")
	if not MEMORY_DEBUG_PROPERTIES.has(field):
		return null
	var profile: NpcProfile = get_npc_profile()
	var id: String = String(profile.npc_id) if profile != null else ""
	var cognition: Node = get_node_or_null("/root/NpcCognition") if is_inside_tree() else null
	var store: NpcMemoryStore = cognition.store if cognition != null else null
	var state: Dictionary = store.snapshot(id) if store != null and not id.is_empty() else {}
	match field:
		"npc_id":
			return id
		"status":
			if id.is_empty():
				return "No NPC profile or stable ID."
			if store == null:
				return "Memory store unavailable."
			return "Not initialized yet." if state.is_empty() else "Live memory state."
		"turn":
			return store.turn if store != null else 0
		"relationship":
			return state.get(field, {})
		_:
			return state.get(field, [])

func _configure_blood_particles() -> void:
	blood_particles.amount = npc_data.blood_particle_count
	blood_particles.lifetime = npc_data.blood_particle_lifetime
	blood_particles.spread = npc_data.blood_particle_spread_degrees
	blood_particles.initial_velocity_min = npc_data.blood_particle_speed * 0.65
	blood_particles.initial_velocity_max = npc_data.blood_particle_speed
	blood_particles.gravity = Vector2.DOWN * npc_data.blood_particle_gravity
	blood_particles.color = npc_data.blood_color

func _connect_dialog_manager() -> void:
	var dialog_manager := get_node_or_null("/root/DialogManager")
	if dialog_manager == null:
		return

	if not dialog_manager.is_connected("dialog_started", _on_dialog_started):
		dialog_manager.connect("dialog_started", _on_dialog_started)
	if not dialog_manager.is_connected("dialog_finished", _on_dialog_finished):
		dialog_manager.connect("dialog_finished", _on_dialog_finished)

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

func _emit_blood_particles(direction: Vector2) -> void:
	if npc_data.blood_particle_count <= 0:
		return
	blood_particles.global_position = global_position + Vector2(0.0, -1.0)
	blood_particles.reset_physics_interpolation()
	blood_particles.direction = direction
	blood_particles.emitting = false
	blood_particles.restart()
	blood_particles.emitting = true

func _receive_hit(area: Area2D, damage: int) -> void:
	take_damage(damage, area)

func _refresh_target() -> void:
	if _target != null and is_instance_valid(_target):
		if can_see_target(_target) or global_position.distance_to(_target.global_position) <= npc_data.lose_interest_range:
			return

	_target = null
	var closest_target: Node2D
	var closest_distance_sq := npc_data.detection_range * npc_data.detection_range
	for node: Node in get_tree().get_nodes_in_group(npc_data.target_group):
		var candidate := node as Node2D
		if candidate == null or not is_instance_valid(candidate):
			continue

		var distance_sq := global_position.distance_squared_to(candidate.global_position)
		if distance_sq > closest_distance_sq:
			continue
		if not can_see_target(candidate):
			continue

		closest_target = candidate
		closest_distance_sq = distance_sq

	_target = closest_target
	if _target != null:
		_target_attack_side_sign = _get_attack_side_sign(_target.global_position)

func _get_direction_to_lateral_attack_position(target_position: Vector2) -> Vector2:
	var attack_position := get_lateral_attack_position(target_position)
	var offset := attack_position - global_position
	# Attack readiness owns arrival tolerance; proximity alone can still be too close,
	# out of range or vertically misaligned.
	return offset.normalized()

func _get_attack_side_offset() -> float:
	var preferred_offset := maxf(npc_data.attack_side_offset, npc_data.soft_collision_distance)
	return minf(preferred_offset, npc_data.attack_range)

func _get_attack_side_sign(target_position: Vector2) -> int:
	var horizontal_offset := global_position.x - target_position.x
	if horizontal_offset < 0.0:
		_target_attack_side_sign = -1
	elif horizontal_offset > 0.0:
		_target_attack_side_sign = 1
	elif facing == Facing.LEFT:
		_target_attack_side_sign = -1
	else:
		_target_attack_side_sign = 1

	return _target_attack_side_sign

func _set_facing_toward_target(target_position: Vector2) -> void:
	var target_offset := target_position - global_position
	if not is_zero_approx(target_offset.x):
		set_facing_from_direction(target_offset)
		return

	set_facing_from_direction(Vector2(float(_target_attack_side_sign) * -1.0, 0.0))

func _spawn_drops() -> void:
	if _drops_spawned or npc_data.drop_table == null:
		return

	_drops_spawned = true
	for raw_entry: DropTableEntryResource in npc_data.drop_table.entries:
		var entry := raw_entry as DropTableEntryResource
		if entry == null or entry.item == null or entry.drop_scene == null:
			continue
		var drop_chance := clampf(entry.chance, 0.0, 1.0)
		if drop_chance <= 0.0:
			continue
		if drop_chance < 1.0 and _rng.randf() > drop_chance:
			continue

		var minimum := mini(entry.min_count, entry.max_count)
		var maximum := maxi(entry.min_count, entry.max_count)
		var count := _rng.randi_range(minimum, maximum)
		var drop := entry.drop_scene.instantiate() as Node2D
		if drop == null:
			continue

		if drop.has_method("configure"):
			drop.call("configure", entry.item, count)

		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(0.0, npc_data.drop_table.scatter_radius)
		var parent := get_parent()
		if parent != null:
			parent.add_child(drop)
		else:
			get_tree().current_scene.add_child(drop)
		drop.global_position = global_position + Vector2.RIGHT.rotated(angle) * distance
		drop.reset_physics_interpolation()

# -- Signal callbacks ---------------------------------------------------------

func _on_dialog_started(source: Node, _text: String) -> void:
	if source != self:
		return

	enter_dialog()

func _on_dialog_finished(source: Node) -> void:
	if source != self:
		return

	exit_dialog()
