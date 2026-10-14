class_name TownLife
extends Node

## Scene-owned application coordinator. Planning, movement, social sessions and saves have separate owners.
## Each resident's NpcBrain is the only locomotion and sleep authority; planners here, the watch and
## funerals only request tasks from it and let its priorities settle conflicts.

## A repeat sighting of the same target is recorded only after it moved, changed space or this long.
const SIGHTING_MOVE_PIXELS: float = 16.0
const SIGHTING_REFRESH_MINUTES: float = 30.0
## Commitment-driven activities: a search for a relative and a visit to a known grave.
const CHECK_RELATIVE: String = "check_relative"
const VISIT_GRAVE: String = "visit_grave"
## Ad-hoc places: where a relative was last seen, and the grave of a deceased resident.
const SEEN_PREFIX: String = "seen:"
const GRAVE_PREFIX: String = "grave:"
## A visitor stands this far below the grave marker.
const GRAVE_STAND_OFFSET := Vector2(0, 12)

@export_range(0.0, 10.0, 0.1) var minutes_per_second: float = 1.5
@export_range(1, 12, 1) var max_decision_workers: int = 4
var save_game: NpcWorldSave
var decisions: NpcDecisionService
var navigation := TownNavigation.new()
var encounters: TownEncounters
var buildings: TownBuildings
var watch: TownWatch
var funerals: TownFunerals
## One tuning resource shared by every resident's brain.
var tuning := NpcBehaviorTuning.new()
var _actors: Dictionary[String, BaseNpc] = {}
var _brains: Dictionary[String, NpcBrain] = {}
# id -> "origin|response" of the last safety task requested, so one concern asks only once.
var _safety_keys: Dictionary = {}
var _places: Dictionary[String, Dictionary] = {}
var _public_people: Array[Dictionary] = []
var _pending: Dictionary = {}
var _revisions: Dictionary = {}
var _tick: float = 0.0
var _save_elapsed: float = 0.0
# Game hour whose memory and receipt upkeep already ran.
var _maintained_hour: int = -1
# (observer|target) -> {space, position, minute}: last sighting recorded, to throttle re-recording.
var _sighted: Dictionary = {}
# observer|deceased -> true once the observer has seen that grave this session.
var _graves_seen: Dictionary = {}
var _initialized: bool = false
# id -> sociability trait, read once: needs advance every frame.
var _sociability: Dictionary[String, float] = {}
var _light: CanvasModulate
var _clock: Label

func _ready() -> void:
	set_process(false)
	var cognition: Node = get_node("/root/NpcCognition")
	save_game = cognition.save_game
	save_game.population.ensure_population(save_game.region_seed)
	save_game.economy.ensure_households(save_game.population, save_game.life.minute)
	decisions = cognition.decisions
	decisions.request_settled.connect(_on_request_settled)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var navigation_world: WorldNavigation = get_parent().get_node("WorldNavigation")
	if not navigation_world.outdoors.ready:
		await navigation_world.initialized
	navigation = navigation_world.outdoors
	var bodies: Array[RID] = []
	for actor: Node in get_tree().get_nodes_in_group("interactables") + get_tree().get_nodes_in_group("players"):
		if actor is PhysicsBody2D and not actor.get_rid() in bodies:
			bodies.append(actor.get_rid())
	buildings = get_parent().get_node("Buildings")
	buildings.prepare_navigation(navigation, bodies)
	for player: Node2D in get_tree().get_nodes_in_group(&"players"):
		navigation.register("player:%d" % player.get_instance_id(), player)
	_build_places()
	var ids: Array[String] = []
	for npc: BaseNpc in get_tree().get_nodes_in_group(&"town_residents"):
		if npc.health <= 0 or npc.is_queued_for_deletion():
			continue
		var id: String = String(npc.get_npc_profile().npc_id)
		_actors[id] = npc
		navigation.register(id, npc)
		_revisions[id] = npc.life_revision
		ids.append(id)
	ids.sort()
	encounters = TownEncounters.new()
	encounters.state = save_game.life
	encounters.store = save_game.memory
	encounters.decisions = decisions
	encounters.seed_value = save_game.get_npc_seed()
	encounters.save_callback = _save
	encounters.brains = brain_for
	encounters.tuning = tuning
	add_child(encounters)
	for id: String in ids:
		var npc: BaseNpc = _actors[id]
		save_game.life.ensure_person(id, save_game.get_npc_seed(), ids, ["market", "garden", "square"],
			save_game.population, save_game.dead_npcs)
		npc.daily_routine = NpcDailyRoutine.new()
		npc.daily_routine.navigation = navigation
		npc.daily_routine.npc_id = id
		buildings.restore(npc, id, save_game.life.get_person(id))
		_add_brain(npc, id)
		_revisions[id] = npc.life_revision
		_update_context(npc, id)
	_bootstrap_knowledge(ids)
	watch = TownWatch.new()
	watch.life = self
	add_child(watch)
	funerals = TownFunerals.new()
	funerals.name = "Funerals"
	funerals.life = self
	add_child(funerals)
	for id: String in ids:
		_restore_brain(_actors[id], id)
	_light = CanvasModulate.new()
	add_child(_light)
	var overlay := CanvasLayer.new()
	add_child(overlay)
	_clock = Label.new()
	_clock.theme = preload("res://assets/art/ui/theme.tres")
	_clock.add_theme_color_override("font_color", Color(0.96, 0.91, 0.78))
	_clock.add_theme_color_override("font_shadow_color", Color(0.12, 0.1, 0.08, 0.8))
	_clock.add_theme_constant_override("shadow_offset_y", 1)
	_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_clock)
	_clock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_clock.offset_left = -105
	_clock.offset_right = -5
	_clock.offset_top = 5
	_clock.offset_bottom = 15
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	buildings.player_space_changed.connect(_update_environment)
	_update_environment()
	_initialized = true
	_save()
	set_process(true)

