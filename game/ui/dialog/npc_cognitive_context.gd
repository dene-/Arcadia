class_name NpcCognitiveContext
extends RefCounted

## A bounded view of working memory, separate from saved diagnostics and the archive.
const WORKING_MEMORY_MINUTES: float = 180.0
const LEGACY_WORKING_MEMORY_SECONDS: float = 120.0

static func build(state: Dictionary, current: Dictionary) -> Dictionary:
	var result: Dictionary = current.duplicate(true)
	result.erase("routine_decision")
	result.erase("social_status")
	result.recent_events = state.recent_events.duplicate()
	result.participants = ["player"]
	result.past_observations = observations(state.observations, current)
	var concerns: Array[Dictionary] = []
	for observed: Dictionary in result.past_observations:
		if not observed.player_involved:
			continue
		var personal_injury: bool = (observed.sense == "touch"
			and current.get("physical_state") == "injured")
		if observed.recent or personal_injury:
			concerns.append(observed)
	concerns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_personal: bool = a.sense == "touch"
		var b_personal: bool = b.sense == "touch"
		if a_personal != b_personal:
			return a_personal
		return _relative_age(a) < _relative_age(b))
	result.current_concerns = concerns.slice(0, 3)
	return result

static func observations(records: Array, current: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in records:
		var seconds: float = maxf(0.0, Time.get_unix_time_from_system() - record.created_at)
		var recent: bool = seconds <= LEGACY_WORKING_MEMORY_SECONDS
		var elapsed_minutes: float = -1.0
		if record.has("world_minute") and current.has("world_minute"):
			elapsed_minutes = maxf(0.0, float(current.world_minute) - float(record.world_minute))
			recent = elapsed_minutes <= WORKING_MEMORY_MINUTES
		var ongoing_injury: bool = record.sense == "touch" and current.get("physical_state") == "injured"
		if not recent and not ongoing_injury:
			continue
		result.append({"text": record.text, "sense": record.sense,
			"player_involved": record.player_involved,
			"recent": recent, "assessment": record.status})
		if elapsed_minutes >= 0.0:
			result[-1]["age_game_minutes"] = elapsed_minutes
		else:
			result[-1]["age_seconds"] = seconds
	return result

static func _relative_age(observed: Dictionary) -> float:
	if observed.has("age_game_minutes"):
		return float(observed.age_game_minutes) / WORKING_MEMORY_MINUTES
	return float(observed.age_seconds) / LEGACY_WORKING_MEMORY_SECONDS
