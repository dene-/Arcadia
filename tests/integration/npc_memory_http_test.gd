extends SceneTree

## Real HTTP exchange with the in-process mock server (tools/server/test/memory.test.js): player
## dialogue on /v2/dialogue/chat, v2 appraise and utterance judgments, then /v2/dialogue/say.

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var backend := DialogBackendClient.new()
	root.add_child(backend)
	backend.v2_base_url = OS.get_environment("ARCADIA_TEST_SERVER_URL")
	var decisions := NpcDecisionService.new()
	decisions.transport = backend
	root.add_child(decisions)
	var profile: NpcProfile = load("res://game/resources/actors/humans/blacksmith_npc_profile.tres")
	var npc_id: String = String(profile.npc_id)
	var conversation := NpcConversation.new()
	conversation.persist = false
	conversation.session_id = "player:http-test"
	conversation.session_start = conversation.store.world_minute
	var result: Dictionary = await conversation.request(profile, {},
		"I will burn down your forge.", decisions)
	var state: Dictionary = conversation.store.snapshot(npc_id)
	var relationship: Dictionary = conversation.store.minds.get_mind(npc_id) \
		.relationships.get_relationship("player")
	_check(not result.is_empty(), "the threat got no committed reply")
	_check(conversation.store.turn == 1 and state.recent_dialogue.size() == 2,
		"the threat exchange was not recorded")
	_check(relationship.trust < 0.0, "the threat did not lower trust")
	_check(state.memories.size() == profile.core_memories.size() + 1,
		"the threat was not remembered")
	var farewell: Dictionary = await conversation.request(profile, {}, "See you tomorrow.", decisions)
	state = conversation.store.snapshot(npc_id)
	_check(farewell.get("end_conversation", false) == true, "the farewell did not end the conversation")
	_check(farewell.get("response") == "Until tomorrow.", "unexpected farewell line")
	_check(state.recent_dialogue.size() == 4 and state.recent_dialogue.back().text == "Until tomorrow.",
		"the farewell exchange was not recorded")
	var tuning := NpcBehaviorTuning.new()
	var evidence: Dictionary = {"id": "obs:http-test", "text": "I saw the player hurt a villager.",
		"modality": "sight", "source_id": "player", "participant_ids": ["player"]}
	var appraise_ticket := NpcDecisionTicket.create(npc_id, NpcDecisionTicket.APPRAISE)
	appraise_ticket.evidence_ids.append(evidence.id)
	var appraised: NpcDecisionResult = await decisions.evaluate(appraise_ticket,
		{"state": {"npc": profile.to_backend_profile()}, "evidence": [evidence], "subjects": ["player"]})
	var appraisal: NpcDecisionPolicy.Appraisal = NpcDecisionPolicy.appraisal(appraised, tuning)
	_check(appraised.is_success() and appraisal.remember and not appraisal.immediate_danger \
		and appraisal.importance > 0.0 \
		and appraisal.dispositions.get("player", {}).get("trust", 0.0) < 0.0,
		"unexpected appraisal")
	var utterance_ticket := NpcDecisionTicket.create(npc_id, NpcDecisionTicket.UTTERANCE)
	utterance_ticket.evidence_ids.append(evidence.id)
	var judged: NpcDecisionResult = await decisions.evaluate(utterance_ticket,
		{"state": {"npc": profile.to_backend_profile()}, "evidence": [evidence],
			"intents": ["remark", "protest", "silence"]})
	var utterance: NpcDecisionPolicy.Utterance = NpcDecisionPolicy.utterance(judged,
		["remark", "protest"], tuning)
	_check(utterance.speak and utterance.intent == "protest", "the utterance judgment did not protest")
	if utterance.speak:
		var ticket := NpcDecisionTicket.create(npc_id, NpcDecisionTicket.UTTERANCE)
		var spoken: NpcDecisionResult = await decisions.run_text(ticket, NpcReportSpeech.PATH, {
			"protocol_version": ticket.protocol_version, "prompt_version": ticket.prompt_version,
			"request_id": ticket.request_id, "npc_id": npc_id,
			"npc": {"id": npc_id, "profile": profile.to_backend_profile()},
			"intent": utterance.intent, "context": {},
			"event": {"text": evidence.text, "sense": "sight", "player_involved": true}})
		_check(NpcReportSpeech.spoken_line(spoken) == "Keep away!", "unexpected spoken line")
	if _failures.is_empty():
		print("Godot HTTP memory integration passed")
	else:
		push_error("Godot HTTP memory integration failed: %s" % "; ".join(_failures))
	decisions.queue_free()
	backend.queue_free()
	quit(0 if _failures.is_empty() else 1)

func _check(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)
