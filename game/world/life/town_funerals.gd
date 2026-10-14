class_name TownFunerals
extends Node

## Scene adapter for bodies: draws remains and graves, gates discovery on perception, and starts
## each participant's NpcRecoveryTask through its brain. TownDeaths owns every lifecycle change;
## the tasks make them through its intent API using the services provided here.
const OWNER: String = "funerals"
## A deferred reporter or a guard whose recovery failed tries again after this many minutes.
const RETRY_MINUTES: float = 30.0

var life: TownLife
var cemetery: TownCemetery
var _bodies: Dictionary[String, NpcRemains] = {}
var _scan_elapsed: float = 0.0
var _settled: Dictionary = {}
# npc_id -> world minute before which funerals assigns this resident nothing. Not saved.
var _retry_at: Dictionary = {}

func _ready() -> void:
	cemetery = life.get_parent().get_node("Cemetery")
	get_node("/root/WorldEvents").occurred.connect(_on_event)
	for id: String in _deaths().ids():
		if life.save_game.population.people.has(id):
			_settled[id] = true
			_refresh_visual(id)
	for id: String in life.resident_ids():
		var brain: NpcBrain = life.brain_for(id)
		if brain == null:
			continue
		brain.provide_service(&"deaths", _deaths)
		brain.provide_service(&"guard_roster", _guard_roster)
		brain.provide_service(&"visible_guards", _visible_guards.bind(id))
		brain.provide_service(&"assess_scene", _assess_scene.bind(id))
		brain.provide_service(&"cemetery_plot", cemetery.plot_for)
		brain.provide_service(&"recovery_event", _recovery_event.bind(id))
		brain.task_finished.connect(_on_task_finished.bind(id))

func _exit_tree() -> void:
	for id: String in _bodies:
		if is_instance_valid(_bodies[id]):
			_bodies[id].queue_free()

func _on_event(event: WorldEvent) -> void:
	if event.kind != &"body_settled":
		return
	var npc: BaseNpc = event.subject
	var id: String = String(npc.get_npc_profile().npc_id)
	if _deaths().settle(id, String(npc.world_space), npc.global_position) != TownDeaths.OK_RESULT:
		return
	_settled[id] = true
	_refresh_visual(id)
	life.save_snapshot()

func advance(delta: float) -> void:
	for id: String in _bodies.keys():
		var entry: Dictionary = _deaths().snapshot(id)
		var carrier: BaseNpc = _actor(entry.guard) if entry.stage == "carried" else null
		if carrier == null:
			continue
		# Combat or injury makes the carrier set the body down where it stands.
		var brain: NpcBrain = life.brain_for(entry.guard)
		if (carrier.has_enemy_target() or carrier.state_machine.is_in_state(&"hurt")) \
				and brain != null and brain.controller.current is NpcRecoveryTask:
			brain.interrupt(NpcTask.Interrupt.DANGER)
		_refresh_visual(id)
	_scan_elapsed += delta
	if _scan_elapsed < 1:
		return
	_scan_elapsed = 0
	for id: String in _deaths().ids():
		if _settled.has(id) and _deaths().snapshot(id).stage != "buried":
			_scan(id)

func _scan(id: String) -> void:
	var deaths: TownDeaths = _deaths()
	var minute: float = life.save_game.life.minute
	var entry: Dictionary = deaths.snapshot(id)
	for actor_id: String in [entry.reporter, entry.guard]:
		if not actor_id.is_empty() and _actor(actor_id) == null:
			deaths.release_assignment(id, actor_id, minute)
	entry = deaths.snapshot(id)
	_refresh_visual(id)
	var point: Vector2 = _point(entry)
	for npc_id: String in life.resident_ids():
		var npc: BaseNpc = _actor(npc_id)
		if npc == null or npc.alert_response.active() or npc_id in entry.known_by \
				or not NpcPerception.can_see_point(npc, StringName(entry.space), point):
			continue
		if deaths.discover(id, npc_id, minute) == TownDeaths.OK_RESULT:
			_observe(npc, id, "body_found", "I found %s's body here." % _name(id), "sight", point)
	entry = deaths.snapshot(id)
	if entry.stage != "discovered" or not entry.reporter.is_empty():
		return
	for witness: String in entry.known_by:
		var npc: BaseNpc = _actor(witness)
		if npc != null and not npc.is_sleeping() and _free(witness) \
				and deaths.claim_report(id, witness, minute) == TownDeaths.OK_RESULT:
			return

