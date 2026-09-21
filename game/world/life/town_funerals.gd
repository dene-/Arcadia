class_name TownFunerals
extends Node

## Coordinates physical discovery, reporting, recovery and burial through ordinary actor routes.
## TownDeaths owns persistence; cognition sees only each participant's perceived facts.
var life: TownLife
var cemetery: TownCemetery
var _bodies: Dictionary[String, NpcRemains] = {}
var _scan_elapsed: float = 0.0
var _routed: Dictionary = {}
var _settled: Dictionary = {}

func _ready() -> void:
	cemetery = life.get_parent().get_node("Cemetery")
	get_node("/root/WorldEvents").occurred.connect(_on_event)
	for id: String in life.save_game.deaths.records:
		if life.save_game.population.people.has(id):
			_settled[id] = true
			_refresh_visual(id)

func _exit_tree() -> void:
	for id: String in _bodies:
		if is_instance_valid(_bodies[id]):
			_bodies[id].queue_free()

func _on_event(event: WorldEvent) -> void:
	if event.kind != &"body_settled":
		return
	var npc: BaseNpc = event.subject
	var id: String = String(npc.get_npc_profile().npc_id)
	var records: Dictionary = life.save_game.deaths.records
	if not records.has(id):
		return
	records[id].position = [npc.global_position.x, npc.global_position.y]
	records[id].space = String(npc.world_space)
	_settled[id] = true
	_refresh_visual(id)
	life.save_snapshot()

func advance(delta: float) -> void:
	for id: String in _bodies:
		var entry: Dictionary = life.save_game.deaths.records[id]
		if entry.stage == "carried":
			var guard: BaseNpc = _actor(entry.guard)
			if guard != null:
				if guard.has_enemy_target() or guard.state_machine.is_in_state(&"hurt"):
					_change(id, "reported")
					_routed.erase(entry.guard)
					_bodies[id].set_carried(false)
					continue
				# A covered body follows its carrier through the same doors, never teleports ahead.
				_bodies[id].global_position = guard.global_position + Vector2(0, -7)
				entry.position = [_bodies[id].global_position.x, _bodies[id].global_position.y]
				entry.space = String(guard.world_space)
	_scan_elapsed += delta
	if _scan_elapsed < 1:
		return
	_scan_elapsed = 0
	for id: String in life.save_game.deaths.records:
		var entry: Dictionary = life.save_game.deaths.records[id]
		if not _settled.has(id) or entry.stage == "buried":
			continue
		if not entry.guard.is_empty() and _actor(entry.guard) == null:
			entry.guard = ""
			entry.reporter = ""
			# A fallen carrier cannot radio a new body location to the rest of town.
			_change(id, "fallen")
			_refresh_visual(id)
		for npc_id: String in life.resident_ids():
			var npc: BaseNpc = _actor(npc_id)
			if npc == null or npc.alert_response.active() \
				or (npc_id in entry.known_by and entry.stage != "fallen"):
				continue
			if NpcPerception.can_see_point(npc, StringName(entry.space), _point(entry)):
				if not npc_id in entry.known_by:
					entry.known_by.append(npc_id)
				_observe(npc, id, "body_found", "I found %s's body here." % _name(id), "sight")
				if entry.stage == "fallen":
					entry.reporter = npc_id
					_change(id, "discovered")
				if npc.is_in_group(&"town_guards") and entry.guard.is_empty() and not _busy(npc_id, id):
					entry.guard = npc_id
					_change(id, "reported")
		if entry.stage == "discovered" and (_actor(entry.reporter) == null or _busy(entry.reporter, id)):
			entry.reporter = ""
			for witness: String in entry.known_by:
				var npc: BaseNpc = _actor(witness)
				if npc != null and not npc.is_sleeping() and not _busy(witness, id):
					entry.reporter = witness
					break

func maintain(npc: BaseNpc, npc_id: String) -> bool:
	if npc.alert_response.active():
		return true
	for id: String in life.save_game.deaths.records:
		var entry: Dictionary = life.save_game.deaths.records[id]
		if entry.stage == "discovered" and entry.reporter == npc_id:
			return _report(npc, npc_id, id, entry)
		if entry.guard == npc_id and entry.stage in ["reported", "recovering", "carried"]:
			return _recover(npc, npc_id, id, entry)
	return false

