class_name BasePlayer
extends BaseActor

const PlayerDataResource = preload("res://game/resources/actors/player_data.gd")
const InventoryDataResource = preload("res://game/items/inventory/inventory_data.gd")
const InventoryStackDataResource = preload("res://game/items/inventory/inventory_stack_data.gd")
const DroppedItemScene: PackedScene = preload("res://game/items/drops/dropped_item.tscn")

## Shared player state, input, and helper methods for a reusable node-based state machine.

const MOVE_LEFT_ACTION: StringName = &"player_left"
const MOVE_RIGHT_ACTION: StringName = &"player_right"
const MOVE_UP_ACTION: StringName = &"player_up"
const MOVE_DOWN_ACTION: StringName = &"player_down"
const ATTACK_ACTION: StringName = &"player_attack"
const JUMP_ACTION: StringName = &"player_jump"
const RUN_ACTION: StringName = &"player_run"

## Data resource containing player movement, combat, facing, and animation tuning.
@export var player_data: PlayerDataResource
## Mutable inventory resource used for item pickups and inventory UI.
@export var inventory_data: InventoryDataResource
## Distance in front of the player where inventory drops are placed.
@export_range(8.0, 48.0, 1.0) var inventory_drop_distance: float = 16.0
## Seconds before player-dropped items can be picked up again.
@export_range(0.0, 5.0, 0.05) var inventory_drop_pickup_delay: float = 1.0

var _move_input: Vector2 = Vector2.ZERO
var move_input: Vector2:
	get:
		return _move_input
var _attack_hold_time: float = 0.0
var _dialog_locked: bool = false

@onready var pickup_area: Area2D = $PickupArea

# -- Lifecycle ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_collect_overlapping_drops()

func _ready() -> void:
	assert(player_data != null, "BasePlayer requires a PlayerData resource.")
	assert(player_data.sprite_frames != null, "BasePlayer requires a SpriteFrames resource.")
	assert(inventory_data != null, "BasePlayer requires an InventoryData resource.")

	add_to_group("players")
	setup_actor(
		player_data.max_health,
		player_data.starting_facing,
		player_data.sprite_frames,
		player_data.combat_layers,
		player_data.attack_damage
	)
	_connect_pickup_area()
	_connect_dialog_manager()
	state_machine.initialize(self)

func get_inventory_data() -> InventoryDataResource:
	return inventory_data

func set_inventory_data(next_inventory_data: InventoryDataResource) -> void:
	assert(next_inventory_data != null, "BasePlayer requires an InventoryData resource.")
	inventory_data = next_inventory_data

func drop_inventory_slot(slot_index: int) -> bool:
	return drop_inventory_stack(slot_index)

func drop_inventory_stack(slot_index: int, amount: int = -1) -> bool:
	var stack := inventory_data.drop_from_slot(slot_index, amount)
	if stack.is_empty():
		return false

	if not _spawn_inventory_drop(stack):
		inventory_data.add_item(stack.item, stack.count)
		return false

	return true

func _spawn_inventory_drop(stack: InventoryStackDataResource) -> bool:
	var drop_scene := DroppedItemScene
	if stack.item != null and stack.item.world_drop_scene != null:
		drop_scene = stack.item.world_drop_scene

	var drop := drop_scene.instantiate() as DroppedItem
	if drop == null:
		return false

	drop.configure(stack.item, stack.count, inventory_drop_pickup_delay)
	var parent := get_parent()
	if parent != null:
		parent.add_child(drop)
	else:
		get_tree().current_scene.add_child(drop)

	var drop_direction := Vector2.RIGHT if facing == Facing.RIGHT else Vector2.LEFT
	drop.global_position = global_position + drop_direction * inventory_drop_distance
	return true

# -- Combat -------------------------------------------------------------------

func take_damage(amount: int = 1) -> void:
	if state_machine.is_in_state(&"dead"):
		return

	set_health(health - maxi(amount, 0))
	reset_attack_hold()
	set_hitbox_enabled(false)
	if health <= 0:
		die()
		return

	state_machine.transition_to(&"hurt", {}, true)

func die() -> void:
	if state_machine.is_in_state(&"dead"):
		return

	reset_attack_hold()
	set_hitbox_enabled(false)
	hurt_box.set_deferred("monitoring", false)
	hurt_box.set_deferred("monitorable", false)
	_emit_health_changed()
	state_machine.transition_to(&"dead", {}, true)
	velocity = Vector2.ZERO
	died.emit()

func set_attack_damage_override(multiplier: float = 1.0) -> void:
	_set_attack_damage(maxi(int(round(float(player_data.attack_damage) * multiplier)), 1))

