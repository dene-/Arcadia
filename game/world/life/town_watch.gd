class_name TownWatch
extends Node

## Scene adapter: perception -> saved evidence -> bounded enforcement -> actor mechanics.
## Investigations and patrol stops are directed-travel tasks requested from the guard's NpcBrain
## (owner "watch"); the brain's priorities settle conflicts with other duties.
const OWNER: String = "watch"

var life: TownLife
var _investigations: Dictionary = {}
var _patrol_stops: Dictionary = {}
# npc_id -> {task_id, kind: "investigate"|"patrol"}: the one task the watch owns per guard.
var _tasks: Dictionary = {}
# npc_id -> true once this node listens to the guard's brain.
var _listening: Dictionary = {}
var _hint: Label

func _ready() -> void:
	get_node("/root/WorldEvents").occurred.connect(_on_event)
	var overlay := CanvasLayer.new()
	add_child(overlay)
	_hint = Label.new()
	_hint.theme = preload("res://assets/art/ui/theme.tres")
	_hint.text = "[G] Surrender"
	_hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	_hint.add_theme_constant_override("shadow_offset_y", 1)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_hint)
	_hint.position = Vector2(6, 22)
	_hint.hide()

func _process(_delta: float) -> void:
	var show_hint: bool = false
	for guard: BaseNpc in get_tree().get_nodes_in_group(&"town_guards"):
		if guard.health <= 0:
			continue
		var id: String = String(guard.get_npc_profile().npc_id)
		for player: BasePlayer in get_tree().get_nodes_in_group(&"players"):
			if guard.world_space == player.world_space and guard.global_position.distance_to(player.global_position) < 128:
				show_hint = show_hint or not life.save_game.justice.current(id, "player", life.save_game.life.minute).is_empty()
	_hint.visible = show_hint

func _on_event(event: WorldEvent) -> void:
	if event.kind == &"actor_surrendered" and event.subject is BasePlayer:
		_accept_surrender(event.subject)
		return
	if not event.kind in [&"actor_hurt", &"actor_died", &"actor_brandished_weapon"]:
		return
	var suspect: BaseActor = event.subject if event.kind == &"actor_brandished_weapon" else event.instigator
	if not is_instance_valid(suspect) or suspect.health <= 0:
		return
	for guard: BaseNpc in get_tree().get_nodes_in_group(&"town_guards"):
		if guard.health <= 0 or guard == suspect:
			continue
		var id: String = String(guard.get_npc_profile().npc_id)
		if event.kind == &"actor_brandished_weapon":
			if not suspect is BasePlayer or not NpcPerception.can_see(guard, suspect):
				continue
			var defending: bool = false
			for enemy: BaseNpc in get_tree().get_nodes_in_group(&"enemies"):
				if enemy.health > 0 and enemy.world_space == suspect.world_space \
					and enemy.global_position.distance_to(suspect.global_position) < 48 \
					and NpcPerception.can_see(guard, enemy):
					defending = true
			if defending:
				continue
			var nearby_civilian: bool = false
			for resident: BaseNpc in get_tree().get_nodes_in_group(&"town_residents"):
				if resident.health > 0 and resident.world_space == suspect.world_space \
					and resident.global_position.distance_to(suspect.global_position) <= 24 \
					and NpcPerception.can_see(guard, resident):
					nearby_civilian = true
			if nearby_civilian:
				_notice(guard, id, suspect, "brandishing")
			continue
		var observation: Dictionary = NpcPerception.observe(guard, event.subject, suspect, event.kind == &"actor_died")
		if observation.is_empty():
			continue
		if observation.sense == "hearing":
			# Sound supplies a location to investigate, never an identified criminal.
			_investigations[id] = {"space": event.subject.world_space,
				"point": event.subject.global_position, "until": life.save_game.life.minute + 12}
			continue
		if not NpcPerception.can_see(guard, suspect):
			continue
		if suspect is BasePlayer and event.subject.is_in_group(&"town_residents"):
			_notice(guard, id, suspect, "killing" if event.kind == &"actor_died" else "assault")
		elif suspect.is_in_group(&"enemies") and (event.subject.is_in_group(&"town_residents") or event.subject is BasePlayer):
			guard.set_enforcement_target(suspect)
			guard.show_spoken_reaction("Get behind me!")

