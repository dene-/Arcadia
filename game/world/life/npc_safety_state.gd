class_name NpcSafetyState
extends RefCounted

## A short-lived, subjective concern. It neither changes trust nor asserts world truth.
const RESPONSES: Array[String] = ["NONE", "CAUTION", "SHELTER"]
const SHELTER_MINUTES: float = 45.0
const CAUTION_MINUTES: float = 15.0

static func active(concern: Dictionary, minute: float) -> bool:
	return not concern.is_empty() and float(concern.until) > minute

static func sheltering(concern: Dictionary, minute: float) -> bool:
	return active(concern, minute) and concern.response == "SHELTER"

static func notice(previous: Dictionary, event: Dictionary, space: String, minute: float) -> Dictionary:
	if not event.get("danger_possible", false) or String(event.get("origin_id", "")).is_empty():
		return previous
	var personal: bool = event.get("directly_affected", false) and event.sense == "touch"
	# A distant noise must not replace an immediate personal threat or restart its timer.
	if sheltering(previous, minute) and not personal:
		return previous
	return {"origin_id": event.origin_id, "text": event.text, "sense": event.sense,
		"space": space, "observed_at": minute,
		"response": "SHELTER" if personal else "CAUTION",
		"until": minute + (SHELTER_MINUTES if personal else CAUTION_MINUTES)}

static func assess(concern: Dictionary, event: Dictionary, policy: Dictionary, minute: float) -> Dictionary:
	# A late decision cannot overrule a more recent threat or resurrect an expired one.
	if not active(concern, minute) or concern.origin_id != event.get("origin_id"):
		return concern
	var response: String = policy.get("safety_response", "")
	if not response in RESPONSES:
		return concern # Keep the provisional response when classification is unavailable.
	if response == "NONE":
		return {}
	var result: Dictionary = concern.duplicate(true)
	result.response = response
	result.until = result.observed_at + (SHELTER_MINUTES if response == "SHELTER" else CAUTION_MINUTES)
	return result

static func context(concern: Dictionary, minute: float) -> Dictionary:
	if not active(concern, minute):
		return {}
	return {"response": concern.response, "concern": concern.text, "sense": concern.sense,
		"age_game_minutes": maxf(0.0, minute - float(concern.observed_at)),
		"remaining_game_minutes": maxf(0.0, float(concern.until) - minute)}

static func is_valid(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true
	for key: String in ["origin_id", "text", "space"]:
		if not value.get(key) is String or value[key].is_empty() or value[key].length() > 500:
			return false
	if not value.get("response") in RESPONSES or not value.get("sense") in ["touch", "sight", "hearing"]:
		return false
	for key: String in ["observed_at", "until"]:
		if not (value.get(key) is float or value.get(key) is int) \
			or not is_finite(float(value[key])) or value[key] < 0:
			return false
	return value.until >= value.observed_at and value.until - value.observed_at <= SHELTER_MINUTES
