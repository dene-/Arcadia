class_name NpcPerception
extends RefCounted

## Converts a real combat event into only what this observer could perceive.
static func observe(observer: BaseNpc, victim: BaseActor, attacker: BaseActor,
		fatal: bool) -> Dictionary:
	if observer.health <= 0 or not observer.npc_data.perception_enabled \
		or observer.world_space != victim.world_space:
		return {}
	var sees_victim: bool = can_see(observer, victim)
	var sees_attacker: bool = is_instance_valid(attacker) and can_see(observer, attacker)
	var event: Dictionary = {"sense": "sight", "player_involved": false, "text": ""}
	var actor_name: String = _recognized_name(observer, attacker) if sees_attacker else "someone"
	if observer == victim:
		event.sense = "touch"
		event.text = "I was hurt by %s." % actor_name if sees_attacker \
			else "I was struck, but I could not see who did it."
		event.player_involved = sees_attacker and attacker.is_in_group("players")
	elif sees_victim:
		var action: String = "kill" if fatal else "hurt"
		if observer == attacker:
			event.text = "I %s %s." % ["killed" if fatal else "hurt", _recognized_name(observer, victim)]
		elif sees_attacker:
			event.text = "I saw %s %s %s nearby." % [actor_name, action, _recognized_name(observer, victim)]
		else:
			event.text = "I saw %s %s nearby, but could not see who caused it." % [
				_recognized_name(observer, victim), "die" if fatal else "get hurt"]
		event.player_involved = victim.is_in_group("players") \
			or (sees_attacker and attacker.is_in_group("players"))
	elif observer.npc_data.hearing_radius > 0.0 and observer.global_position.distance_to(
			victim.global_position) <= observer.npc_data.hearing_radius:
		event.sense = "hearing"
		event.text = "I heard sounds of fighting nearby, but could not see what happened."
	else:
		return {}
	event.participants = []
	for participant: BaseActor in [victim, attacker]:
		if event.sense == "hearing" or not is_instance_valid(participant) or not can_see(observer, participant):
			continue
		var identity: String = "player" if participant.is_in_group("players") else ""
		if participant is BaseNpc and participant.get_npc_profile() != null \
			and observer.is_in_group(&"town_residents") and participant.is_in_group(&"town_residents"):
			identity = String(participant.get_npc_profile().npc_id)
		var visible_person: Dictionary = {"id": identity, "name": _recognized_name(observer, participant),
			"role": "hurt_person" if participant == victim else "aggressor"}
		for neighbor: Dictionary in observer.life_context.get("known_townspeople", []):
			if neighbor.id == identity:
				visible_person.relationship = neighbor.relationship.duplicate(true)
		event.participants.append(visible_person)
	return event

static func _recognized_name(observer: BaseNpc, target: BaseActor) -> String:
	if target is BaseNpc and observer.is_in_group(&"town_residents") \
		and target.is_in_group(&"town_residents") and target.get_npc_profile() != null:
		return target.get_npc_profile().profile_name
	return target.get_perceived_name()

static func can_see(observer: BaseNpc, target: BaseActor) -> bool:
	if observer.world_space != target.world_space or observer.is_sleeping():
		return false
	if observer == target:
		return true
	if observer.npc_data.vision_radius <= 0.0 or observer.global_position.distance_to(
			target.global_position) > observer.npc_data.vision_radius:
		return false
	var offset := Vector2(0.0, -4.0)
	var ray := PhysicsRayQueryParameters2D.create(observer.global_position + offset,
		target.global_position + offset, observer.npc_data.vision_collision_mask)
	ray.exclude = [observer.get_rid()]
	var hit: Dictionary = observer.get_world_2d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or hit.get("collider") == target
