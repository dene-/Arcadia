class_name TownWatch
extends Node

## Scene adapter: perception -> saved evidence -> the guard's NpcGuardTask -> actor mechanics.
## The watch records what each guard perceives (justice reports, sightings, heard disturbances)
## and serves it to that guard's task, which decides where to go and whom to stop; the brain's
## priorities settle conflicts with other duties.
const OWNER: String = "watch"
const PATROL_STOPS: int = 4
## Minutes a heard disturbance stays worth investigating.
const LEAD_MINUTES: float = 12.0
## Offline guard lines when speech generation fails.
const WEAPON_WARNINGS: Array[String] = ["Enough. Put it away. You can surrender.",
	"Easy now. Stand down and no one else gets hurt.", "Stop there. Put the weapon down."]
const COMBAT_WARNINGS: Array[String] = ["Stop fighting! Surrender and I'll stop too.",
	"Enough. Stand down!", "Leave them alone! You can still surrender."]
const SURRENDER_FALLBACK: String = "All right. Keep that weapon down."
## What the guard saw, by justice report kind, for the generated warning.
const WARNING_EVENTS: Dictionary[String, String] = {
	"brandishing": "The player is holding a weapon near townsfolk.",
	"assault": "The player attacked a resident.",
	"killing": "The player killed a resident."}

var life: TownLife
# npc_id -> {subject: {subject, minute, until, space, x, y}}: unsaved leads the guard heard.
var _leads: Dictionary = {}
# npc_id -> the patrol stop the guard last headed for; a new duty continues after it.
var _stops: Dictionary = {}
var _origins: int = 0
var _hint: Label
var speech := NpcReportSpeech.new()

func _ready() -> void:
	speech.decisions = life.decisions
	get_node("/root/WorldEvents").occurred.connect(_on_event)
	for guard: BaseNpc in get_tree().get_nodes_in_group(&"town_guards"):
		var id: String = String(guard.get_npc_profile().npc_id)
		var brain: NpcBrain = life.brain_for(id)
		if brain != null:
			_provide(brain, guard, id)
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
			_hear(id, event.subject)
			continue
		if not NpcPerception.can_see(guard, suspect):
			continue
		if suspect is BasePlayer and event.subject.is_in_group(&"town_residents"):
			_notice(guard, id, suspect, "killing" if event.kind == &"actor_died" else "assault")
		elif suspect.is_in_group(&"enemies") and (event.subject.is_in_group(&"town_residents") or event.subject is BasePlayer):
			guard.set_enforcement_target(suspect)
			speech.say(guard, "warn", "A hostile creature is attacking near me.", "sight", "Get behind me!",
				null, event.subject is BasePlayer)

func _notice(guard: BaseNpc, id: String, suspect: BaseActor, kind: String) -> void:
	var minute: float = life.save_game.life.minute
	var before: Dictionary = life.save_game.justice.current(id, "player", minute)
	# Do not keep extending a warning just because a held attack loops its animation.
	if kind == "brandishing" and not before.is_empty():
		return
	var report: Dictionary = life.save_game.justice.notice(id, "player", kind, minute)
	# The guard saw the suspect here; a pursuit heads for this, never for a live position.
	_origins += 1
	var origin: String = "watch:%s:%d:%d" % [id, int(minute * 10.0), _origins]
	life.save_game.minds.get_mind(id).knowledge.record("player", "location",
		{"space": String(suspect.world_space), "x": suspect.global_position.x, "y": suspect.global_position.y},
		NpcKnowledge.Status.OBSERVED, NpcKnowledge.SELF_SOURCE, origin, origin, minute, 1.0)
	life.encounters.interrupt(id)
	guard.life_context.enforcement = life.save_game.justice.known_to(id)
	if before.get("status") != report.status:
		var lines: Array[String] = COMBAT_WARNINGS if report.status == "combat" else WEAPON_WARNINGS
		speech.say(guard, "warn", WARNING_EVENTS.get(kind, "The player is threatening townsfolk nearby."), "sight",
			lines[abs(hash(id)) % lines.size()], null, true)
	life.save_game.life.interrupt(id)
	life.saves.request(&"watch_notice")
	_prompt(id)

func _hear(id: String, source: BaseActor) -> void:
	var minute: float = life.save_game.life.minute
	var leads: Dictionary = _leads.get_or_add(id, {})
	leads["disturbance"] = {"subject": "disturbance", "minute": minute, "until": minute + LEAD_MINUTES,
		"space": String(source.world_space), "x": source.global_position.x, "y": source.global_position.y}
	life.encounters.interrupt(id)
	_prompt(id)

func _accept_surrender(player: BasePlayer) -> void:
	for guard: BaseNpc in get_tree().get_nodes_in_group(&"town_guards"):
		if guard.health <= 0 or guard.world_space != player.world_space \
			or guard.global_position.distance_to(player.global_position) > guard.npc_data.hearing_radius:
			continue
		var id: String = String(guard.get_npc_profile().npc_id)
		if life.save_game.justice.surrender(id, "player", life.save_game.life.minute):
			guard.life_revision += 1
			guard.life_context.enforcement = life.save_game.justice.known_to(id)
			speech.say(guard, "acknowledge", "The player surrendered to me.", "sight",
				SURRENDER_FALLBACK, null, true)
			life.save_game.life.interrupt(id)
			_prompt(id)
	life.saves.request(&"surrender")

