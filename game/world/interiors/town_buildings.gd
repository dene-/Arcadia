class_name TownBuildings
extends Node2D

## Owns door transitions and multi-space journeys; actors and cognition remain alive across doors.
## It is the brain's travel executor: each journey belongs to one task id, so a late cancel or
## state query from an older task can never touch a newer journey.
signal player_space_changed

var seed_value: int
var rooms: Dictionary[StringName, NpcInterior] = {}
var outdoors: TownNavigation
var _journeys: Dictionary = {}
var _residents: Dictionary = {}
var _player_camera_limits: Rect2i

func _ready() -> void:
	y_sort_enabled = true
	var population: TownPopulation = get_node("/root/NpcCognition").save_game.population
	population.ensure_population(seed_value)
	for index: int in range(RegionLayout.HOMES.size()):
		var home: Dictionary = RegionLayout.HOMES[index]
		var room := NpcInterior.new()
		room.name = String(home.job).capitalize() + "Interior"
		room.resident_id = TownPopulation.FOUNDERS.get(home.job, home.job)
		room.residents = population.members_of(room.resident_id)
		room.resident_name = population.people[room.residents[0]].name.get_slice(" ", 1)
		room.job = home.job
		room.seed_value = seed_value
		room.position = Vector2(4096 + index * 512, 4096)
		room.outside = Vector2(home.cell * 8) + Vector2(0, 6)
		add_child(room)
		var space := StringName("home:" + room.resident_id)
		rooms[space] = room
		var door := BuildingDoor.new()
		door.name = String(home.job).capitalize() + "Door"
		door.position = Vector2(home.cell * 8) + Vector2(0, 4)
		door.label = "Enter " + room.resident_name + " household"
		add_child(door)
		door.used.connect(func(player: BasePlayer) -> void: move_player(player, space))
		room.door.used.connect(func(player: BasePlayer) -> void: move_player(player, &"outdoors"))

func prepare_navigation(shared: TownNavigation, bodies: Array[RID]) -> void:
	outdoors = shared
	for room: NpcInterior in rooms.values():
		room.navigation.clearance = shared.clearance
		room.navigation.build(get_world_2d().direct_space_state, bodies)

func navigation_for(space: StringName) -> TownNavigation:
	return outdoors if space == &"outdoors" or not rooms.has(space) else rooms[space].navigation

func restore(npc: BaseNpc, id: String, saved: Dictionary) -> void:
	_residents[id] = weakref(npc)
	var space := StringName(saved.get("space", "outdoors"))
	if space != &"outdoors" and not rooms.has(space):
		return
	if saved.position.size() == 2:
		var point := Vector2(saved.position[0], saved.position[1])
		if navigation_for(space).is_clear(point):
			_transfer(npc, id, space, point)

func begin_task_travel(npc: Object, npc_id: String, space: StringName, point: Vector2,
		label: String, owner_task_id: String) -> bool:
	if not npc is BaseNpc or owner_task_id.is_empty() \
			or (space != &"outdoors" and not rooms.has(space)):
		return false
	_residents[npc_id] = weakref(npc)
	_journeys[npc_id] = {"owner": owner_task_id, "npc": weakref(npc), "space": space,
		"point": point, "label": label, "state": &"traveling"}
	_next_leg(npc, npc_id)
	return true

## A one-cell step near where the resident stands, as an idle gesture of the owning task. It
## reserves no space and crosses no door, so it fails when the target cell is not walkable
## right there; the journey then completes like any other for `task_travel_state`.
func begin_task_nudge(npc: Object, npc_id: String, point: Vector2, owner_task_id: String) -> bool:
	if not npc is BaseNpc or owner_task_id.is_empty() or _journeys.has(npc_id):
		return false
	var navigation: TownNavigation = navigation_for((npc as BaseNpc).world_space)
	var target: Vector2 = navigation.nearest(point)
	if target.distance_to(point) > TownNavigation.CELL_SIZE or target.distance_to(npc.global_position) < 4.0:
		return false
	_residents[npc_id] = weakref(npc)
	_journeys[npc_id] = {"owner": owner_task_id, "npc": weakref(npc), "space": npc.world_space,
		"point": target, "label": npc.daily_routine.place, "state": &"traveling"}
	npc.daily_routine.navigation = navigation
	npc.daily_routine.travel(npc.global_position, target, npc.daily_routine.activity,
		npc.daily_routine.place)
	npc.state_time_remaining = 0
	return true

func cancel_task_travel(npc_id: String, owner_task_id: String) -> bool:
	var journey: Dictionary = _journeys.get(npc_id, {})
	if journey.is_empty() or journey.owner != owner_task_id:
		return false
	_journeys.erase(npc_id)
	var npc: BaseNpc = journey.npc.get_ref() as BaseNpc
	if journey.state == &"traveling" and npc != null:
		npc.daily_routine.stop()
	return true

