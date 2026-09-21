extends SceneTree

class MockBackend extends DialogBackendClient:
	func request_life(_kind: String, _payload: Dictionary) -> Dictionary:
		return {}
	func request_observation(_payload: Dictionary) -> Dictionary:
		return {}
	func request_reaction(_payload: Dictionary) -> Dictionary:
		return {}

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var cognition: Node = root.get_node("NpcCognition")
	cognition.save_game.path = OS.get_temp_dir().path_join("arcadia-watch-%d.json" % OS.get_process_id())
	cognition.save_game.from_data(NpcWorldSave.new().to_data())
	cognition.save_game.region_seed = 274415
	var backend := MockBackend.new()
	root.add_child(backend)
	cognition.backend = backend
	cognition.events.backend = backend
	var world: Node2D = load("res://game/world/scenes/world.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame: int in range(8):
		await physics_frame
	var life: TownLife = world.get_node("Region/TownLife")
	life.set_process(false)
	life.encounters.set_process(false)
	_check(get_nodes_in_group("town_residents").size() == 33, "Missing residents")
	_check(life.buildings.rooms.size() == 12, "Missing households")
	var guard: BaseNpc = life._actors.voss_guard
	var other: BaseNpc = life._actors.vale_guard
	var victim: BaseNpc = life._actors.garrin_holt
	var player: BasePlayer = world.get_node("BasePlayer")
	for npc: BaseNpc in get_nodes_in_group("town_residents") + get_nodes_in_group("enemies"):
		npc.set_physics_process(false)
	player.set_physics_process(false)
	guard.global_position = Vector2(-24, 88)
	player.global_position = Vector2(0, 88)
	victim.global_position = Vector2(10, 88)
	other.global_position = Vector2(320, 280)
	for actor: BaseActor in [guard, player, victim, other]:
		actor.world_space = &"outdoors"
	await physics_frame
	await physics_frame
	player.set_hitbox_enabled(true)
	player.set_hitbox_enabled(false)
	_check(cognition.save_game.justice.current("voss_guard", "player", 480).get("status") == "warning", "Missing brandishing warning")
	_check(not guard.has_enemy_target(), "Minor trouble triggered combat")
	_check(guard.get_node("ReactionBubble").visible, "Warning bubble is invisible")
	player.surrender()
	_check(cognition.save_game.justice.current("voss_guard", "player", 480).is_empty(), "Pre-combat surrender ignored")
	victim.take_damage(1, player.hit_box)
	_check(not guard.has_enemy_target(), "First injury skipped warning")
	victim.take_damage(1, player.hit_box)
	_check(guard.has_enemy_target(), "Repeated violence did not trigger enforcement")
	_check(not other.has_enemy_target(), "Unwitnessed assault caused remote aggression")
	_check(not guard.consume_melee_hit(victim), "Guard could hit an uninvolved resident")
	guard.set_physics_process(true)
	var health_before: int = player.health
	for frame: int in range(240):
		await physics_frame
	_check(player.health < health_before, "Guard pursuit never landed a real melee hit")
	guard.request_attack()
	player.surrender()
	await physics_frame
	await physics_frame
	var surrendered_health: int = player.health
	_check(not guard.has_enemy_target(), "Surrender retained target")
	_check(guard.get_node("HitBox/CollisionShape2D").disabled, "Surrender retained active swing")
	for frame: int in range(180):
		await physics_frame
	_check(player.health == surrendered_health, "Guard attacked after surrender")
	# A wall blocks attribution. Noise permits investigation only.
	guard.set_physics_process(false)
	guard.global_position = Vector2(-40, 128)
	player.global_position = Vector2(8, 128)
	victim.global_position = Vector2(16, 128)
	var wall: StaticBody2D = RegionArt.barrier(world, Vector2(-16, 124), Vector2(8, 48))
	await physics_frame
	await physics_frame
	victim.set_health(victim.max_health)
	victim.take_damage(1, player.hit_box)
	_check(cognition.save_game.justice.current("voss_guard", "player", 480).is_empty(), "Hearing through a wall identified attacker")
	_check(life.watch._investigations.has("voss_guard"), "Guard ignored nearby fighting sounds")
	wall.queue_free()
	await physics_frame
	await physics_frame
	# Helping against a monster does not count as violence against townspeople.
	var enemy: BaseNpc = get_nodes_in_group("enemies")[0]
	enemy.global_position = Vector2(16, 128)
	enemy.world_space = &"outdoors"
	player.set_hitbox_enabled(true)
	player.set_hitbox_enabled(false)
	enemy.take_damage(1, player.hit_box)
	_check(cognition.save_game.justice.current("voss_guard", "player", 480).is_empty(), "Monster defense was criminalized")
	var restored := NpcWorldSave.new()
	_check(restored.from_data(cognition.save_game.to_data()), "Expanded state could not reload")
	_check(restored.justice.known_to("voss_guard")[0].status == "surrendered", "Surrender was not saved")
	print("Town watch failures: ", failures)
	world.queue_free()
	await process_frame
	DirAccess.remove_absolute(cognition.save_game.path)
	quit(0 if failures.is_empty() else 1)