func _process(delta: float) -> void:
	var elapsed_minutes: float = delta * minutes_per_second
	save_game.life.advance(elapsed_minutes)
	funerals.advance(delta)
	save_game.economy.settle(save_game.life.minute, save_game.population, save_game.dead_npcs)
	_tick += delta
	_save_elapsed += delta
	for id: String in _actors.keys():
		if not is_instance_valid(_actors[id]):
			navigation.release(id)
			_actors.erase(id)
			_brains.erase(id)
			continue
		var npc: BaseNpc = _actors[id]
		if npc.health <= 0:
			_brains[id].interrupt(NpcTask.Interrupt.DEATH)
			navigation.release(id)
			buildings.release(npc, id)
			_actors.erase(id)
			_brains.erase(id)
			continue
		if _revisions[id] != npc.life_revision:
			_revisions[id] = npc.life_revision
			save_game.life.interrupt(id)
		npc.daily_routine.update(npc.global_position, delta, not npc.can_follow_routine())
		if npc.earns_work_credit():
			save_game.economy.record_work(id, elapsed_minutes)
		_advance_needs(npc, id, elapsed_minutes)
		buildings.advance(npc, id)
		_brains[id].advance(save_game.life.minute, elapsed_minutes)
		# Door transfers and scheduled waking belong to the running task, not an interruption.
		_revisions[id] = npc.life_revision
	if _tick < 1.0:
		return
	_tick = 0.0
	var ids: Array[String] = _actors.keys()
	ids.sort()
	_record_sightings(ids)
	for id: String in ids:
		var npc: BaseNpc = _actors[id]
		save_game.life.ensure_person(id, save_game.get_npc_seed(), ids, ["market", "garden", "square"],
			save_game.population, save_game.dead_npcs)
		# Each system only requests tasks; the brain's priorities settle who moves the resident.
		var engaged: bool = watch.maintain(npc, id)
		engaged = funerals.maintain(npc, id) or engaged
		engaged = _maintain_safety(npc, id) or engaged
		_maintain_commitments(id)
		_update_context(npc, id)
		if not engaged and _routine_due(id) and npc.can_follow_routine() and not encounters.is_busy(id) \
			and not _pending.has(id) and _pending.size() < max_decision_workers:
			_plan_routine(npc, id)
	# Rotate ordering deterministically so low-ID residents do not always initiate.
	if not ids.is_empty():
		var offset: int = int(save_game.life.minute) % ids.size()
		for index: int in range(ids.size()):
			var first: BaseNpc = _actors[ids[(index + offset) % ids.size()]]
			if funerals.is_assigned(ids[(index + offset) % ids.size()]) or first.alert_response.active():
				continue
			for second_id: String in ids:
				var second: BaseNpc = _actors[second_id]
				if funerals.is_assigned(second_id) or second.alert_response.active():
					continue
				if first != second and first.can_speak_reaction() and second.can_speak_reaction():
					encounters.consider(first, second)
	_update_environment()
	var hour: int = floori(save_game.life.minute / 60.0)
	if hour != _maintained_hour:
		_maintained_hour = hour
		save_game.memory.maintain(save_game.life.rumors.live_origins(save_game.life.minute),
			save_game.life.minute)
	if _save_elapsed >= 15.0:
		_save_elapsed = 0.0
		_save()

func _update_environment() -> void:
	_clock.text = save_game.life.clock_text()
	var hour: float = fmod(save_game.life.minute / 60.0, 24.0)
	var daylight: float = smoothstep(5.0, 8.0, hour) * (1.0 - smoothstep(18.0, 21.0, hour))
	_light.color = Color(0.48, 0.53, 0.7).lerp(Color.WHITE, daylight)
	for player: BasePlayer in get_tree().get_nodes_in_group(&"players"):
		if player.world_space != &"outdoors":
			_light.color = Color(1, 0.96, 0.88)

func _exit_tree() -> void:
	decisions.request_settled.disconnect(_on_request_settled)
	for request_id: String in _pending.values():
		decisions.cancel(request_id)
	if _initialized:
		_save()
	for id: String in _actors:
		if is_instance_valid(_actors[id]):
			_actors[id].daily_routine = null

func _bootstrap_knowledge(ids: Array[String]) -> void:
	var guards: Array[String] = []
	for id: String in save_game.population.people:
		if save_game.population.people[id].get("job") == "guard":
			guards.append(id)
	guards.sort()
	for id: String in ids:
		save_game.minds.get_mind(id).knowledge.bootstrap_public(id, save_game.population.people, _places, guards)