func task_travel_state(npc_id: String, owner_task_id: String) -> StringName:
	var journey: Dictionary = _journeys.get(npc_id, {})
	if journey.is_empty() or journey.owner != owner_task_id:
		return &"none"
	return journey.state

## The resident's own bed when it stands in a room it lives in; null anywhere else.
func bed_for(npc_id: String) -> Variant:
	var npc: BaseNpc = _residents[npc_id].get_ref() as BaseNpc if _residents.has(npc_id) else null
	if npc == null or not rooms.has(npc.world_space) or not npc_id in rooms[npc.world_space].residents:
		return null
	return rooms[npc.world_space].bed_for(npc_id, true)

## Progresses a journey through doors; arriving only marks the journey for its owning task.
func advance(npc: BaseNpc, id: String) -> void:
	if not _journeys.has(id) or _journeys[id].state != &"traveling" or not npc.can_follow_routine():
		return
	var journey: Dictionary = _journeys[id]
	# A family can queue at a doorway without every body reaching the same pixel.
	var tolerance: float = 3.0 if npc.world_space == journey.space else 10.0
	if npc.global_position.distance_to(npc.daily_routine.destination) > tolerance:
		return
	if npc.world_space != journey.space and not navigation_for(npc.world_space).can_travel(
			npc.global_position, npc.daily_routine.destination):
		return
	if npc.world_space == journey.space:
		journey.state = &"arrived"
		return
	if npc.world_space != &"outdoors":
		if not _transfer(npc, id, &"outdoors", rooms[npc.world_space].outside):
			return
	else:
		if not _transfer(npc, id, journey.space, rooms[journey.space].entrance):
			return
	_next_leg(npc, id)

func release(npc: BaseNpc, id: String) -> void:
	_journeys.erase(id)
	_residents.erase(id)
	navigation_for(npc.world_space).release(id)

func move_player(player: BasePlayer, destination: StringName) -> void:
	if outdoors == null or destination == player.world_space:
		return
	var camera: Camera2D = player.get_node("Camera2D")
	var point: Vector2
	if destination == &"outdoors":
		if not rooms.has(player.world_space):
			return
		point = rooms[player.world_space].outside
		if not _transfer(player, "player:%d" % player.get_instance_id(), destination, point):
			return
		camera.limit_left = _player_camera_limits.position.x
		camera.limit_top = _player_camera_limits.position.y
		camera.limit_right = _player_camera_limits.end.x
		camera.limit_bottom = _player_camera_limits.end.y
	else:
		if not rooms.has(destination):
			return
		var room: NpcInterior = rooms[destination]
		point = room.player_entrance
		if not _transfer(player, "player:%d" % player.get_instance_id(), destination, point):
			return
		_player_camera_limits = Rect2i(camera.limit_left, camera.limit_top,
			camera.limit_right - camera.limit_left, camera.limit_bottom - camera.limit_top)
		camera.limit_left = int(room.global_position.x) - 120
		camera.limit_right = int(room.global_position.x) + 120
		camera.limit_top = int(room.global_position.y) - 80
		camera.limit_bottom = int(room.global_position.y) + 80
	camera.reset_smoothing()
	camera.force_update_scroll()

func _next_leg(npc: BaseNpc, id: String) -> void:
	var journey: Dictionary = _journeys[id]
	var point: Vector2 = journey.point
	if npc.world_space != journey.space:
		point = rooms[npc.world_space].entrance if npc.world_space != &"outdoors" \
			else rooms[journey.space].outside
	var navigation: TownNavigation = navigation_for(npc.world_space)
	npc.daily_routine.navigation = navigation
	# Door thresholds and the resident's bed are fixed anchors, not gathering spots.
	var fixed_bed: bool = npc.daily_routine.activity == "rest" and rooms.has(npc.world_space) \
		and id in rooms[npc.world_space].residents
	var destination: Vector2 = navigation.reserve_destination(id, point) \
		if npc.world_space == journey.space and not fixed_bed else navigation.nearest(point)
	npc.daily_routine.travel(npc.global_position, destination, npc.daily_routine.activity, journey.label)
	npc.state_time_remaining = 0

func _transfer(actor: BaseActor, id: String, space: StringName, point: Vector2) -> bool:
	var safe_point: Vector2 = navigation_for(space).landing(actor, point)
	if safe_point == Vector2.INF:
		return false
	navigation_for(actor.world_space).release(id)
	actor.world_space = space
	actor.world_space_label = "Rekala" if space == &"outdoors" else rooms[space].resident_name + "'s home and shop"
	actor.global_position = safe_point
	actor.velocity = Vector2.ZERO
	actor.reset_physics_interpolation()
	navigation_for(space).register(id, actor)
	if actor is BaseNpc:
		actor.life_revision += 1
	elif actor is BasePlayer:
		player_space_changed.emit()
	return true
