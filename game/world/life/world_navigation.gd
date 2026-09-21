class_name WorldNavigation
extends Node

## Scene-owned navigation for town and forest actors; interiors retain separate grids.
signal initialized
var outdoors := TownNavigation.new()

func _ready() -> void:
	add_to_group(&"actor_navigation_world")
	await get_tree().physics_frame
	await get_tree().physics_frame
	outdoors.area = RegionLayout.BOUNDS
	var largest_footprint: float = 0.0
	for actor: BaseActor in get_tree().get_nodes_in_group(&"actors"):
		if actor is BaseNpc:
			largest_footprint = maxf(largest_footprint, ActorFootprint.radius(actor))
	if largest_footprint > 0:
		outdoors.clearance = largest_footprint + ActorFootprint.MARGIN
	outdoors.build(get_parent().get_world_2d().direct_space_state)
	for actor: BaseActor in get_tree().get_nodes_in_group(&"actors"):
		register_actor(actor)
	initialized.emit()

func register_actor(actor: BaseActor) -> void:
	if not is_instance_valid(actor) or actor.world_space != &"outdoors" or not outdoors.ready:
		return
	var id: String = "actor:%d" % actor.get_instance_id()
	if actor is BasePlayer:
		id = "player:%d" % actor.get_instance_id()
	elif actor is BaseNpc and actor.get_npc_profile() != null:
		id = String(actor.get_npc_profile().npc_id)
	outdoors.register(id, actor)