# Residents learn where others are only by seeing them; every record is a first-hand sighting.
func _record_sightings(ids: Array[String]) -> void:
	var minute: float = save_game.life.minute
	var targets: Array[BaseActor] = []
	var target_ids: Array[String] = []
	for id: String in ids:
		targets.append(_actors[id])
		target_ids.append(id)
	for player: Node in get_tree().get_nodes_in_group(&"players"):
		if player is BaseActor and (player as BaseActor).health > 0:
			targets.append(player)
			target_ids.append("player")
	var graves: Dictionary[String, Vector2] = funerals.cemetery.graves()
	for id: String in ids:
		var observer: BaseNpc = _actors[id]
		if observer.health <= 0 or observer.is_sleeping():
			continue
		var knowledge: NpcKnowledge = save_game.minds.get_mind(id).knowledge
		var radius: float = observer.npc_data.vision_radius
		for index: int in targets.size():
			var target: BaseActor = targets[index]
			var target_id: String = target_ids[index]
			if target == observer or not is_instance_valid(target) \
					or observer.world_space != target.world_space \
					or observer.global_position.distance_to(target.global_position) > radius \
					or not _sighting_due(id, target_id, target, minute) \
					or not NpcPerception.can_see(observer, target):
				continue
			if knowledge.record_sighting(target_id, String(target.world_space), target.global_position,
					minute, "sighting:%s:%s:%d" % [id, target_id, int(minute * 10.0)]):
				_sighted["%s|%s" % [id, target_id]] = {"space": target.world_space,
					"position": target.global_position, "minute": minute}
		if observer.world_space != &"outdoors":
			continue
		for deceased: String in graves:
			var key: String = "%s|%s" % [id, deceased]
			if not _graves_seen.has(key) and NpcPerception.can_see_point(observer, &"outdoors", graves[deceased]):
				_graves_seen[key] = true
				get_node("/root/NpcCognition").see_grave(id, deceased, graves[deceased])

func _sighting_due(observer_id: String, target_id: String, target: BaseActor, minute: float) -> bool:
	var last: Variant = _sighted.get("%s|%s" % [observer_id, target_id])
	if not last is Dictionary:
		return true
	return last["space"] != target.world_space \
		or minute - float(last["minute"]) >= SIGHTING_REFRESH_MINUTES \
		or (last["position"] as Vector2).distance_to(target.global_position) > SIGHTING_MOVE_PIXELS

func _build_places() -> void:
	_places = {"square": {"label": "Rekala square", "position": Vector2(16, 48)},
		"market": {"label": "the market stalls", "position": Vector2(-48, 88)},
		"garden": {"label": "the farm garden", "position": Vector2(320, 104)}}
	_places["school"] = {"label": "the school lessons by the farm", "position": Vector2(128, 256)}
	_places["playground"] = {"label": "the children's play green", "position": Vector2(-104, 232)}
	for index: int in range(4):
		_places["patrol:%d" % index] = {"label": "village watch route", "position":
			[Vector2(-320, 32), Vector2(8, -232), Vector2(392, 32), Vector2(8, 304)][index]}
	for id: String in save_game.population.people:
		var person: Dictionary = save_game.population.people[id]
		var space: String = "home:" + person.household
		var room: NpcInterior = buildings.rooms[StringName(space)]
		_places["home:" + id] = {"label": room.resident_name + " family home", "position": room.bed_for(id), "space": space}
		_places["work:" + id] = {"label": person.name + "'s workplace", "position": room.work_spot, "space": space}
		var outdoor_jobs: Dictionary = {"farmer": Vector2(352, 72), "farmhand": Vector2(376, 120),
			"herb gatherer": Vector2(-304, -200), "fisher": Vector2(432, 208),
			"miller": Vector2(416, -16), "delivery worker": Vector2(-48, 88)}
		if outdoor_jobs.has(person.job):
			_places["work:" + id] = {"label": person.job + " work", "position": outdoor_jobs[person.job]}
		elif person.job == "teacher" or person.age < 16:
			_places["work:" + id] = _places.school
		_public_people.append({"id": id, "name": person.name, "job": person.job,
			"home": room.resident_name + " household in Rekala"})