func _report(npc: BaseNpc, npc_id: String, id: String, entry: Dictionary) -> bool:
	if not npc.can_follow_routine():
		return true
	# Take a moment to absorb the discovery before setting off for help.
	if life.save_game.life.minute - entry.since < 4:
		_pause(npc, npc_id)
		return true
	if npc.is_in_group(&"town_guards") and not _busy(npc_id, id):
		entry.guard = npc_id
		_change(id, "reported")
		_resume(npc, npc_id)
		return true
	var guard: BaseNpc
	var distance: float = INF
	for candidate_id: String in life.resident_ids():
		var candidate: BaseNpc = _actor(candidate_id)
		if candidate == null or not candidate.is_in_group(&"town_guards") or _busy(candidate_id):
			continue
		var next: float = npc.global_position.distance_to(candidate.global_position)
		# Prefer an awake watchman, but a guard at home can be roused if needed.
		if candidate.is_sleeping():
			next += 10000
		if next < distance:
			distance = next
			guard = candidate
	if guard == null:
		_resume(npc, npc_id)
		return false # No surviving guard: the body remains, and normal safety still applies.
	if npc.world_space == guard.world_space and npc.global_position.distance_to(guard.global_position) < 28 \
		and NpcPerception.can_see(npc, guard):
		entry.guard = String(guard.get_npc_profile().npc_id)
		guard.alert_response.notice(guard, {"danger_possible": true, "origin_id": "body:" + id})
		if not entry.guard in entry.known_by:
			entry.known_by.append(entry.guard)
		_observe(guard, id, "body_reported", "%s told me they found %s dead. The cause is unconfirmed." % [
			npc.get_npc_profile().profile_name, _name(id)], "hearing")
		npc.show_spoken_reaction("%s is dead. Please, come with me." % _name(id).get_slice(" ", 0))
		_change(id, "reported")
		_resume(npc, npc_id)
		return true
	_move(npc, npc_id, guard.world_space, guard.global_position + Vector2(0, 16), "seek_guard", "finding a guard")
	return true

func _recover(guard: BaseNpc, guard_id: String, id: String, entry: Dictionary) -> bool:
	if not guard.can_follow_routine():
		return true
	if entry.stage == "carried":
		var plot: Vector2 = cemetery.plot_for(id) + Vector2(0, 12)
		_move(guard, guard_id, &"outdoors", plot, "burial", "the cemetery")
		if guard.world_space != &"outdoors" or guard.global_position.distance_to(plot) > 16:
			entry.since = life.save_game.life.minute
			return true
		if life.save_game.life.minute - entry.since < 12:
			return true
		_change(id, "buried")
		_refresh_visual(id)
		for observer_id: String in life.resident_ids():
			var observer: BaseNpc = _actor(observer_id)
			if observer != null and NpcPerception.can_see_point(observer, &"outdoors", plot):
				entry.burial_known_by.append(observer_id)
				_observe(observer, id, "body_buried", "I saw %s laid to rest in the town cemetery." % _name(id), "sight")
		guard.show_spoken_reaction("Rest easy.")
		_resume(guard, guard_id)
		life.save_game.save_file()
		return true
	var point: Vector2 = _point(entry)
	_move(guard, guard_id, StringName(entry.space), point + Vector2(0, 12), "recover_body", "a reported death")
	if guard.world_space != StringName(entry.space) or guard.global_position.distance_to(point) > 24 \
		or not NpcPerception.can_see_point(guard, StringName(entry.space), point) or not _safe(guard, point):
		if entry.stage == "recovering":
			_change(id, "reported")
		return true
	if entry.stage == "reported":
		_change(id, "recovering")
		guard.show_spoken_reaction("Give me some room, please.")
	elif life.save_game.life.minute - entry.since >= 6:
		_change(id, "carried")
		_routed.erase(guard_id)
		_bodies[id].set_carried(true)
	return true