## Requests the watch task for an on-duty guard that has none; the brain's priorities decide
## whether it runs.
func maintain(npc: BaseNpc, id: String) -> void:
	if not npc.is_in_group(&"town_guards") or npc.alert_response.active():
		return
	var brain: NpcBrain = life.brain_for(id)
	if brain != null and _on_duty(id) and _guard_task(brain) == null and npc.can_follow_routine():
		_request(id, brain, false)

## After a reload: a restored guard task continues from its saved stop.
func reconcile(id: String, brain: NpcBrain) -> void:
	for task: NpcTask in [brain.controller.suspended, brain.controller.current]:
		if task != null and task.kind == &"guard":
			_stops[id] = int(task.progress.get("stop", task.params["stop"]))

# Something new to act on: the current guard task re-decides at once, otherwise a new one starts
# at caution priority (a busier duty refuses it and the suspended watch re-decides on resume).
func _prompt(id: String) -> void:
	var brain: NpcBrain = life.brain_for(id)
	if brain == null:
		return
	var current: NpcTask = brain.controller.current
	if current != null and current.kind == &"guard":
		brain.advance(life.save_game.life.minute, 0.0)
	else:
		_request(id, brain, true)

# Patrol is the guard's scheduled routine, so it replaces ordinary routine tasks; an incident
# only suspends them.
func _request(id: String, brain: NpcBrain, incident: bool) -> bool:
	var task := NpcGuardTask.create(int(_stops.get(id, _origin(id))), "the watch", life.tuning, incident)
	var current: NpcTask = brain.controller.current
	if current != null and current.kind != &"routine" and current.priority > task.priority:
		return false
	if not incident:
		for routine: NpcTask in [brain.controller.suspended, brain.controller.current]:
			if routine != null and routine.kind == &"routine":
				brain.end_task(routine.task_id, &"replanned")
	return brain.request_task(task)

func _guard_task(brain: NpcBrain) -> NpcTask:
	for task: NpcTask in [brain.controller.current, brain.controller.suspended]:
		if task != null and task.kind == &"guard":
			return task
	return null

func _origin(id: String) -> int:
	return int(TownResidentSchedule.guard_shift(life.save_game.population, id,
		life.save_game.dead_npcs)["origin"])

func _on_duty(id: String) -> bool:
	var person: Dictionary = life.save_game.life.get_person(id)
	return not person.is_empty() \
		and NpcRoutinePlan.current(person.plan, life.save_game.life.minute).kind == "patrol"

# --- Services for the guard's task (NpcGuardTask documents the contract) ---

func _provide(brain: NpcBrain, guard: BaseNpc, id: String) -> void:
	brain.provide_service(&"guard_on_duty", _on_duty.bind(id))
	brain.provide_service(&"guard_patrol", _patrol_stop.bind(id))
	brain.provide_service(&"guard_reports", _reports.bind(id))
	brain.provide_service(&"guard_leads", _active_leads.bind(id))
	brain.provide_service(&"guard_sees", _sees.bind(guard))
	brain.provide_service(&"guard_engage", _engage.bind(guard))
	brain.provide_service(&"guard_disengage", _disengage.bind(guard))

func _reports(id: String) -> Array[Dictionary]:
	return life.save_game.justice.known_to(id)

func _patrol_stop(stop: int, id: String) -> Dictionary:
	var index: int = posmod(stop, PATROL_STOPS)
	var selected: Dictionary = {"kind": "patrol", "place": "patrol:%d" % index}
	var target: Dictionary = life.destination(id, selected)
	var point: Vector2 = target.point
	_stops[id] = index
	life.save_game.life.select_activity(id, selected, 20)
	return {"stop": index, "space": String(target.space), "x": point.x, "y": point.y,
		"label": target.label}

func _active_leads(id: String) -> Array:
	var minute: float = life.save_game.life.minute
	var leads: Dictionary = _leads.get(id, {})
	for subject: String in leads.keys():
		if float(leads[subject]["until"]) <= minute:
			leads.erase(subject)
	return leads.values().map(func(lead: Dictionary) -> Dictionary: return lead.duplicate())

func _sees(subject: String, guard: BaseNpc) -> bool:
	var actor: BaseActor = _actor(subject)
	return actor != null and actor.health > 0 and NpcPerception.can_see(guard, actor)

func _engage(subject: String, guard: BaseNpc) -> bool:
	var actor: BaseActor = _actor(subject)
	if actor == null:
		return false
	guard.set_enforcement_target(actor)
	return guard.has_enemy_target()

# A guard defending against a monster keeps that fight.
func _disengage(guard: BaseNpc) -> void:
	if not guard.is_fighting_monster():
		guard.clear_enforcement_target()

func _actor(subject: String) -> BaseActor:
	if subject != "player":
		return null
	for player: BasePlayer in get_tree().get_nodes_in_group(&"players"):
		return player
	return null
