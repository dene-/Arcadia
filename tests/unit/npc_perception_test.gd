extends "res://tests/test_case.gd"

class Observer extends BaseNpc:
	var received: Array[Dictionary] = []
	func _ready() -> void:
		pass
	func _physics_process(_delta: float) -> void:
		pass
	func perceive_combat_event(victim: BaseActor, attacker: BaseActor, fatal: bool) -> void:
		received.append(NpcPerception.observe(self, victim, attacker, fatal))
	func get_perceived_name() -> String:
		return "the player" if is_in_group("players") else super.get_perceived_name()

var _nodes: Array[Node] = []

func _actor(at: Vector2) -> Observer:
	var scene: PackedScene = load("res://game/actors/npcs/base_npc.tscn")
	var npc: BaseNpc = scene.instantiate()
	var data: NpcData = npc.npc_data.duplicate()
	npc.set_script(Observer)
	npc.npc_data = data
	npc.npc_data.profile = NpcProfile.new()
	npc.npc_data.profile.npc_id = &"perception_test"
	npc.position = at
	npc.collision_layer = 0
	npc.collision_mask = 0
	npc.health = 3
	npc.max_health = 3
	var tree: SceneTree = Engine.get_main_loop()
	tree.root.add_child(npc)
	_nodes.append(npc)
	return npc as Observer

func after_each() -> void:
	for node: Node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()

func test_vision_hearing_and_own_injury_have_distinct_evidence() -> void:
	var observer: Observer = _actor(Vector2.ZERO)
	var victim: Observer = _actor(Vector2(30, 0))
	var player: Observer = _actor(Vector2(35, 0))
	player.add_to_group("players")
	victim.npc_data.ai_enabled = true
	victim.npc_data.profile = null
	observer.npc_data.vision_radius = 40
	observer.npc_data.hearing_radius = 80
	var seen: Dictionary = NpcPerception.observe(observer, victim, player, true)
	assert_eq(seen.sense, "sight")
	assert_true(seen.player_involved)
	assert_true(seen.text.contains("the player kill a hostile creature"))
	observer.npc_data.vision_radius = 10
	var heard: Dictionary = NpcPerception.observe(observer, victim, player, true)
	assert_eq(heard.sense, "hearing")
	assert_false(heard.player_involved)
	assert_false(heard.text.contains("player"))
	assert_false(heard.text.contains("kill"))
	observer.npc_data.hearing_radius = 0
	assert_true(NpcPerception.observe(observer, victim, player, true).is_empty())
	var felt: Dictionary = NpcPerception.observe(observer, observer, player, false)
	assert_eq(felt.sense, "touch")
	assert_false(felt.player_involved)
	observer.npc_data.perception_enabled = false
	assert_true(NpcPerception.observe(observer, observer, player, false).is_empty())

func test_wall_blocks_identity_and_distant_npcs_do_not_observe() -> void:
	var observer: Observer = _actor(Vector2.ZERO)
	var victim: Observer = _actor(Vector2(8, 0))
	var player: Observer = _actor(Vector2(32, 0))
	player.add_to_group("players")
	var wall := StaticBody2D.new()
	wall.position = Vector2(16, 0)
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(4, 64)
	collider.shape = shape
	wall.add_child(collider)
	var tree: SceneTree = Engine.get_main_loop()
	tree.root.add_child(wall)
	_nodes.append(wall)
	await tree.physics_frame
	await tree.process_frame
	var event: Dictionary = NpcPerception.observe(observer, victim, player, true)
	assert_eq(event.sense, "sight")
	assert_false(event.player_involved)
	assert_true(event.text.contains("could not see who"))
	victim.position = Vector2(34, 0)
	await tree.physics_frame
	await tree.process_frame
	assert_eq(NpcPerception.observe(observer, victim, player, true).sense, "hearing")
	observer.position = Vector2(1000, 1000)
	assert_true(NpcPerception.observe(observer, victim, player, true).is_empty())

func test_damage_dispatch_attributes_player_and_reports_lethal_hit_only_once() -> void:
	var observer: Observer = _actor(Vector2.ZERO)
	var bus: Node = observer.get_node("/root/WorldEvents")
	var capture: Callable = func(event: WorldEvent) -> void:
		observer.received.append(NpcPerceptionRouter.new().perceive(observer, event))
	bus.occurred.connect(capture)
	var victim: Observer = _actor(Vector2(20, 0))
	var player: Observer = _actor(Vector2(25, 0))
	player.add_to_group("players")
	# Initialize the real actor states; this exercises BaseNpc.take_damage rather than a fake event.
	victim.npc_data.profile = null
	victim.state_machine.initialize(victim)
	player.hit_box.set_meta("owner", player)
	victim.take_damage(3, player.hit_box)
	assert_eq(observer.received.size(), 1)
	assert_true(observer.received[0].text.contains("kill"))
	assert_true(observer.received[0].player_involved)
	victim.take_damage(3, player.hit_box)
	assert_eq(observer.received.size(), 1)
	bus.occurred.disconnect(capture)

func test_reaction_bubble_is_temporary_and_cooldown_blocks_repeated_speech() -> void:
	var npc: Observer = _actor(Vector2.ZERO)
	assert_true(npc.reserve_spoken_reaction())
	assert_false(npc.reserve_spoken_reaction())
	assert_true(npc.show_spoken_reaction("Keep away!"))
	var bubble: Node2D = npc.get_node("ReactionBubble")
	assert_true(bubble.visible)
	assert_eq(bubble.get_node("Panel/Text").text, "Keep away!")
	bubble.get_node("Timer").timeout.emit()
	assert_false(bubble.visible)
	npc.health = 0
	assert_false(npc.show_spoken_reaction("Too late."))
