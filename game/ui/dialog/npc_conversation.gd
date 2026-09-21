class_name NpcConversation
extends RefCounted

## Coordinates two inference stages; commits only a current, valid, completed exchange.
const OPENING_GREETINGS: Array[String] = ["Hi.", "Hey.", "Hello.", "Hi there.", "Hey there."]

var store: NpcMemoryStore = NpcMemoryStore.new()
var retriever: NpcMemoryRetriever = NpcMemoryRetriever.new()
var persist: bool = true
var save_callback: Callable
var _generation: int = 0

func cancel() -> void:
	_generation += 1

func request(profile: NpcProfile, current: Dictionary, message: String,
		backend: DialogBackendClient, current_guard: Callable = Callable()) -> Dictionary:
	cancel()
	var generation: int = _generation
	if profile == null or profile.npc_id.is_empty() or message.length() > 2000:
		return {}
	# An empty message is the interaction action opening a conversation.
	if message.is_empty():
		message = OPENING_GREETINGS.pick_random()
	store.ensure_npc(profile)
	var id: String = String(profile.npc_id)
	var state: Dictionary = store.snapshot(id)
	var revision: int = store.revision(id)
	var perception: Dictionary = NpcCognitiveContext.build(state, current)
	# Decisions need the same imperfect evidence as speech, not an omniscient archive.
	var candidates: Array[Dictionary] = retriever.retrieve(state.memories, message,
		perception, profile.get_cognition(), store.world_minute)
	var payload: Dictionary = {
		"protocol_version": 1, "npc": {"id": id, "profile": profile.to_backend_profile()},
		"player": {"message": message, "identity": current.get("player_identity",
			preload("res://game/resources/actors/player_data.tres").social_identity())},
		"context": {"current": perception, "relationship": state.relationship,
			"recent_dialogue": state.recent_dialogue, "memories": candidates},
	}
	var judgment: Dictionary = await backend.request_decision(payload)
	if not _is_current(generation, current_guard) or not NpcMemoryStore.is_valid_policy(judgment.get("policy")):
		return {}
	if store.revision(id) != revision:
		return {"interrupted": true}
	var policy: Dictionary = judgment.policy
	var recalled: Array[Dictionary] = []
	if policy.retrieve:
		recalled = candidates
	payload.context.memories = recalled
	payload.context.relationship = NpcRelationshipState.changed(
		state.relationship, policy.relationship_delta)
	payload["answers"] = judgment.get("answers", {})
	var result: Dictionary = await backend.request_dialog(payload)
	if not _is_current(generation, current_guard):
		return {}
	if store.revision(id) != revision:
		return {"interrupted": true}
	if not store.commit_exchange(id, message, result, policy, recalled, state.recent_events):
		return {}
	if persist:
		var error: Error = save_callback.call() if save_callback.is_valid() else store.save_file()
		if error != OK:
			push_warning("NPC memory could not be saved: %s" % error)
	# Only the assessed policy can end a completed exchange, never generated dialogue metadata.
	result["end_conversation"] = policy.get("end_conversation", false)
	return result

func _is_current(generation: int, current_guard: Callable) -> bool:
	return generation == _generation and (not current_guard.is_valid() or current_guard.call())
