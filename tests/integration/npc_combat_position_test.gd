extends SceneTree

var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _run() -> void:
	var target := Node2D.new()
	root.add_child(target)
	target.add_to_group(&"combat_position_test_targets")
	# Exercise the real run state and physics with close, distant and misaligned starts.
	for scenario: Dictionary in [
		{"start": Vector2(-9, 0), "spacing": 12.0, "vertical": 4.0},
		{"start": Vector2(9, 0), "spacing": 12.0, "vertical": 4.0},
		{"start": Vector2(-14, 0), "spacing": 12.0, "vertical": 4.0},
		{"start": Vector2(12, -2), "spacing": 12.0, "vertical": 0.5},
		{"start": Vector2(-30, 0), "spacing": 20.0, "vertical": 4.0},
	]:
		var enemy: BaseNpc = load("res://game/actors/enemies/scenes/goblin.tscn").instantiate()
		enemy.npc_data = enemy.npc_data.duplicate()
		enemy.npc_data.target_group = &"combat_position_test_targets"
		enemy.npc_data.require_line_of_sight = false
		enemy.npc_data.attack_side_offset = 8.0
		enemy.npc_data.attack_range = 13.0
		enemy.npc_data.soft_collision_distance = scenario.spacing
		enemy.npc_data.attack_vertical_tolerance = scenario.vertical
		enemy.npc_data.attack_slot_arrival_distance = 3.0
		# A full step would cross the entire attack band; the final step must be limited.
		enemy.npc_data.move_speed = 180.0
		enemy.position = scenario.start
		root.add_child(enemy)
		var attacked: bool = false
		for frame: int in range(120):
			await physics_frame
			if enemy.state_machine.is_in_state(&"attack"):
				attacked = true
				break
		_check(attacked, "Enemy never attacked from %s with spacing %s" % [
			scenario.start, scenario.spacing])
		_check(enemy.is_in_lateral_attack_position(target.global_position), "Attack outside valid spacing")
		_check(enemy.velocity == Vector2.ZERO, "Enemy kept moving while attacking")
		enemy.queue_free()
		await process_frame
	target.free()
	print("NPC combat positioning failures: ", _failures)
	quit(0 if _failures.is_empty() else 1)
