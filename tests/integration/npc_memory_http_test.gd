extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var backend := DialogBackendClient.new()
	root.add_child(backend)
	var endpoint: String = OS.get_environment("ARCADIA_TEST_SERVER_URL")
	backend.chat_endpoint = endpoint + "/chat"
	backend.decision_endpoint = endpoint + "/decide"
	backend.v2_base_url = endpoint
	var decisions := NpcDecisionService.new()
	decisions.transport = backend
	root.add_child(decisions)
	var profile: NpcProfile = load("res://game/resources/actors/humans/blacksmith_npc_profile.tres")
	var conversation := NpcConversation.new()
	conversation.persist = false
	conversation.session_id = "player:http-test"
	conversation.session_start = conversation.store.world_minute
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
	var tuning := NpcBehaviorTuning.new()
	var npc_id: String = String(profile.npc_id)
	var evidence: Dictionary = {"id": "obs:http-test", "text": "I saw the player hurt a villager.",
		"modality": "sight", "source_id": "player", "participant_ids": ["player"]}
	var appraise_ticket := NpcDecisionTicket.create(npc_id, NpcDecisionTicket.APPRAISE)
	appraise_ticket.evidence_ids.append(evidence.id)
	var appraised: NpcDecisionResult = await decisions.evaluate(appraise_ticket,
		{"state": {"npc": profile.to_backend_profile()}, "evidence": [evidence], "subjects": ["player"]})
	var appraisal: NpcDecisionPolicy.Appraisal = NpcDecisionPolicy.appraisal(appraised, tuning)
	succeeded = succeeded and appraised.is_success() and appraisal.remember \
		and not appraisal.immediate_danger and appraisal.importance > 0.0 \
		and appraisal.dispositions.get("player", {}).get("trust", 0.0) < 0.0
	var permitted: Array[String] = ["remark", "protest"]
	var utterance_ticket := NpcDecisionTicket.create(npc_id, NpcDecisionTicket.UTTERANCE)
	utterance_ticket.evidence_ids.append(evidence.id)
	var judged: NpcDecisionResult = await decisions.evaluate(utterance_ticket,
		{"state": {"npc": profile.to_backend_profile()}, "evidence": [evidence],
			"intents": ["remark", "protest", "silence"]})
	var utterance: NpcDecisionPolicy.Utterance = NpcDecisionPolicy.utterance(judged, permitted, tuning)
	succeeded = succeeded and utterance.speak and utterance.intent == "protest"
	if utterance.speak:
		var payload: Dictionary = {"protocol_version": 1,
			"npc": {"id": npc_id, "profile": profile.to_backend_profile()},
			"player": {"message": ""},
			"event": {"text": evidence.text, "sense": "sight", "player_involved": true},
			"intent": utterance.intent,
			"context": {"current": {"recent_events": []}, "relationship": state.relationship,
				"recent_dialogue": [], "memories": []}}
		var spoken: NpcDecisionResult = await decisions.run_text(
			NpcDecisionTicket.create(npc_id, NpcDecisionTicket.UTTERANCE), "/react", payload)
		succeeded = succeeded and spoken.is_success() and spoken.body.get("response") == "Keep away!"
	if succeeded:
		print("Godot HTTP memory integration passed")
	else:
		push_error("Godot HTTP memory integration failed")
	decisions.queue_free()
	backend.queue_free()
	quit(0 if succeeded else 1)