## Starts or keeps this resident's recovery duty. True while funerals engages the resident.
func maintain(npc: BaseNpc, npc_id: String) -> bool:
	if npc.alert_response.active():
		return true
	var brain: NpcBrain = life.brain_for(npc_id)
	if brain == null:
		return false
	var minute: float = life.save_game.life.minute
	var live: NpcRecoveryTask = _recovery_task(brain)
	if live != null:
		if live.phase != NpcRecoveryTask.PHASE_DEFERRED:
			return true
		# No guard found anywhere the witness knew of: every report this witness holds stays open
		# for a later try, and the witness returns to ordinary life meanwhile.
		brain.end_task(live.task_id, &"deferred")
		for id: String in _deaths().ids():
			var held: Dictionary = _deaths().snapshot(id)
			if held.stage == "discovered" and held.reporter == npc_id:
				_deaths().release_assignment(id, npc_id, minute)
		_retry_at[npc_id] = minute + RETRY_MINUTES
		return false
	if float(_retry_at.get(npc_id, -INF)) > minute:
		return false
	var guard: bool = npc.is_in_group(&"town_guards")
	for id: String in _deaths().ids():
		var entry: Dictionary = _deaths().snapshot(id)
		if entry.stage == "discovered" and entry.reporter == npc_id:
			if not guard:
				return _start(brain, npc_id, id, NpcRecoveryTask.WITNESS)
			# A discovering guard acknowledges its own report.
			if _deaths().acknowledge_report(id, npc_id, npc_id, minute) == TownDeaths.OK_RESULT:
				return _start(brain, npc_id, id, NpcRecoveryTask.GUARD)
		if entry.guard == npc_id and entry.stage in ["reported", "recovering", "carried"]:
			return _start(brain, npc_id, id, NpcRecoveryTask.GUARD)
	if not guard or npc.is_sleeping():
		return false
	for id: String in _deaths().ids():
		var entry: Dictionary = _deaths().snapshot(id)
		if entry.stage == "reported" and entry.guard.is_empty() and npc_id in entry.known_by:
			return _start(brain, npc_id, id, NpcRecoveryTask.GUARD)
	return false

func _start(brain: NpcBrain, npc_id: String, id: String, role: String) -> bool:
	var witness: bool = role == NpcRecoveryTask.WITNESS
	var task := NpcRecoveryTask.create({"role": role, "body": id,
		"activity": "seek_guard" if witness else "recover_body",
		"label": "finding a guard" if witness else "a reported death"}, life.tuning)
	if not witness:
		return brain.request_task(task)
	var commitments: NpcCommitments = life.save_game.minds.get_mind(npc_id).commitments
	var commitment_id: String = _report_commitment(npc_id, id)
	if not commitment_id.is_empty():
		task.commitment_ids.assign([commitment_id])
	if not brain.request_task(task):
		return false
	if not commitment_id.is_empty():
		commitments.link_task(commitment_id, task.task_id)
	return true

# The witness's open report_discovery commitment for this body, created once and citing the
# observation through which the witness learned of the death.
func _report_commitment(npc_id: String, id: String) -> String:
	var mind: NpcMindState = life.save_game.minds.get_mind(npc_id)
	for item: Dictionary in mind.commitments.open_commitments():
		if item["kind"] == "report_discovery" and id in item["other_ids"]:
			return item["id"]
	var evidence: Array[String] = []
	for fact: Dictionary in mind.knowledge.current(id, "status"):
		if fact["value"] == "dead" and not (fact["evidence_ids"] as Array).is_empty():
			evidence.append((fact["evidence_ids"] as Array).back())
			break
	var others: Array[String] = [id]
	return mind.commitments.create("report_discovery", others, evidence, life.save_game.life.minute)

static func _recovery_task(brain: NpcBrain) -> NpcRecoveryTask:
	for task: NpcTask in [brain.controller.current, brain.controller.suspended]:
		if task is NpcRecoveryTask:
			return task
	return null

func _on_task_finished(task_id: String, status: String, _reason: StringName, id: String) -> void:
	if task_id.begins_with("recovery:") and status == NpcTask.status_name(NpcTask.Status.FAILED):
		_retry_at[id] = life.save_game.life.minute + RETRY_MINUTES

## After a reload: drop any errand an older build of funerals left in the task stack. Restored
## recovery tasks revalidate themselves against TownDeaths.
func reconcile(_id: String, brain: NpcBrain) -> void:
	for task: NpcTask in [brain.controller.current, brain.controller.suspended]:
		if task != null and task.params.get("owner") == OWNER:
			brain.end_task(task.task_id, &"unowned")

# --- Services for NpcRecoveryTask ---

func _deaths() -> TownDeaths:
	return life.save_game.deaths

func _guard_roster() -> Array[String]:
	var result: Array[String] = []
	for id: String in life.save_game.population.people:
		if life.save_game.population.people[id].get("job") == "guard":
			result.append(id)
	result.sort()
	return result

