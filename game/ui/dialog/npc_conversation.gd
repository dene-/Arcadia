class_name NpcConversation
extends RefCounted

## Sends one player-dialogue request per message; commits only a current, valid, completed exchange.
## The provider judges the message and words the reply; only Godot applies the effects.
const OPENING_GREETINGS: Array[String] = ["Hi.", "Hey.", "Hello.", "Hi there.", "Hey there."]

var store: NpcMemoryStore = NpcMemoryStore.new()
var retriever: NpcMemoryRetriever = NpcMemoryRetriever.new()
var tuning := NpcBehaviorTuning.new()
var persist: bool = true
var save_callback: Callable
## The player session exchanges belong to, and the store minute it started at.
var session_id: String = ""
var session_start: float = -1.0
var _generation: int = 0
var _decisions: NpcDecisionService
var _pending_request: String = ""

## Abandons the request in flight; its answer is never applied.
func cancel() -> void:
	_generation += 1
	if not _pending_request.is_empty() and is_instance_valid(_decisions):
		_decisions.cancel(_pending_request)
	_pending_request = ""

func request(profile: NpcProfile, current: Dictionary, message: String,
		decisions: NpcDecisionService, current_guard: Callable = Callable()) -> Dictionary:
	cancel()
	var generation: int = _generation
	if profile == null or profile.npc_id.is_empty() or message.length() > 2000 or decisions == null:
		return {}
	# An empty message is the interaction action opening a conversation.
	if message.is_empty():
		var greeting := NpcRoutinePlan.random_for(0, "%s:greeting:%d:%s" % [profile.npc_id,
			int(store.world_minute), session_id])
		message = OPENING_GREETINGS[greeting.randi_range(0, OPENING_GREETINGS.size() - 1)]
	store.ensure_npc(profile)
	var id: String = String(profile.npc_id)
	var state: Dictionary = store.snapshot(id)
	var revision: int = store.revision(id)
	var perception: Dictionary = NpcCognitiveContext.build(state, current)
	# Judgments and speech get the same imperfect recollections, never the archive.
	var candidates: Array[Dictionary] = retriever.retrieve(state.memories, message,
		perception, profile.get_cognition(), store.world_minute, NpcMemoryRetriever.links_for(current))
	var turns: Array[Dictionary] = []
	for entry: Dictionary in state.recent_dialogue:
		turns.append({"speaker": entry.speaker, "text": entry.text})
	var payload: Dictionary = {
		"npc": {"id": id, "profile": profile.to_backend_profile()},
		"context": perception,
		"player": {"message": message, "identity": current.get("player_identity",
			preload("res://game/resources/actors/player_data.tres").social_identity())},
		"recent_dialogue": turns, "memories": candidates,
	}
	var ticket := NpcDecisionTicket.create(id, NpcDecisionTicket.DIALOGUE,
		NpcDecisionTicket.Urgency.INTERACTIVE)
	ticket.created_minute = int(store.world_minute)
	_decisions = decisions
	_pending_request = ticket.request_id
	var answered: NpcDecisionResult = await decisions.chat(ticket, payload)
	if generation != _generation:
		return {}
	_pending_request = ""
	if not _is_current(generation, current_guard) or not answered.is_success():
		return {}
	if store.revision(id) != revision:
		return {"interrupted": true}
	var speech: NpcDecisionPolicy.PlayerSpeech = NpcDecisionPolicy.player_speech(answered, tuning)
	var result: Dictionary = answered.body.duplicate(true)
	result.erase("judgments")
	var recalled: Array[Dictionary] = []
	if speech.retrieve:
		recalled = candidates
	if not store.commit_exchange(id, message, result, speech, recalled, state.recent_events,
			session_id):
		return {}
	if persist:
		if not save_callback.is_valid():
			push_error("NPC conversation cannot persist without a save callback.")
		else:
			var error: Error = save_callback.call()
			if error != OK:
				push_warning("NPC memory could not be saved: %s" % error)
	# Only Godot's reading of the message can end a completed exchange, never generated metadata.
	result["end_conversation"] = speech.end_conversation
	result["surrender"] = speech.surrender
	return result

func _is_current(generation: int, current_guard: Callable) -> bool:
	return generation == _generation and (not current_guard.is_valid() or current_guard.call())