func _choose_activity(npc: BaseNpc, id: String) -> void:
	var revision: int = npc.life_revision
	var person: Dictionary = save_game.life.get_person(id)
	var preferred: Dictionary = NpcRoutinePlan.current(person.plan, save_game.life.minute)
	var options: Array[Dictionary] = _options(id, preferred)
	save_game.memory.ensure_npc(npc.get_npc_profile())
	var memory: Dictionary = save_game.memory.snapshot(id)
	var raw: Dictionary = npc.get_cognitive_context(NpcCognitiveContext.DECISION, ["player"])
	var current: Dictionary = NpcCognitiveContext.build(memory, raw)
	current.participants = [id]
	current.memories = NpcMemoryRetriever.new().retrieve(memory.memories,
		str(current.get("activity", "")) + " " + preferred.kind + " "
		+ str(current.get("safety_response", {}).get("concern", "")),
		current, npc.get_npc_profile().get_cognition(), save_game.memory.world_minute,
		NpcMemoryRetriever.links_for(raw))
	var mind: NpcMindState = save_game.minds.get_mind(id)
	var ticket := NpcDecisionTicket.create(id, NpcDecisionTicket.SELECT_GOAL)
	ticket.task_id = "routine:" + id
	ticket.task_generation = revision
	ticket.created_minute = int(save_game.life.minute)
	ticket.read_versions = {"life": revision, "task": int(mind.versions().task),
		"condition": mind.condition_version(save_game.life.minute),
		"commitments": mind.commitments.version}
	var candidates: Array[Dictionary] = []
	for option: Dictionary in options:
		ticket.candidate_ids.append(option.id)
		candidates.append({"id": option.id, "description": option.description})
	_pending[id] = ticket.request_id
	var result: NpcDecisionResult = await decisions.evaluate(ticket, {"evidence": [],
		"state": {"profile": npc.get_backend_profile(), "current": current},
		"candidates": candidates})
	_pending.erase(id)
	if result.outcome in [NpcDecisionResult.Outcome.STALE, NpcDecisionResult.Outcome.CANCELLED]:
		return # A newer request for this resident, or shutdown, owns the decision.
	if not is_inside_tree() or not is_instance_valid(npc) or not npc.can_follow_routine() \
		or npc.life_revision != revision or encounters.is_busy(id) or funerals.is_assigned(id) \
		or not _routine_due(id):
		return
	if save_game.life.get_person(id).safety != person.safety:
		return # A routine decision cannot supersede a new or newly assessed concern.
	if NpcRoutinePlan.current(save_game.life.get_person(id).plan, save_game.life.minute) != preferred:
		save_game.life.interrupt(id)
		return # A delayed nighttime decision cannot overwrite the morning routine.
	if mind.condition_version(save_game.life.minute) != ticket.read_versions.condition \
			or mind.commitments.version != ticket.read_versions.commitments:
		save_game.life.interrupt(id)
		return # The resident's needs, feelings or commitments moved on while it was judged.
	var frame: NpcDecisionPolicy.GoalFrame = goal_frame(options, mind,
		save_game.life.personality_for(id, save_game.get_npc_seed()).traits,
		save_game.life.get_person(id), save_game.life.minute, save_game.get_npc_seed(), tuning)
	var choice: NpcDecisionPolicy.GoalChoice = NpcDecisionPolicy.goal_choice(result, tuning, frame)
	# Without an eligible candidate (or a provider) the resident keeps today's plan entry.
	var selected: Dictionary = options[0]
	var duration: float = tuning.plan_kept_minutes
	var service: String = "schedule_fallback" if not result.is_success() else "plan_kept"
	for option: Dictionary in options:
		if option.id == choice.candidate_id:
			selected = option
			duration = choice.duration_minutes
			# "priority": the resident's own needs or commitments chose what the judgment did not.
			service = "jev" if choice.endorsed else "priority"
			break
	_trace(id, NpcDecisionTrace.GOAL, {"reason": service,
		"outcome": NpcDecisionTrace.code(NpcDecisionResult.Outcome.keys()[result.outcome]),
		"request_id": ticket.request_id, "selected": selected.id, "duration": duration,
		"scores": choice.scores, "commitment_id": String(selected.get("commitment_id", ""))})
	save_game.life.select_activity(id, selected, duration)
	_request_routine(npc, id, selected)
	_update_context(npc, id)
	_save()

## The resident's own reasons for each option, for `NpcDecisionPolicy.goal_choice`. `options`
## carry {id, kind, place} and, for a commitment, {commitment_id, subject}; `person` is the saved
## life record (activity, place, since). Draws the tie-break seed from the mind's decision sequence.
static func goal_frame(options: Array[Dictionary], mind: NpcMindState, traits: Dictionary,
		person: Dictionary, minute: float, seed_value: int,
		source: NpcBehaviorTuning) -> NpcDecisionPolicy.GoalFrame:
	var frame := NpcDecisionPolicy.GoalFrame.new()
	var fear: float = mind.emotion("fear", minute)
	var causes: Array[Dictionary] = mind.emotion_causes(minute)
	frame.urgent = fear >= source.urgent_fear
	for option: Dictionary in options:
		var kind: String = option.kind
		var parts: Dictionary = {"need": 0.0, "obligation": 0.0, "concern": 0.0,
			"commitment": 0.0, "personality": 0.0}
		var need: String = {"meal": "hunger", "rest": "fatigue", "socialize": "social",
			"visit": "social"}.get(kind, "")
		if not need.is_empty():
			parts.need = float(mind.needs.get(need, 0.0))
		if kind in ["work", "patrol", "school"]:
			parts.obligation = 1.0 if option.id == "PLAN" else 0.5
		if option.has("commitment_id"):
			var record: Dictionary = mind.commitments.get_commitment(option.commitment_id)
			parts.commitment = float(record.get("priority", 0.0))
			for cause: Dictionary in causes:
				if cause.emotion in (["fear", "grief"] if kind == CHECK_RELATIVE else ["grief"]) \
						and (cause.subject == option.subject or kind == CHECK_RELATIVE):
					parts.concern = maxf(parts.concern, float(cause.intensity))
		elif kind == "rest":
			parts.concern = fear # Home is the refuge a frightened resident knows.
		var trait_name: String = {"socialize": "sociability", "visit": "sociability",
			"walk": "curiosity", "rest": "sociability"}.get(kind, "")
		if not trait_name.is_empty():
			var signed: float = (float(traits.get(trait_name, 0.5)) - 0.5) * 2.0
			parts.personality = -signed if kind == "rest" else signed
		frame.components[option.id] = parts
		if frame.incumbent.is_empty() and kind == person.get("activity") \
				and option.place == person.get("place"):
			frame.incumbent = option.id
	# Older saves do not know when the current goal began: no inertia protects it.
	if not frame.incumbent.is_empty() and person.has("since"):
		frame.incumbent_minutes = minute - float(person.since)
	frame.tie_seed = hash("%d:%s:goal:%d" % [seed_value, mind.npc_id, mind.next_decision()])
	return frame

