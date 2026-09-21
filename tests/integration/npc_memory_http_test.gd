extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var backend := DialogBackendClient.new()
	root.add_child(backend)
	var endpoint: String = OS.get_environment("ARCADIA_TEST_SERVER_URL")
	backend.chat_endpoint = endpoint + "/chat"
	backend.decision_endpoint = endpoint + "/decide"
	backend.observation_endpoint = endpoint + "/observe"
	backend.reaction_endpoint = endpoint + "/react"
	var profile: NpcProfile = load("res://game/resources/actors/humans/blacksmith_npc_profile.tres")
	var conversation := NpcConversation.new()
	conversation.persist = false
	var result: Dictionary = await conversation.request(profile, {},
		"I will burn down your forge.", backend)
	var state: Dictionary = conversation.store.snapshot(String(profile.npc_id))
	var succeeded: bool = not result.is_empty() and conversation.store.turn == 1 \
		and state.recent_dialogue.size() == 2 and state.relationship.trust < 0.0 \
		and state.memories.size() == profile.core_memories.size() + 1
	var farewell: Dictionary = await conversation.request(profile, {}, "See you tomorrow.", backend)
	state = conversation.store.snapshot(String(profile.npc_id))
	succeeded = succeeded and farewell.get("end_conversation", false) \
		and farewell.get("response") == "Until tomorrow." \
		and state.recent_dialogue.size() == 4 \
		and state.recent_dialogue.back().text == "Until tomorrow."
	var event: Dictionary = {"text": "I saw the player hurt a villager.",
		"sense": "sight", "player_involved": true, "speech_allowed": true}
	var payload: Dictionary = {"protocol_version": 1,
		"npc": {"id": String(profile.npc_id), "profile": profile.to_backend_profile()},
		"player": {"message": ""}, "event": event,
		"context": {"current": {"recent_events": []}, "relationship": state.relationship,
			"recent_dialogue": [], "memories": []}}
	var judgment: Dictionary = await backend.request_observation(payload)
	succeeded = succeeded and NpcMemoryStore.is_valid_policy(judgment.get("policy"))
	if not judgment.is_empty():
		payload.answers = judgment.answers
		var reaction: Dictionary = await backend.request_reaction(payload)
		succeeded = succeeded and reaction.get("response") == "Keep away!"
	if succeeded:
		print("Godot HTTP memory integration passed")
	else:
		push_error("Godot HTTP memory integration failed")
	backend.queue_free()
	quit(0 if succeeded else 1)