func reset_attack_damage_override() -> void:
	_set_attack_damage(maxi(player_data.attack_damage, 1))

func reset_attack_hold() -> void:
	_attack_hold_time = 0.0

## Reads attack input and returns the state to transition to, or &"" if none.
func consume_attack_transition(delta: float) -> StringName:
	if is_input_blocked():
		reset_attack_hold()
		return &""

	if Input.is_action_just_pressed(ATTACK_ACTION):
		_attack_hold_time = 0.0

	if Input.is_action_pressed(ATTACK_ACTION):
		_attack_hold_time += delta
		if _attack_hold_time >= player_data.charge_attack_hold_time:
			reset_attack_hold()
			return &"charge_build"
	elif _attack_hold_time > 0.0:
		reset_attack_hold()
		return &"attack"

	return &""

func is_attack_held() -> bool:
	if is_input_blocked():
		return false
	return Input.is_action_pressed(ATTACK_ACTION)

func is_jump_just_pressed() -> bool:
	if is_input_blocked():
		return false
	return Input.is_action_just_pressed(JUMP_ACTION)

func is_run_pressed() -> bool:
	if is_input_blocked():
		return false
	return Input.is_action_pressed(RUN_ACTION)

func is_input_blocked() -> bool:
	return not get_tree().get_nodes_in_group("blocking_player_input").is_empty()

func set_charged_attack_damage() -> void:
	set_attack_damage_override(player_data.charged_attack_damage_multiplier)

func current_walk_speed() -> float:
	return player_data.move_speed

func current_run_speed() -> float:
	return player_data.move_speed * player_data.run_speed_multiplier

func current_move_speed() -> float:
	return current_run_speed() if is_run_pressed() else current_walk_speed()

func current_walk_animation_speed() -> float:
	return player_data.run_animation_multiplier if is_run_pressed() else 1.0

# -- Movement -----------------------------------------------------------------

func read_move_input() -> void:
	if is_input_blocked():
		_move_input = Vector2.ZERO
		return

	_move_input = Input.get_vector(
		MOVE_LEFT_ACTION,
		MOVE_RIGHT_ACTION,
		MOVE_UP_ACTION,
		MOVE_DOWN_ACTION
	)

func has_move_input() -> bool:
	return _move_input != Vector2.ZERO

func set_facing_from_move_input() -> void:
	if _move_input.x < 0.0:
		facing = Facing.LEFT
		_update_hit_box_facing()
	elif _move_input.x > 0.0:
		facing = Facing.RIGHT
		_update_hit_box_facing()

func apply_action_velocity(stop_movement: bool) -> void:
	if stop_movement:
		apply_velocity(Vector2.ZERO)
		return
	apply_velocity(_move_input * player_data.move_speed * player_data.action_speed_multiplier)

# -- Dialog -------------------------------------------------------------------

func enter_dialog() -> void:
	if state_machine.is_in_state(&"dead"):
		return

	_dialog_locked = true
	reset_attack_hold()
	set_hitbox_enabled(false)
	state_machine.transition_to(&"interaction", {}, true)

func exit_dialog() -> void:
	if not _dialog_locked:
		return

	_dialog_locked = false
	if state_machine.is_in_state(&"dead"):
		return

	state_machine.transition_to(&"idle", {}, true)

# -- Private helpers ----------------------------------------------------------

func _connect_dialog_manager() -> void:
	var dialog_manager := get_node_or_null("/root/DialogManager")
	if dialog_manager == null:
		return

	if not dialog_manager.is_connected("dialog_started", _on_dialog_started):
		dialog_manager.connect("dialog_started", _on_dialog_started)
	if not dialog_manager.is_connected("dialog_finished", _on_dialog_finished):
		dialog_manager.connect("dialog_finished", _on_dialog_finished)

func _connect_pickup_area() -> void:
	if not pickup_area.area_entered.is_connected(_on_pickup_area_entered):
		pickup_area.area_entered.connect(_on_pickup_area_entered)

func _collect_overlapping_drops() -> void:
	for area: Area2D in pickup_area.get_overlapping_areas():
		_try_collect_drop(area)

func _try_collect_drop(area: Area2D) -> void:
	if area == null or not area.has_method("collect_into"):
		return

	area.call("collect_into", inventory_data)

func _receive_hit(_area: Area2D, damage: int) -> void:
	take_damage(damage)

# -- Signal callbacks ---------------------------------------------------------

func _on_dialog_started(_source: Node, _text: String) -> void:
	enter_dialog()

func _on_dialog_finished(_source: Node) -> void:
	exit_dialog()

func _on_pickup_area_entered(area: Area2D) -> void:
	_try_collect_drop(area)