# A new ordinary routine is wanted when the brain is idle or its routine ran out (or was
# invalidated through `save_game.life.interrupt`). Duties and safety tasks are never replanned.
func _routine_due(id: String) -> bool:
	var controller: NpcTaskController = _brains[id].controller
	if controller.current == null:
		return controller.suspended == null
	return controller.current.kind == &"routine" \
		and float(save_game.life.get_person(id).until) <= save_game.life.minute

func _plan_routine(npc: BaseNpc, id: String) -> void:
	var person: Dictionary = save_game.life.get_person(id)
	var preferred: Dictionary = NpcRoutinePlan.current(person.plan, save_game.life.minute)
	if person.activity == "rest" and preferred.kind != "rest":
		# Waking is a schedule obligation, independent of model latency or repeated REST choices.
		save_game.life.select_activity(id, preferred, 20)
		_trace(id, NpcDecisionTrace.GOAL, {"reason": "scheduled_wakeup", "selected": "PLAN"})
		_request_routine(npc, id, preferred)
		return
	_choose_activity(npc, id)

# Replaces the resident's ordinary routine; the saved person record projects the new task.
func _request_routine(npc: BaseNpc, id: String, selected: Dictionary) -> bool:
	var brain: NpcBrain = _brains[id]
	var target: Dictionary = destination(id, selected)
	var current: NpcTask = brain.controller.current
	if current != null and current.kind == &"routine":
		brain.end_task(current.task_id, &"replanned")
	var point: Vector2 = target.point
	var requested: bool = brain.request_task(NpcRoutineTask.create({"activity": selected.kind,
		"place": selected.place, "label": target.label, "space": String(target.space),
		"point": [point.x, point.y], "until_minute": float(save_game.life.get_person(id).until)}, tuning))
	_revisions[id] = npc.life_revision # A scheduled wakeup is part of this plan, not an interruption.
	return requested

# Safety intent becomes one safety task per concern; the brain's priorities displace routines,
# sessions and adapter duties. Returns true while the concern should keep routine planning away.
func _maintain_safety(npc: BaseNpc, id: String) -> bool:
	if npc.is_in_group(&"town_guards"):
		return false
	var person: Dictionary = save_game.life.get_person(id)
	var minute: float = save_game.life.minute
	if not NpcSafetyState.active(person.safety, minute):
		return false
	var concern: Dictionary = person.safety
	var origin: String = String(concern.get("origin_id", ""))
	if concern.response == "CAUTION" and minute - float(concern.observed_at) < tuning.caution_minutes:
		# Sleepers are covered by the real-second alert reflex; caution is for the awake.
		if not npc.is_sleeping() and _safety_requested(id, origin, "CAUTION"):
			save_game.life.select_activity(id, {"kind": "assess_safety", "place": person.place},
				tuning.caution_minutes)
			_trace(id, NpcDecisionTrace.GOAL, {"reason": "listening_after_disturbance",
				"selected": "assess_safety", "incident_id": origin})
			_brains[id].request_task(NpcSafetyTask.create({"response": "CAUTION", "origin_id": origin,
				"until_minute": minf(float(concern.until), float(concern.observed_at) + tuning.caution_minutes),
				"label": "listening after a disturbance", "refuge_space": "", "refuge_point": []}, tuning))
		return true
	if not NpcSafetyState.sheltering(concern, minute):
		return false
	if not _safety_requested(id, origin, "SHELTER"):
		return true
	# Do not retreat into the room where the threat was perceived. Outdoors, home is
	# a known refuge; a threat in one's own home calls for leaving for the public market.
	var refuge: String = "home:" + id if concern.space != "home:" + save_game.population.household_for(id) else "market"
	if not _places.has(refuge):
		return false
	var selected: Dictionary = {"kind": "shelter", "place": refuge}
	var target: Dictionary = destination(id, selected)
	var point: Vector2 = target.point
	save_game.life.select_activity(id, selected, float(concern.until) - minute)
	_trace(id, NpcDecisionTrace.GOAL, {"reason": "safety_response", "selected": "shelter",
		"incident_id": origin})
	_brains[id].request_task(NpcSafetyTask.create({"response": "SHELTER", "origin_id": origin,
		"until_minute": float(concern.until), "label": target.label,
		"refuge_space": String(target.space), "refuge_point": [point.x, point.y]}, tuning))
	_save()
	return true

# True (and remembered) when this concern has not asked for this response yet.
func _safety_requested(id: String, origin: String, response: String) -> bool:
	var key: String = origin + "|" + response
	var current: NpcTask = _brains[id].controller.current
	if _safety_keys.get(id) == key or (current != null and current.kind == &"safety"
			and current.params.get("origin_id") == origin and current.params.get("response") == response):
		_safety_keys[id] = key
		return false
	_safety_keys[id] = key
	return true

# Needs drift every frame; fatigue eases only while the resident actually sleeps.
func _advance_needs(npc: BaseNpc, id: String, minutes: float) -> void:
	if not _sociability.has(id):
		_sociability[id] = float(save_game.life.personality_for(id,
			save_game.get_npc_seed()).traits.get("sociability", 0.5))
	save_game.minds.get_mind(id).advance_needs(minutes, npc.is_sleeping(), _sociability[id], tuning)

