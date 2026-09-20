extends "res://tests/test_case.gd"

const ObservationTests = preload("res://tests/unit/npc_observation_test.gd")
const ConversationTests = preload("res://tests/unit/npc_conversation_test.gd")

func test_actual_damage_reaches_bubble_then_shapes_next_greeting() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var cognition: Node = tree.root.get_node("NpcCognition")
	var original: DialogBackendClient = cognition.events.backend
	var backend := ObservationTests.FakeBackend.new()
	backend.policy = ObservationTests.new()._policy()
	backend.policy.speak = true
	cognition.events.backend = backend
	var npc: BaseNpc = load("res://game/actors/npcs/base_npc.tscn").instantiate()
	npc.npc_data = npc.npc_data.duplicate()
	npc.npc_data.max_health = 5
	npc.npc_data.profile = NpcProfile.new()
	npc.npc_data.profile.npc_id = &"flow_test"
	npc.position = Vector2(5000, 5000)
	tree.root.add_child(npc)
	var player: BaseActor = load("res://game/actors/player/base_player.tscn").instantiate()
	player.position = Vector2(5010, 5000)
	tree.root.add_child(player)
	npc.take_damage(1, player.hit_box)
	await cognition.events.flush("flow_test")
	assert_eq(backend.payloads.size(), 1)
	assert_true(backend.payloads[0].event.directly_affected)
	assert_ne(backend.payloads[0].context.current.activity, "conversation")
	assert_true(npc.get_node("ReactionBubble").visible)
	assert_eq(npc.get_node("ReactionBubble/Panel/Text").text, "Keep away!")
	assert_eq(cognition.store.snapshot("flow_test").observations[0].diagnostics.speech_result, "displayed")
	var dialogue := ConversationTests.FakeBackend.new()
	var conversation := NpcConversation.new()
	conversation.store = cognition.store
	conversation.persist = false
	await conversation.request(npc.get_npc_profile(), npc.get_cognitive_context(), "Hi.", dialogue)
	assert_eq(dialogue.payload.context.current.current_concerns.size(), 1)
	assert_true(dialogue.payload.context.current.current_concerns[0].text.contains("the player"))
	assert_false(dialogue.payload.context.current.past_observations[0].has("decision"))
	assert_true(dialogue.payload.context.relationship.trust < 0.0)
	assert_true(dialogue.payload.context.memories.size() > 0)
	# A lethal hit saves death immediately, independently of providers and animation.
	npc.take_damage(99, player.hit_box)
	await cognition.events.flush("flow_test")
	assert_true(cognition.save_game.is_dead(&"flow_test"))
	var restored := NpcWorldSave.new()
	restored.path = cognition.save_game.path
	assert_eq(restored.load_file(), OK)
	assert_true(restored.is_dead(&"flow_test"))
	var respawn: BaseNpc = load("res://game/actors/npcs/base_npc.tscn").instantiate()
	respawn.npc_data = npc.npc_data
	tree.root.add_child(respawn)
	assert_true(respawn.is_queued_for_deletion())
	npc.queue_free()
	player.queue_free()
	await tree.process_frame
	cognition.events.backend = original
	backend.free()
	dialogue.free()

func test_new_event_adapter_needs_no_dialogue_or_queue_changes() -> void:
	var router := NpcPerceptionRouter.new()
	router.register(&"bell_rang", func(_observer: BaseNpc, _event: WorldEvent) -> Dictionary:
		return {"text": "I heard the town bell.", "sense": "hearing", "player_involved": false,
			"topics": ["bell"]})
	var event := WorldEvent.new()
	event.kind = &"bell_rang"
	var npc := BaseNpc.new()
	assert_eq(router.perceive(npc, event).topics, ["bell"])
	event.kind = &"unknown"
	assert_true(router.perceive(npc, event).is_empty())
	npc.free()