func _safe(guard: BaseNpc, point: Vector2) -> bool:
	for npc: BaseNpc in get_tree().get_nodes_in_group(&"enemies"):
		if npc.health > 0 and NpcPerception.can_see(guard, npc) and npc.global_position.distance_to(point) < 80:
			guard.set_enforcement_target(npc)
			return false
	for id: String in life.resident_ids():
		var npc: BaseNpc = _actor(id)
		if npc != null and npc.world_space == guard.world_space \
			and npc.alert_response.active() and npc.global_position.distance_to(point) < 64:
			return false
	return not guard.has_enemy_target()

func _move(npc: BaseNpc, id: String, space: StringName, point: Vector2, activity: String, label: String) -> void:
	life.encounters.interrupt(id)
	npc.daily_routine.hold(false)
	var previous: Dictionary = _routed.get(id, {})
	if not previous.is_empty() and previous.space == space and previous.activity == activity \
		and Vector2(previous.point).distance_to(point) < 20 and npc.daily_routine.activity == activity:
		return
	_routed[id] = {"space": space, "point": point, "activity": activity}
	npc.life_revision += 1 # Invalidates pending ordinary routine/model results.
	life.buildings.travel(npc, id, space, point, activity, label)

func _pause(npc: BaseNpc, id: String) -> void:
	life.encounters.interrupt(id)
	npc.daily_routine.hold(true)

func _resume(npc: BaseNpc, id: String) -> void:
	npc.daily_routine.hold(false)
	_routed.erase(id)
	life.save_game.life.interrupt(id)

func _busy(npc_id: String, except_body: String = "") -> bool:
	for id: String in life.save_game.deaths.records:
		if id == except_body:
			continue
		var entry: Dictionary = life.save_game.deaths.records[id]
		if (entry.guard == npc_id and entry.stage in ["reported", "recovering", "carried"]) \
			or (entry.reporter == npc_id and entry.stage == "discovered"):
			return true
	return false

func is_assigned(id: String) -> bool:
	return _busy(id)

func known_losses(npc_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in life.save_game.deaths.records:
		var entry: Dictionary = life.save_game.deaths.records[id]
		if not npc_id in entry.known_by and not npc_id in entry.burial_known_by:
			continue
		result.append({"id": id, "name": _name(id), "relationship":
			life.save_game.population.people[npc_id].kin.get(id, "neighbor"),
			"burial_witnessed": npc_id in entry.burial_known_by})
	return result

func _actor(id: String) -> BaseNpc:
	return life.resident(id)

func _point(entry: Dictionary) -> Vector2:
	return Vector2(entry.position[0], entry.position[1])

func _name(id: String) -> String:
	return life.save_game.population.people[id].name

func _change(id: String, stage: String) -> void:
	life.save_game.deaths.transition(id, stage, life.save_game.life.minute)
	life.save_snapshot()

func _refresh_visual(id: String) -> void:
	var entry: Dictionary = life.save_game.deaths.records[id]
	if entry.stage == "buried":
		if _bodies.has(id):
			_bodies[id].queue_free()
			_bodies.erase(id)
		cemetery.bury(id, _name(id))
		return
	if not _bodies.has(id):
		var person: Dictionary = life.save_game.population.people[id]
		var frames: SpriteFrames = TownResidentArt.frames_for(person)
		if TownPopulation.FOUNDERS.values().has(id):
			frames = load("res://game/resources/actors/humans/%s_npc_data.tres" % person.job).sprite_frames
		var body := NpcRemains.new()
		body.name = id.to_pascal_case() + "Remains"
		body.configure(frames)
		life.get_parent().add_child(body)
		_bodies[id] = body
	_bodies[id].global_position = _point(entry)
	_bodies[id].set_carried(entry.stage == "carried")

func _observe(observer: BaseNpc, id: String, kind: String, text: String, sense: String) -> void:
	var event := WorldEvent.new()
	event.kind = StringName(kind)
	event.subject = observer
	event.facts = {"kind": kind, "text": text, "sense": sense, "player_involved": false,
		"danger_possible": false, "directly_affected": false, "topics": ["death", "town"],
		"participants": [{"id": id, "name": _name(id), "role": "deceased",
			"relationship": life.save_game.population.people[String(observer.get_npc_profile().npc_id)].kin.get(id, "neighbor")} ]}
	get_node("/root/WorldEvents").publish(event)