# Checks on relatives end when the resident sees them (or learns they died); grave visits end on
# arrival. A search place reached without finding the relative leads to the next known place,
# and after the last one the search waits `search_defer_minutes`.
func _maintain_commitments(id: String) -> void:
	var mind: NpcMindState = save_game.minds.get_mind(id)
	var minute: float = save_game.life.minute
	for record: Dictionary in mind.commitments.open_commitments():
		if record.kind != CHECK_RELATIVE:
			continue
		var relative: String = record.other_ids[0]
		var outcome: String = "cancelled" if _known_dead(mind.knowledge, relative) \
			else "completed" if _found(id, relative, float(record.created_minute)) else ""
		if not outcome.is_empty() and mind.commitments.resolve(record.id, outcome, minute):
			save_game.life.end_search(id, record.id)
	var person: Dictionary = save_game.life.get_person(id)
	var commitment_id: String = String(person.get("commitment_id", ""))
	if commitment_id.is_empty() or not person.activity in [CHECK_RELATIVE, VISIT_GRAVE]:
		return
	var record: Dictionary = mind.commitments.get_commitment(commitment_id)
	if record.is_empty() or record.status != "open":
		if String(record.get("kind", "")) == CHECK_RELATIVE and float(person.until) > minute:
			save_game.life.interrupt(id) # Found: the search is over.
		return
	var task: NpcTask = _brains[id].controller.current
	if not task is NpcRoutineTask or task.params.get("activity") != person.activity \
			or (task as NpcRoutineTask).confirmed_engagement() == &"":
		return
	if record.kind == VISIT_GRAVE:
		mind.commitments.resolve(commitment_id, "completed", minute) # Stays until its time is up.
		return
	_search_failed(id)

# The current search place did not show the relative (or could not be reached): move on to the
# next place, or defer the search after the last one. A grave that cannot be reached defers too.
func _search_failed(id: String) -> void:
	var person: Dictionary = save_game.life.get_person(id)
	var commitment_id: String = String(person.get("commitment_id", ""))
	if commitment_id.is_empty() or not person.get("activity") in [CHECK_RELATIVE, VISIT_GRAVE]:
		return
	var record: Dictionary = save_game.minds.get_mind(id).commitments.get_commitment(commitment_id)
	if record.is_empty() or record.status != "open":
		return
	var minute: float = save_game.life.minute
	var step: int = save_game.life.search_for(id, commitment_id).step + 1
	if record.kind == VISIT_GRAVE or step >= _search_places(id, record.other_ids[0]).size():
		save_game.life.set_search(id, commitment_id, 0, minute + tuning.search_defer_minutes)
	else:
		save_game.life.set_search(id, commitment_id, step, 0.0)
	# Clears the commitment from the record, so a stale routine never searches the same place twice.
	save_game.life.select_activity(id, {"kind": person.activity, "place": person.place}, 5.0)
	_trace(id, NpcDecisionTrace.EFFECT, {"reason": "search_failed",
		"commitment_id": commitment_id, "step": step})
	save_game.life.interrupt(id)

static func _known_dead(knowledge: NpcKnowledge, subject: String) -> bool:
	for fact: Dictionary in knowledge.current(subject, "status"):
		if fact.value is String and fact.value == "dead":
			return true
	return false

# The resident saw the relative itself after the reason to check arose (the reason's own sighting
# of a hurt relative does not count), or sees them right now.
func _found(id: String, relative: String, since: float) -> bool:
	for fact: Dictionary in save_game.minds.get_mind(id).knowledge.known_locations(relative):
		if fact.source_id == NpcKnowledge.SELF_SOURCE and float(fact.observed_minute) > since:
			return true
	var observer: BaseNpc = resident(id)
	var target: BaseNpc = resident(relative)
	return observer != null and target != null and not observer.is_sleeping() \
		and observer.world_space == target.world_space \
		and observer.global_position.distance_to(target.global_position) <= observer.npc_data.vision_radius \
		and NpcPerception.can_see(observer, target)

func _options(id: String, preferred: Dictionary) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	_add_option(options, "PLAN", preferred.kind, preferred.place, "Follow today's planned activity.")
	var hour: int = int(save_game.life.minute / 60.0) % 24
	if hour >= 6 and hour < 21:
		_add_commitment_options(options, id)
	if preferred.kind in ["school", "patrol", "meal"]:
		return options
	var resident: Dictionary = save_game.population.people[id]
	if resident.job == "guard" and preferred.kind == "rest":
		return options
	if preferred.kind == "rest" or save_game.life.get_person(id).activity != "rest":
		_add_option(options, "REST", "rest", "home:" + id, "Take a bounded rest break at home.")
	if hour >= 6 and hour < 21:
		var venues: Array[String] = ["square", "market", "garden"]
		var random_venue := NpcRoutinePlan.random_for(save_game.get_npc_seed(),
			"%s:venue:%d" % [id, int(save_game.life.minute / 60)])
		var venue: String = venues[random_venue.randi_range(0, venues.size() - 1)]
		_add_option(options, "SOCIAL", "socialize", venue, "Spend some free time here; neighbors may pass by.")
		_add_option(options, "MEAL", "meal", "market", "Take a meal break near the market stalls.")
		if resident.age >= 16 and not String(resident.job).begins_with("retired") and resident.job != "guard":
			_add_option(options, "WORK", "work", "work:" + id, "Return to professional work and daily obligations.")
		_add_option(options, "WALK", "walk", "garden", "Take a walk near the farm garden.")
		var residents: Array[String] = save_game.minds.get_mind(id).relationships.subjects()
		residents.erase("player")
		residents.sort()
		if not residents.is_empty():
			var random := NpcRoutinePlan.random_for(save_game.get_npc_seed(),
				"%s:visit:%s" % [id, int(save_game.life.minute / 60)])
			var other: String = residents[random.randi_range(0, residents.size() - 1)]
			if _actors.has(other):
				_add_option(options, "VISIT", "visit", "work:" + other, "Visit this neighbor if they are available.")
	return options

