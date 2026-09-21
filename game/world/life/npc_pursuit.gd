class_name NpcPursuit
extends RefCounted

## Combat owns the target; this component owns its route and a leased approach slot.
var _route := ActorRoute.new()
var _target_id: int = 0
var _goal := Vector2.INF
var _slot: String = ""
var _can_attack: bool = true

func reset(npc: BaseNpc) -> void:
	if npc.movement_navigation != null:
		npc.movement_navigation.release_attack(npc.movement_id)
	_target_id = 0
	_goal = Vector2.INF
	_slot = ""
	_can_attack = true

func prepare(npc: BaseNpc, target: Node2D, delta: float, in_attack_position: bool) -> void:
	var navigation: TownNavigation = npc.movement_navigation
	if navigation == null:
		return
	if _target_id != target.get_instance_id() or _route.navigation != navigation:
		reset(npc)
		_target_id = target.get_instance_id()
		_route.navigation = navigation
		_route.id = npc.movement_id
		_route.arrival_distance = 0.01
	var reach: float = npc.get_combat_approach_distance(target)
	var choice: Dictionary = navigation.attack_destination(npc.movement_id, target, npc.global_position, reach)
	_can_attack = choice.attack
	if _goal.distance_to(choice.point) >= 0.1 or _slot != choice.slot:
		_goal = choice.point
		if _slot != choice.slot:
			_route.travel(npc.global_position, _goal)
		else:
			_route.retarget(npc.global_position, _goal)
		_slot = choice.slot
	_route.update(npc.global_position, delta,
		holding(npc.global_position) or (_can_attack and in_attack_position))

func may_attack() -> bool:
	return _can_attack

func holding(position: Vector2) -> bool:
	return not _can_attack and position.distance_to(_goal) <= 2.5

func velocity_for(npc: BaseNpc, delta: float) -> Vector2:
	var point: Vector2 = _route.waypoint(npc.global_position)
	var offset: Vector2 = point - npc.global_position
	if delta <= 0.0 or offset.length() <= 0.001:
		return Vector2.ZERO
	var desired: Vector2 = offset.normalized() * minf(npc.current_run_speed(), offset.length() / delta)
	return npc.movement_navigation.steer(npc.movement_id, npc.global_position, desired, delta)