func _notice(guard: BaseNpc, id: String, suspect: BaseActor, kind: String) -> void:
	var before: Dictionary = life.save_game.justice.current(id, "player", life.save_game.life.minute)
	# Do not keep extending a warning just because a held attack loops its animation.
	if kind == "brandishing" and not before.is_empty():
		return
	var report: Dictionary = life.save_game.justice.notice(id, "player", kind, life.save_game.life.minute)
	life.encounters.interrupt(id)
	guard.life_context.enforcement = report
	if report.status == "combat":
		guard.set_enforcement_target(suspect)
	else:
		_investigations[id] = {"space": suspect.world_space, "point": suspect.global_position,
			"until": report.until}
	if before.get("status") != report.status:
		var lines: Array[String] = ["Enough. Put it away. You can surrender.", "Easy now. Stand down and no one else gets hurt.", "Stop there. Put the weapon down."]
		if report.status == "combat":
			lines = ["Stop fighting! Surrender and I'll stop too.", "Enough. Stand down!", "Leave them alone! You can still surrender."]
		guard.show_spoken_reaction(lines[abs(hash(id)) % lines.size()])
	life.save_game.life.interrupt(id)
	life.save_game.save_file()

func _accept_surrender(player: BasePlayer) -> void:
	for guard: BaseNpc in get_tree().get_nodes_in_group(&"town_guards"):
		if guard.health <= 0 or guard.world_space != player.world_space \
			or guard.global_position.distance_to(player.global_position) > guard.npc_data.hearing_radius:
			continue
		var id: String = String(guard.get_npc_profile().npc_id)
		if life.save_game.justice.surrender(id, "player", life.save_game.life.minute):
			if not guard.is_fighting_monster():
				guard.clear_enforcement_target()
			_investigations.erase(id)
			_end_task(id, "investigate")
			guard.life_revision += 1
			guard.show_spoken_reaction("All right. Keep that weapon down.")
			guard.life_context.enforcement = {"status": "surrendered"}
			life.save_game.life.interrupt(id)
	life.save_game.save_file()

func maintain(npc: BaseNpc, id: String) -> bool:
	if not npc.is_in_group(&"town_guards"):
		return false
	if npc.alert_response.active():
		return true
	for player: BasePlayer in get_tree().get_nodes_in_group(&"players"):
		var report: Dictionary = life.save_game.justice.current(id, "player", life.save_game.life.minute)
		if not report.is_empty() and report.status == "combat" and player.health > 0 \
			and NpcPerception.can_see(npc, player):
			npc.set_enforcement_target(player)
		elif report.is_empty() and npc.has_enemy_target() and not npc.is_fighting_monster():
			npc.clear_enforcement_target()
	if npc.has_enemy_target():
		return true
	if _investigations.has(id):
		var investigation: Dictionary = _investigations[id]
		if investigation.until > life.save_game.life.minute and npc.can_follow_routine():
			if not _owns(id, "investigate"):
				life.encounters.interrupt(id)
				_request(id, "investigate", NpcDirectedTravelTask.create({"owner": OWNER,
					"activity": "investigate", "label": "a disturbance", "space": String(investigation.space),
					"point": [investigation.point.x, investigation.point.y],
					"priority": life.tuning.caution_priority, "hold_on_arrival": true}))
			return true
		_investigations.erase(id)
		_end_task(id, "investigate")
	var person: Dictionary = life.save_game.life.get_person(id)
	var preferred: Dictionary = NpcRoutinePlan.current(person.plan, life.save_game.life.minute)
	if preferred.kind != "patrol":
		_end_task(id, "patrol")
		return false
	if npc.can_follow_routine() and not _owns(id, "patrol"):
		var stop: int = (int(_patrol_stops.get(id, 0 if id == "voss_guard" else 2)) + 1) % 4
		var place: String = "patrol:%d" % stop
		var target: Dictionary = life.destination(id, {"kind": "patrol", "place": place})
		var point: Vector2 = target.point
		var task := NpcDirectedTravelTask.create({"owner": OWNER, "activity": "patrol",
			"label": target.label, "space": String(target.space), "point": [point.x, point.y],
			"priority": life.tuning.routine_priority, "hold_on_arrival": false, "stop": stop})
		# Patrol is the guard's scheduled routine, so it replaces ordinary routine tasks.
		if _request(id, "patrol", task, true):
			_patrol_stops[id] = stop
			life.save_game.life.select_activity(id, {"kind": "patrol", "place": place}, 20,
				{"service": "town_obligation"})
	return true

