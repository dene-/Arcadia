class_name NpcCognitiveContext
extends RefCounted

## A bounded view of working memory, separate from saved diagnostics and the archive.
static func build(state: Dictionary, current: Dictionary) -> Dictionary:
	var result: Dictionary = current.duplicate(true)
	result.recent_events = state.recent_events.duplicate()
	result.participants = ["player"]
	result.past_observations = observations(state.observations)
	var concerns: Array[Dictionary] = []
	for observed: Dictionary in result.past_observations:
		if not observed.player_involved:
			continue
		var personal_injury: bool = (observed.sense == "touch"
			and current.get("physical_state") == "injured")
		if observed.age_seconds <= 120.0 or personal_injury:
			concerns.append(observed)
	concerns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_personal: bool = a.sense == "touch"
		var b_personal: bool = b.sense == "touch"
		if a_personal != b_personal:
			return a_personal
		return a.age_seconds < b.age_seconds)
	result.current_concerns = concerns.slice(0, 3)
	return result

static func observations(records: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in records:
		result.append({"text": record.text, "sense": record.sense,
			"player_involved": record.player_involved,
			"age_seconds": maxf(0.0, Time.get_unix_time_from_system() - record.created_at),
			"assessment": record.status})
	return result
