class_name NpcPerception
extends RefCounted

## Converts a real combat event into only what this observer could perceive.
static func observe(observer: BaseNpc, victim: BaseActor, attacker: BaseActor,
		fatal: bool) -> Dictionary:
	if observer.health <= 0 or not observer.npc_data.perception_enabled:
		return {}
	var sees_victim: bool = can_see(observer, victim)
	var sees_attacker: bool = is_instance_valid(attacker) and can_see(observer, attacker)
	var event: Dictionary = {"sense": "sight", "player_involved": false, "text": ""}
	var actor_name: String = attacker.get_perceived_name() if sees_attacker else "someone"
	if observer == victim:
		event.sense = "touch"
		event.text = "I was hurt by %s." % actor_name if sees_attacker \
			else "I was struck, but I could not see who did it."
		event.player_involved = sees_attacker and attacker.is_in_group("players")
	elif sees_victim:
		var action: String = "kill" if fatal else "hurt"
		if observer == attacker:
			event.text = "I %s %s." % ["killed" if fatal else "hurt", victim.get_perceived_name()]
		elif sees_attacker:
			event.text = "I saw %s %s %s nearby." % [actor_name, action, victim.get_perceived_name()]
		else:
			event.text = "I saw %s %s nearby, but could not see who caused it." % [
				victim.get_perceived_name(), "die" if fatal else "get hurt"]
		event.player_involved = victim.is_in_group("players") \
			or (sees_attacker and attacker.is_in_group("players"))
	elif observer.npc_data.hearing_radius > 0.0 and observer.global_position.distance_to(
			victim.global_position) <= observer.npc_data.hearing_radius:
		event.sense = "hearing"
		event.text = "I heard sounds of fighting nearby, but could not see what happened."
	else:
		return {}
	return event

static func can_see(observer: BaseNpc, target: BaseActor) -> bool:
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