func _visible_guards(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var npc: BaseNpc = _actor(id)
	if npc == null:
		return result
	for guard_id: String in life.resident_ids():
		var guard: BaseNpc = _actor(guard_id)
		if guard != null and guard != npc and guard.is_in_group(&"town_guards") and NpcPerception.can_see(npc, guard):
			result.append({"id": guard_id, "space": guard.world_space, "position": guard.global_position})
	return result

func _assess_scene(space: StringName, point: Vector2, id: String) -> StringName:
	var guard: BaseNpc = _actor(id)
	if guard == null or not NpcPerception.can_see_point(guard, space, point):
		return &"unseen"
	for npc: BaseNpc in get_tree().get_nodes_in_group(&"enemies"):
		if npc.health > 0 and NpcPerception.can_see(guard, npc) and npc.global_position.distance_to(point) < 80:
			guard.set_enforcement_target(npc)
			return &"danger"
	for other_id: String in life.resident_ids():
		var npc: BaseNpc = _actor(other_id)
		if npc != null and npc.world_space == guard.world_space \
				and npc.alert_response.active() and npc.global_position.distance_to(point) < 64:
			return &"danger"
	return &"danger" if guard.has_enemy_target() else &"clear"

func _recovery_event(event: StringName, id: String, other: String, npc_id: String) -> void:
	var npc: BaseNpc = _actor(npc_id)
	match event:
		&"reported":
			var guard: BaseNpc = _actor(other)
			if guard != null and npc != null:
				guard.alert_response.notice(guard, {"danger_possible": true, "origin_id": "body:" + id})
				_observe(guard, id, "body_reported", "%s told me they found %s dead. The cause is unconfirmed." % [
					npc.get_npc_profile().profile_name, _name(id)], "hearing", null, npc)
				npc.show_spoken_reaction("%s is dead. Please, come with me." % _name(id).get_slice(" ", 0))
		&"preparing":
			if npc != null:
				npc.show_spoken_reaction("Give me some room, please.")
		&"buried":
			var plot: Vector2 = cemetery.plot_for(id)
			for observer_id: String in life.resident_ids():
				var observer: BaseNpc = _actor(observer_id)
				if observer != null and NpcPerception.can_see_point(observer, &"outdoors", plot):
					_deaths().mark_burial_known(id, observer_id)
					_observe(observer, id, "body_buried", "I saw %s laid to rest in the town cemetery." % _name(id),
						"sight", plot)
			if npc != null:
				npc.show_spoken_reaction("Rest easy.")
	_refresh_visual(id)
	life.save_snapshot()

# --- Queries ---

func _free(npc_id: String) -> bool:
	return not is_assigned(npc_id) and float(_retry_at.get(npc_id, -INF)) <= life.save_game.life.minute

func is_assigned(npc_id: String) -> bool:
	for id: String in _deaths().ids():
		var entry: Dictionary = _deaths().snapshot(id)
		if (entry.guard == npc_id and entry.stage in ["reported", "recovering", "carried"]) \
				or (entry.reporter == npc_id and entry.stage == "discovered"):
			return true
	return false

func known_losses(npc_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in _deaths().ids():
		var entry: Dictionary = _deaths().snapshot(id)
		if not npc_id in entry.known_by and not npc_id in entry.burial_known_by:
			continue
		result.append({"id": id, "name": _name(id), "relationship":
			life.save_game.population.people[npc_id].kin.get(id, "neighbor"),
			"burial_witnessed": npc_id in entry.burial_known_by})
	return result

func _actor(id: String) -> BaseNpc:
	return life.resident(id)

static func _point(entry: Dictionary) -> Vector2:
	return Vector2(entry.position[0], entry.position[1])

func _name(id: String) -> String:
	return life.save_game.population.people[id].name

# --- Visuals and observations ---

func _refresh_visual(id: String) -> void:
	var entry: Dictionary = _deaths().snapshot(id)
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
	var carried: bool = entry.stage == "carried"
	var carrier: BaseNpc = _actor(entry.guard) if carried else null
	# A covered body follows its carrier through the same doors, never teleports ahead.
	_bodies[id].global_position = carrier.global_position + Vector2(0, -7) if carrier != null else _point(entry)
	_bodies[id].set_carried(carried)

func _observe(observer: BaseNpc, id: String, kind: String, text: String, sense: String,
		point: Variant = null, reporter: BaseNpc = null) -> void:
	var event := WorldEvent.new()
	event.kind = StringName(kind)
	event.subject = observer
	var relationship: String = life.save_game.population.people[String(observer.get_npc_profile().npc_id)].kin.get(id, "neighbor")
	var participants: Array[Dictionary] = [{"id": id, "name": _name(id), "role": "deceased",
		"relationship": relationship}]
	if reporter != null:
		participants.append({"id": String(reporter.get_npc_profile().npc_id),
			"name": reporter.get_npc_profile().profile_name, "role": "reporter"})
	event.facts = {"kind": kind, "text": text, "sense": sense, "player_involved": false,
		"danger_possible": false, "directly_affected": false, "topics": ["death", "town"],
		"participants": participants}
	if point is Vector2:
		event.facts["position"] = [(point as Vector2).x, (point as Vector2).y]
	get_node("/root/WorldEvents").publish(event)