## After a reload: investigations are not saved, so only a restored patrol stop that is still
## scheduled is kept; every other restored watch task ends.
func reconcile(id: String, brain: NpcBrain) -> void:
	for task: NpcTask in [brain.controller.suspended, brain.controller.current]:
		if task == null or task.kind != &"directed_travel" or task.params.get("owner") != OWNER:
			continue
		var person: Dictionary = life.save_game.life.get_person(id)
		var scheduled: bool = not person.is_empty() \
			and NpcRoutinePlan.current(person.plan, life.save_game.life.minute).kind == "patrol"
		var stop: Variant = task.params.get("stop")
		if task == brain.controller.current and task.params.activity == "patrol" and scheduled \
			and (stop is float or stop is int) and not _tasks.has(id):
			_brain(id)
			_tasks[id] = {"task_id": task.task_id, "kind": "patrol"}
			_patrol_stops[id] = int(stop)
		else:
			brain.end_task(task.task_id, &"unowned")

# True when `kind` is requested and still running or suspended in the guard's brain.
func _owns(id: String, kind: String) -> bool:
	var owned: Dictionary = _tasks.get(id, {})
	if owned.is_empty() or owned.kind != kind:
		return false
	var brain: NpcBrain = _brain(id)
	return brain != null and brain.task_state(owned.task_id) in [
		NpcTask.status_name(NpcTask.Status.RUNNING), NpcTask.status_name(NpcTask.Status.SUSPENDED)]

# Replaces the watch's previous task for this guard; a higher-priority current task refuses
# without spending a decision. `replace_routine` ends ordinary routine tasks first so a finished
# patrol stop does not fall back into them.
func _request(id: String, kind: String, task: NpcDirectedTravelTask, replace_routine: bool = false) -> bool:
	var brain: NpcBrain = _brain(id)
	if brain == null:
		return false
	var current: NpcTask = brain.controller.current
	if current != null and current.priority > task.priority \
		and current.task_id != _tasks.get(id, {}).get("task_id", ""):
		return false
	_end_task(id, "")
	if replace_routine:
		for routine: NpcTask in [brain.controller.suspended, brain.controller.current]:
			if routine != null and routine.kind == &"routine":
				brain.end_task(routine.task_id, &"replanned")
	if not brain.request_task(task):
		return false
	_tasks[id] = {"task_id": task.task_id, "kind": kind}
	return true

# Ends the watch's task for this guard when it is of `kind` (any kind when empty).
func _end_task(id: String, kind: String) -> void:
	var owned: Dictionary = _tasks.get(id, {})
	if owned.is_empty() or (not kind.is_empty() and owned.kind != kind):
		return
	_tasks.erase(id)
	var brain: NpcBrain = _brain(id)
	if brain != null:
		brain.end_task(owned.task_id, &"released")

func _brain(id: String) -> NpcBrain:
	var brain: NpcBrain = life.brain_for(id)
	if brain != null and not _listening.has(id):
		_listening[id] = true
		brain.task_finished.connect(_on_task_finished.bind(id))
	return brain

func _on_task_finished(task_id: String, _status: String, _reason: StringName, id: String) -> void:
	if _tasks.has(id) and _tasks[id].task_id == task_id:
		_tasks.erase(id) # Arrived, displaced or unreachable: the next maintain decides again.
