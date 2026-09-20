class_name NpcConversation
extends RefCounted

## Coordinates two inference stages; commits only a current, valid, completed exchange.
var store: NpcMemoryStore = NpcMemoryStore.new()
var retriever: NpcMemoryRetriever = NpcMemoryRetriever.new()
var persist: bool = true
var _generation: int = 0

func cancel() -> void:
	_generation += 1

func request(profile: NpcProfile, current: Dictionary, message: String,
		backend: DialogBackendClient, current_guard: Callable = Callable()) -> Dictionary:
	cancel()
	var generation: int = _generation
	if profile == null or profile.npc_id.is_empty() or message.length() > 2000:
		return {}
	store.ensure_npc(profile)
	var id: String = String(profile.npc_id)
	var state: Dictionary = store.snapshot(id)
	var perception: Dictionary = current.duplicate(true)
	perception["recent_events"] = state.recent_events.duplicate()
	var payload: Dictionary = {
		"protocol_version": 1, "npc": {"id": id, "profile": profile.to_backend_profile()},
		"player": {"message": message},
		"context": {"current": perception, "relationship": state.relationship,
			"recent_dialogue": state.recent_dialogue, "memories": []},
	}
	var judgment: Dictionary = await backend.request_decision(payload)
	if not _is_current(generation, current_guard) or not NpcMemoryStore.is_valid_policy(judgment.get("policy")):
		return {}
	var policy: Dictionary = judgment.policy
	var recalled: Array[Dictionary] = []
	if policy.retrieve:
		recalled = retriever.retrieve(state.memories, message, perception,
			profile.get_cognition(), store.turn)
	payload.context.memories = recalled
	payload.context.relationship = NpcRelationshipState.changed(
		state.relationship, policy.relationship_delta)
	payload["answers"] = judgment.get("answers", {})
	var result: Dictionary = await backend.request_dialog(payload)
	if not _is_current(generation, current_guard):
		return {}
	if not store.commit_exchange(id, message, result, policy, recalled, state.recent_events):
		return {}
	if persist:
		var error: Error = store.save_file()
		if error != OK:
			push_warning("NPC memory could not be saved: %s" % error)
	return result

func _is_current(generation: int, current_guard: Callable) -> bool:
	return generation == _generation and (not current_guard.is_valid() or current_guard.call())