# The most pressing open check on a relative and grave visit become candidates; a search that
# found nobody waits out its deferral.
func _add_commitment_options(options: Array[Dictionary], id: String) -> void:
	var mind: NpcMindState = save_game.minds.get_mind(id)
	var best: Dictionary = {}
	for record: Dictionary in mind.commitments.open_commitments():
		if record.kind in [CHECK_RELATIVE, VISIT_GRAVE] \
				and float(record.priority) > float(best.get(record.kind, {}).get("priority", -1.0)) \
				and save_game.life.search_for(id, record.id).deferred_until <= save_game.life.minute \
				and not _commitment_place(id, record).is_empty():
			best[record.kind] = record
	for kind: String in [CHECK_RELATIVE, VISIT_GRAVE]:
		if not best.has(kind):
			continue
		var record: Dictionary = best[kind]
		var subject: String = record.other_ids[0]
		var place: String = _commitment_place(id, record)
		var label: String = _place(id, place).label
		var description: String = "Look for %s at %s to see that they are all right." \
			% [_name_of(subject), label] if kind == CHECK_RELATIVE \
			else "Visit %s at the cemetery and pay respects." % label
		options.append({"id": kind.to_upper(), "kind": kind, "place": place,
			"commitment_id": record.id, "subject": subject, "description": description})

# Where the commitment leads now: the current search place, or the known grave.
func _commitment_place(id: String, record: Dictionary) -> String:
	var subject: String = record.other_ids[0]
	if record.kind == VISIT_GRAVE:
		var grave: String = GRAVE_PREFIX + subject
		return grave if not _place(id, grave).is_empty() else ""
	var places: Array[String] = _search_places(id, subject)
	var step: int = save_game.life.search_for(id, record.id).step
	return places[step] if step < places.size() else ""

## Where a resident looks for a relative, in order: where it last saw them, then their home and
## workplace (public knowledge of every neighbor).
func _search_places(id: String, relative: String) -> Array[String]:
	var places: Array[String] = []
	if not _place(id, SEEN_PREFIX + relative).is_empty():
		places.append(SEEN_PREFIX + relative)
	for place: String in ["home:" + relative, "work:" + relative]:
		if _places.has(place):
			places.append(place)
	return places

## A named place as {label, position, space?}: fixed town places, where `id` last saw someone
## (seen:<other>, from its own knowledge) or a dug grave (grave:<deceased>); {} when unknown.
func _place(id: String, place: String) -> Dictionary:
	if _places.has(place):
		return _places[place]
	if place.begins_with(SEEN_PREFIX):
		var other: String = place.trim_prefix(SEEN_PREFIX)
		for fact: Dictionary in save_game.minds.get_mind(id).knowledge.known_locations(other):
			var value: Variant = fact.value
			if value is Dictionary and value.get("space") is String:
				return {"label": "where %s was last seen" % _name_of(other),
					"position": Vector2(float(value.x), float(value.y)), "space": value.space}
	elif place.begins_with(GRAVE_PREFIX) and funerals != null:
		var deceased: String = place.trim_prefix(GRAVE_PREFIX)
		if funerals.cemetery.graves().has(deceased):
			return {"label": "the grave of %s" % _name_of(deceased),
				"position": funerals.cemetery.plot_for(deceased) + GRAVE_STAND_OFFSET}
	return {}

func _name_of(id: String) -> String:
	return String(save_game.population.people.get(id, {}).get("name", id))

func _add_option(options: Array[Dictionary], id: String, kind: String, place: String, reason: String) -> void:
	if _places.has(place):
		var crowd: int = 0
		for resident: String in _actors:
			if save_game.life.get_person(resident).get("place") == place:
				crowd += 1
		if id in ["SOCIAL", "VISIT", "WALK"] and crowd >= 3:
			return
		options.append({"id": id, "kind": kind, "place": place,
			"description": "%s At %s. %s" % [kind.capitalize(), _places[place].label, reason]})

## Where an activity at a named place happens: {space, point, label}. Outdoor gatherings get a
## per-day spot so neighbors do not stack; meals use the household table.
func destination(id: String, selected: Dictionary) -> Dictionary:
	var place: Dictionary = _place(id, selected.place)
	if place.is_empty():
		place = _places["home:" + id]
	var space := StringName(place.get("space", "outdoors"))
	var random := NpcRoutinePlan.random_for(save_game.get_npc_seed(),
		"%s:spot:%s:%s" % [id, save_game.life.day(), selected.place])
	var offset := Vector2(random.randi_range(-2, 2), random.randi_range(-1, 1)) * 8.0
	# Only shared town places spread their visitors; a grave or a sighting is one exact spot.
	var spread: bool = space == &"outdoors" and _places.has(selected.place)
	var point: Vector2 = place.position + (offset if spread else Vector2.ZERO)
	if selected.kind == "meal" and buildings.rooms.has(space):
		point = buildings.rooms[space].meal_for(id)
	return {"space": space, "point": point, "label": place.label}

