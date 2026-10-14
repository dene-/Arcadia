extends RefCounted

## Builds appraisal records for store tests that commit evidence without a decision service.

## `dispositions` maps subject id -> {dimension: signed delta}; `emotion` is the single strongest
## emotion intensity (fear).
static func make(remember: bool = true, importance: float = 0.8, emotion: float = 0.0,
		dispositions: Dictionary = {}) -> NpcDecisionPolicy.Appraisal:
	var appraisal := NpcDecisionPolicy.Appraisal.new()
	appraisal.remember = remember
	appraisal.importance = importance
	appraisal.emotions["fear"] = emotion
	for subject: String in dispositions:
		appraisal.dispositions[subject] = dispositions[subject].duplicate()
	return appraisal

## An appraisal whose only effect is a change of `trust` toward the player.
static func player_trust(trust: float, remember: bool = true,
		importance: float = 0.7, emotion: float = 0.5) -> NpcDecisionPolicy.Appraisal:
	return make(remember, importance, emotion,
		{"player": {"trust": trust}} if trust != 0.0 else {})
