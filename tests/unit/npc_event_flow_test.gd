extends "res://tests/test_case.gd"

const FakeService = preload("res://tests/fixtures/npc_fake_decision_service.gd")
const Rig = preload("res://tests/fixtures/npc_processor_rig.gd")
const CHAT: String = "dialogue/chat"

func test_actual_damage_reaches_bubble_then_shapes_next_greeting() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var cognition: Node = tree.root.get_node("NpcCognition")
	var original: DialogBackendClient = cognition.decisions.transport
	var backend := FakeService.new()
	tree.root.add_child(backend)
	backend.set_default("appraise", Rig.distrust("player"))
	backend.set_default("dialogue/say", {"response": "Keep away!"})
	cognition.decisions.transport = backend
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
	var sightings: Array[Dictionary] = cognition.save_game.minds.get_mind("flow_test") \
		.knowledge.known_locations("player")
	assert_eq(sightings.size(), 1, "The victim saw the attacker, so it knows where the player was")
	assert_eq(sightings[0].value.x, 5010.0)
	assert_eq(sightings[0].status, "OBSERVED")
	var calls: Array[Dictionary] = backend.calls("appraise")
	assert_eq(calls.size(), 1)
	assert_true(calls[0].evidence[0].text.contains("Den"), "The victim names the attacker it saw")
	assert_eq(calls[0].evidence[0].modality, "touch")
	assert_true("player" in calls[0].subjects)
	assert_ne(calls[0].state.current.activity, "conversation")
	assert_eq(backend.call_count("utterance"), 1)
	assert_eq(backend.calls("utterance")[0].intents,
		["remark", "warn", "call_for_help", "protest", "silence"],
		"A hurt actor is danger evidence, and being touched permits a protest")
	assert_true(npc.get_node("ReactionBubble").visible)
	assert_eq(npc.get_node("ReactionBubble/Panel/Text").text, "Keep away!")
	assert_eq(cognition.store.snapshot("flow_test").observations[0].diagnostics.speech_result, "displayed")
	var conversation := NpcConversation.new()
	conversation.store = cognition.store
	conversation.persist = false
	await conversation.request(npc.get_npc_profile(), npc.get_cognitive_context(), "Hi.",
		cognition.decisions)
	assert_eq(backend.call_count(CHAT), 1)
	var payload: Dictionary = backend.calls(CHAT)[0]
	assert_eq(payload.context.current_concerns.size(), 1)
	assert_true(payload.context.current_concerns[0].text.contains("Den"))
	assert_eq(payload.player.identity, {"id": "player", "name": "Den", "sex": "Male"})
	assert_false(payload.context.past_observations[0].has("decision"))
	assert_true(cognition.save_game.minds.get_mind("flow_test").relationships \
		.get_relationship("player").trust < 0.0)
	assert_true(payload.memories.size() > 0)
	# A lethal hit saves death immediately, independently of providers and animation.
	npc.take_damage(99, player.hit_box)
	await cognition.events.flush("flow_test")
	assert_true(cognition.save_game.is_dead(&"flow_test"))
	var restored := NpcWorldSave.new()
	restored.path = cognition.save_game.path
	restored.legacy_world_path = cognition.save_game.legacy_world_path
	restored.legacy_memory_path = cognition.save_game.legacy_memory_path
	assert_eq(restored.load_file(), OK)
	assert_true(restored.is_dead(&"flow_test"))
	var respawn: BaseNpc = load("res://game/actors/npcs/base_npc.tscn").instantiate()
	respawn.npc_data = npc.npc_data
	tree.root.add_child(respawn)
	assert_true(respawn.is_queued_for_deletion())
	npc.queue_free()
	player.queue_free()
	await tree.process_frame
	cognition.decisions.transport = original
	backend.release_all()
	backend.free()

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
