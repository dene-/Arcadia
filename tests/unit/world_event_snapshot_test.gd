extends "res://tests/test_case.gd"

var _scene: Node2D

func before_each() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	_scene = Node2D.new()
	tree.root.add_child(_scene)

func after_each() -> void:
	_scene.free()

func _resident(id: String, point: Vector2, space: StringName) -> BaseNpc:
	var npc: BaseNpc = load("res://game/actors/npcs/base_npc.tscn").instantiate()
	npc.npc_data = npc.npc_data.duplicate(true)
	npc.npc_data.profile = npc.npc_data.profile.duplicate(true)
	npc.npc_data.profile.npc_id = StringName(id)
	npc.position = point
	_scene.add_child(npc)
	npc.world_space = space
	return npc

func test_snapshot_survives_freeing_the_actors_and_mutating_the_source_facts() -> void:
	var victim: BaseNpc = _resident("snap_victim", Vector2(5000, 5000), &"home:snap_victim")
	var attacker: BaseNpc = _resident("snap_attacker", Vector2(5020, 5000), &"home:snap_victim")
	var event := WorldEvent.damage(victim, attacker)
	event.facts["witnesses"] = ["a", "b"]
	event.facts["node"] = victim
	event.facts["bad_number"] = INF
	event.facts["nested"] = {"list": [1, {"deep": "x"}]}
	var snapshot: WorldEventSnapshot = WorldEventSnapshot.capture(event, "event:7", 42.5)
	victim.free()
	attacker.free()
	event.facts["witnesses"].append("c")
	event.facts["nested"]["list"][1]["deep"] = "changed"
	event.facts["health_remaining"] = -1
	assert_eq(snapshot.event_id, "event:7")
	assert_eq(snapshot.kind, &"actor_hurt")
	assert_eq(snapshot.minute, 42.5)
	assert_eq(snapshot.subject_id, "snap_victim")
	assert_eq(snapshot.instigator_id, "snap_attacker")
	assert_eq(snapshot.space_id, &"home:snap_victim")
	assert_true(snapshot.has_position)
	assert_eq(snapshot.position, Vector2(5000, 5000))
	assert_eq(snapshot.facts["witnesses"], ["a", "b"])
	assert_eq(snapshot.facts["nested"]["list"][1]["deep"], "x")
	assert_ne(snapshot.facts["health_remaining"], -1)
	assert_false(snapshot.facts.has("node"), "scene nodes never cross the boundary")
	assert_false(snapshot.facts.has("bad_number"))
	var data: Dictionary = snapshot.to_data()
	assert_eq(data["position"], {"x": 5000.0, "y": 5000.0})
	var round_trip: Variant = JSON.parse_string(JSON.stringify(data))
	assert_eq(round_trip["subject_id"], "snap_victim")
	assert_eq(round_trip["kind"], "actor_hurt")

func test_event_without_actors_has_no_ids_or_position() -> void:
	var event := WorldEvent.new()
	event.kind = &"combat_noise"
	var snapshot: WorldEventSnapshot = WorldEventSnapshot.capture(event, "event:1", 1.0)
	assert_eq(snapshot.subject_id, "")
	assert_eq(snapshot.instigator_id, "")
	assert_false(snapshot.has_position)
	assert_eq(snapshot.space_id, &"")

func test_actor_id_identifies_the_player_residents_and_nothing_else() -> void:
	var player := Node2D.new()
	player.add_to_group(&"players")
	_scene.add_child(player)
	assert_eq(WorldEventSnapshot.actor_id(player), "player")
	var resident: BaseNpc = _resident("snap_resident", Vector2(5000, 5000), &"outdoors")
	assert_eq(WorldEventSnapshot.actor_id(resident), "snap_resident")
	resident.npc_data.profile.npc_id = &""
	assert_eq(WorldEventSnapshot.actor_id(resident), "")
	var stranger := Node2D.new()
	assert_eq(WorldEventSnapshot.actor_id(stranger), "")
	stranger.free()
	assert_eq(WorldEventSnapshot.actor_id(null), "")
	var doomed := Node2D.new()
	doomed.free()
	assert_eq(WorldEventSnapshot.actor_id(doomed), "")