func brain_for(id: String) -> NpcBrain:
	return _brains.get(id)

func _add_brain(npc: BaseNpc, id: String) -> void:
	var brain := NpcBrain.new()
	brain.name = NpcBrain.NODE_NAME
	brain.memory = save_game.memory
	npc.add_child(brain)
	brain.setup(id, save_game.minds.get_mind(id), npc, buildings, tuning, save_game.get_npc_seed())
	brain.controller.transitioned.connect(_on_task_transition.bind(id))
	_brains[id] = brain

# Restores the saved task stack with the loaded clock; duty owners drop tasks they no longer
# hold, and an idle resident resumes its saved routine (or replans on the next tick).
func _restore_brain(npc: BaseNpc, id: String) -> void:
	var brain: NpcBrain = _brains[id]
	brain.restore_checkpoint(save_game.life.minute)
	watch.reconcile(id, brain)
	funerals.reconcile(id, brain)
	var saved: Dictionary = save_game.life.get_person(id)
	if brain.controller.current == null and brain.controller.suspended == null \
			and not _place(id, saved.place).is_empty():
		_request_routine(npc, id, {"kind": saved.activity, "place": saved.place})

# The route's activity label drives gait, work accounting and dialogue context.
func _on_task_transition(entry: Dictionary, id: String) -> void:
	if entry["to"] == NpcTask.status_name(NpcTask.Status.FAILED) and String(entry["kind"]) == "routine":
		_search_failed(id) # An unreachable search place counts as searched.
	if entry["to"] != NpcTask.status_name(NpcTask.Status.RUNNING) or not _brains.has(id):
		return
	var task: NpcTask = _brains[id].controller.current
	if task == null or task.task_id != entry["task_id"] or not is_instance_valid(_actors.get(id)):
		return
	var routine: NpcDailyRoutine = _actors[id].daily_routine
	if task.kind in [&"routine", &"recovery"]:
		routine.activity = task.params["activity"]
		routine.place = task.params["label"]
	elif task.kind == &"safety" and task.params["response"] == "SHELTER":
		routine.activity = "shelter"
		routine.place = task.params["label"]

func _update_context(npc: BaseNpc, id: String) -> void:
	var person: Dictionary = save_game.life.get_person(id)
	var relationships: NpcRelationshipGraph = save_game.minds.get_mind(id).relationships
	var neighbors: Array[Dictionary] = []
	for public_person: Dictionary in _public_people:
		if public_person.id == id:
			continue
		var known: Dictionary = public_person.duplicate(true)
		known.relationship = relationships.get_relationship(public_person.id) \
			if relationships.has_subject(public_person.id) else {}
		neighbors.append(known)
	npc.life_context = {"world_time": save_game.life.clock_text(), "world_minute": save_game.life.minute,
		"safety_response": NpcSafetyState.context(person.safety, save_game.life.minute),
		"known_townspeople": neighbors,
		"town_rumors": save_game.life.rumors.get_known(id, save_game.life.minute).slice(-4),
		"personality": npc.get_npc_profile().personality,
		"family_members": save_game.population.family_context(id),
		"household": save_game.population.household_for(id),
		"household_economy": save_game.economy.context(save_game.population.household_for(id))}
	npc.life_context.recent_social = encounters.social_history(id)
	if funerals != null:
		npc.life_context.known_deaths = funerals.known_losses(id)
	if npc.is_in_group(&"town_guards"):
		npc.life_context.enforcement = save_game.justice.known_to(id)

func _save() -> Error:
	for id: String in _actors:
		if is_instance_valid(_actors[id]) and _actors[id].health > 0:
			save_game.life.remember_position(id, _actors[id].global_position, String(_actors[id].world_space))
			if not _brains[id].save_checkpoint():
				_trace(id, NpcDecisionTrace.SAVE_FAILURE, {"reason": "task_checkpoint_rejected"})
	var error: Error = save_game.save_file()
	if error != OK:
		push_warning("Town life could not be saved: %s" % error)
		for id: String in _brains:
			_trace(id, NpcDecisionTrace.SAVE_FAILURE, {"reason": "save_error:%d" % error})
	return error

# Records a trace entry in resident `id`'s brain at the current world minute.
func _trace(id: String, kind: String, fields: Dictionary) -> void:
	if _brains.has(id):
		_brains[id].trace.record(save_game.life.minute, kind, fields)

func _on_request_settled(entry: Dictionary) -> void:
	var fields: Dictionary = entry.duplicate()
	fields.erase("npc_id")
	_trace(String(entry.npc_id), NpcDecisionTrace.REQUEST, fields)

func save_snapshot() -> Error:
	return _save()

func resident_ids() -> Array[String]:
	return _actors.keys()

func resident(id: String) -> BaseNpc:
	var npc: Variant = _actors.get(id)
	return npc if is_instance_valid(npc) and npc.health > 0 else null
