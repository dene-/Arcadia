class_name NpcAlertResponse
extends RefCounted

## Short physical reaction beats run in real seconds, independent of model/network latency.
var phase: String = ""
var remaining: float = 0.0
var _orient_seconds: float = 0.0

func notice(npc: BaseNpc, event: Dictionary) -> void:
	if not event.get("danger_possible", false) or npc.health <= 0:
		return
	var personal: bool = event.get("directly_affected", false)
	# Repeated noise cannot keep restarting a wake-up or indefinitely freeze a witness.
	if active() and not personal:
		return
	var id: String = String(npc.get_npc_profile().npc_id)
	var random := NpcRoutinePlan.random_for(0, id + String(event.get("origin_id", "")))
	var courage: float = float(npc.get_npc_profile().social_traits.get("courage", 0.5))
	_orient_seconds = random.randf_range(0.8, 1.2) + (1.0 - courage) * 0.5
	if npc.is_sleeping() and not personal:
		phase = "stirring"
		remaining = random.randf_range(1.2, 3.4)
	else:
		phase = "startled" if personal else "assessing"
		remaining = random.randf_range(0.35, 0.65) if personal else random.randf_range(0.5, 1.2)

func advance(npc: BaseNpc, delta: float) -> void:
	if not active():
		return
	if npc.health <= 0:
		phase = ""
		return
	remaining -= delta
	if remaining > 0:
		return
	if phase == "stirring":
		npc.wake_from_noise("disturbance")
		phase = "getting_bearings"
		remaining = _orient_seconds
	else:
		phase = ""

func active() -> bool:
	return not phase.is_empty()
