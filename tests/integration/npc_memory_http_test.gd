extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var backend := DialogBackendClient.new()
	root.add_child(backend)
	var endpoint: String = OS.get_environment("ARCADIA_TEST_SERVER_URL")
	backend.chat_endpoint = endpoint + "/chat"
	backend.decision_endpoint = endpoint + "/decide"
	var profile: NpcProfile = load("res://game/resources/actors/humans/blacksmith_npc_profile.tres")
	var conversation := NpcConversation.new()
	conversation.persist = false
	var result: Dictionary = await conversation.request(profile, {},
		"I will burn down your forge.", backend)
	var state: Dictionary = conversation.store.snapshot(String(profile.npc_id))
	var succeeded: bool = not result.is_empty() and conversation.store.turn == 1 \
		and state.recent_dialogue.size() == 2 and state.relationship.trust < 0.0 \
		and state.memories.size() == profile.core_memories.size() + 1
	if succeeded:
		print("Godot HTTP memory integration passed")
	else:
		push_error("Godot HTTP memory integration failed")
	backend.queue_free()
	quit(0 if succeeded else 1)
