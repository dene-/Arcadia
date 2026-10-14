class_name NpcAmbientHistory
extends RefCounted

## Brief audible context, not factual memory. A spoken claim never becomes an observation.
## Lines stay audible for this many game minutes (45 real seconds at the default clock rate).
const AUDIBLE_MINUTES: float = 60.0
const MAX_LINES: int = 6

var _heard: Dictionary = {}

## Stamps each line with the speaker's world minute; residents outside town life hear at 0.
func record(speaker: BaseNpc, text: String, observers: Array[Node]) -> void:
	var minute: float = float(speaker.life_context.get("world_minute", 0.0))
	for observer: BaseNpc in observers:
		if observer.health <= 0 or observer.is_sleeping() or observer.world_space != speaker.world_space \
			or observer.global_position.distance_to(speaker.global_position) > observer.npc_data.hearing_radius:
			continue
		var id: String = String(observer.get_npc_profile().npc_id)
		var entries: Array = (_heard.get(id, []) as Array).filter(func(entry: Dictionary) -> bool:
			return _audible(entry, minute))
		entries.append({"speaker": speaker.get_npc_profile().profile_name \
			if NpcPerception.can_see(observer, speaker) else "someone nearby",
			"text": text, "heard_minute": minute})
		_heard[id] = entries.slice(-MAX_LINES)

## Lines heard within AUDIBLE_MINUTES before `minute`, each with its `age_game_minutes`.
func recent(id: String, minute: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _heard.get(id, []):
		if _audible(entry, minute):
			var view: Dictionary = entry.duplicate(true)
			view.age_game_minutes = minute - float(entry.heard_minute)
			result.append(view)
	return result

static func _audible(entry: Dictionary, minute: float) -> bool:
	var age: float = minute - float(entry.heard_minute)
	return age >= 0.0 and age < AUDIBLE_MINUTES
