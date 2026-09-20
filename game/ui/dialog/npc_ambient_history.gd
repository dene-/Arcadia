class_name NpcAmbientHistory
extends RefCounted

## Brief audible context, not factual memory. A spoken claim never becomes an observation.
var _heard: Dictionary = {}

func record(speaker: BaseNpc, text: String, observers: Array[Node]) -> void:
	for observer: BaseNpc in observers:
		if observer.health <= 0 or observer.is_sleeping() or observer.world_space != speaker.world_space \
			or observer.global_position.distance_to(speaker.global_position) > observer.npc_data.hearing_radius:
			continue
		var id: String = String(observer.get_npc_profile().npc_id)
		var entries: Array[Dictionary] = recent(id)
		entries.append({"speaker": speaker.get_npc_profile().profile_name \
			if NpcPerception.can_see(observer, speaker) else "someone nearby",
			"text": text, "heard_at": Time.get_ticks_msec()})
		_heard[id] = entries.slice(-6)

func recent(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _heard.get(id, []):
		if Time.get_ticks_msec() - entry.heard_at < 45000:
			result.append(entry.duplicate(true))
	return result
