extends SceneTree

var _stage: Node2D
var _player: BasePlayer
var _enemy: BaseNpc
var _failures: Array[String] = []
var _swings: int = 0

func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if not arguments.is_empty():
		Engine.physics_ticks_per_second = int(arguments[0])
	_run.call_deferred()

func _setup() -> void:
	_stage = Node2D.new()
	root.add_child(_stage)
	_player = load("res://game/actors/player/base_player.tscn").instantiate()
	_player.player_data = _player.player_data.duplicate()
	_player.player_data.max_health = 100
	_player.player_data.starting_facing = BaseActor.Facing.RIGHT
	_stage.add_child(_player)
	_enemy = load("res://game/actors/enemies/scenes/goblin.tscn").instantiate()
	_enemy.npc_data = _enemy.npc_data.duplicate()
	_enemy.npc_data.max_health = 100
	_enemy.npc_data.roam_radius = 0
	_enemy.npc_data.drop_table = null
	_enemy.npc_data.perception_enabled = false
	_enemy.position = Vector2(28, 0)
	_stage.add_child(_enemy)
	_swings = 0
	_enemy.state_changed.connect(func(state: StringName) -> void:
		if state == &"attack":
			_swings += 1)
	await physics_frame
	await physics_frame
	var navigation := TownNavigation.new()
	navigation.area = Rect2i(-20, -20, 120, 40)
	navigation.register("player", _player)
	navigation.register("enemy", _enemy)
	navigation.build(_stage.get_world_2d().direct_space_state)

func _cleanup() -> void:
	Input.action_release(&"player_attack")
	Input.action_release(&"player_right")
	Input.action_release(&"player_run")
	_stage.queue_free()
	await process_frame

func _run() -> void:
	var cognition: Node = root.get_node("NpcCognition")
	cognition.save_game.path = OS.get_temp_dir().path_join("arcadia-combat-contact-%d.json" % OS.get_process_id())
	cognition.save_game.from_data(NpcWorldSave.new().to_data())
	await _setup()
	for frame: int in range(Engine.physics_ticks_per_second * 5):
		await physics_frame
	if _player.health == 100:
		_failures.append("Enemy swings never damaged a stationary player")
	print("Stationary combat: player health=", _player.health, " separation=", _enemy.position - _player.position,
		" swings=", _swings, " facing=", _enemy.facing, " hitbox=", _enemy.hit_box_shape.position)
	await _cleanup()
	await _setup()
	var swing_cycle: int = roundi(Engine.physics_ticks_per_second * 0.6)
	var swing_release: int = roundi(Engine.physics_ticks_per_second * 0.1)
	for frame: int in range(Engine.physics_ticks_per_second * 5):
		Input.action_press(&"player_right")
		if frame % swing_cycle == 0:
			Input.action_press(&"player_attack")
		elif frame % swing_cycle == swing_release:
			Input.action_release(&"player_attack")
		await physics_frame
	if _enemy.health > 98:
		_failures.append("Enemy continually backed away from the player's advancing swings")
	print("Advancing combat: enemy health=", _enemy.health, " player health=", _player.health,
		" separation=", _enemy.position - _player.position)
	await _cleanup()
	await _setup()
	_enemy.position = Vector2(-24, 0)
	Input.action_press(&"player_right")
	Input.action_press(&"player_run")
	for frame: int in range(Engine.physics_ticks_per_second * 8):
		await physics_frame
	if _player.health == 100:
		_failures.append("Faster pursuing enemy tracked the player without ever landing a hit")
	print("Running combat: player health=", _player.health, " separation=", _enemy.position - _player.position)
	await _cleanup()
	await _setup()
	_enemy.npc_data.ai_enabled = false
	_enemy.position = Vector2(12, 0)
	_enemy.state_machine.transition_to(&"idle")
	_enemy.set_facing_from_direction(Vector2.LEFT)
	RegionArt.barrier(_stage, Vector2(6, 0), Vector2(1, 32))
	await physics_frame
	_player.state_machine.transition_to(&"attack")
	_enemy.state_machine.transition_to(&"attack")
	for frame: int in range(Engine.physics_ticks_per_second):
		await physics_frame
	if _player.health < 100 or _enemy.health < 100:
		_failures.append("An actual swing dealt damage through a wall")
	await _cleanup()
	print("Combat contact failures: ", _failures)
	DirAccess.remove_absolute(cognition.save_game.path)
	quit(0 if _failures.is_empty() else 1)
