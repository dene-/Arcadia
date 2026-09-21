class_name TownLife
extends Node

## Scene-owned application coordinator. Planning, movement, social sessions and saves have separate owners.
@export_range(0.0, 10.0, 0.1) var minutes_per_second: float = 1.5
@export_range(1, 12, 1) var max_decision_workers: int = 4
var save_game: NpcWorldSave
var backend: DialogBackendClient
var navigation := TownNavigation.new()
var encounters: TownEncounters
var buildings: TownBuildings
var watch: TownWatch
var _actors: Dictionary[String, BaseNpc] = {}
var _places: Dictionary[String, Dictionary] = {}
var _public_people: Array[Dictionary] = []
var _pending: Dictionary = {}
var _revisions: Dictionary = {}
var _tick: float = 0.0
var _save_elapsed: float = 0.0
var _initialized: bool = false
var _light: CanvasModulate
var _clock: Label

func _ready() -> void:
	set_process(false)
	var cognition: Node = get_node("/root/NpcCognition")
	save_game = cognition.save_game
	save_game.population.ensure_population(save_game.region_seed)
	save_game.economy.ensure_households(save_game.population, save_game.life.minute)
	backend = cognition.backend
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
	for id: String in ids:
		var npc: BaseNpc = _actors[id]
		save_game.life.ensure_person(id, save_game.region_seed, ids, ["market", "garden", "square"], save_game.population)
		npc.daily_routine = NpcDailyRoutine.new()
		npc.daily_routine.navigation = navigation
		npc.daily_routine.npc_id = id
		var saved: Dictionary = save_game.life.get_person(id)
		buildings.restore(npc, id, saved)
		_revisions[id] = npc.life_revision
		if _places.has(saved.place):
			_travel(npc, id, {"place": saved.place, "kind": saved.activity})
		_update_context(npc, id)
	encounters = TownEncounters.new()
	encounters.state = save_game.life
	encounters.store = save_game.memory
	encounters.backend = backend
	encounters.seed_value = save_game.region_seed
	encounters.save_callback = _save
	add_child(encounters)
	watch = TownWatch.new()
	watch.life = self
	add_child(watch)
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
	save_game.economy.settle(save_game.life.minute, save_game.population, save_game.dead_npcs)
	_tick += delta
	_save_elapsed += delta
	for id: String in _actors.keys():
		var npc: BaseNpc = _actors[id]
		if not is_instance_valid(npc) or npc.health <= 0:
			navigation.release(id)
			if is_instance_valid(npc):
				buildings.release(npc, id)
			_actors.erase(id)
			continue
		if _revisions[id] != npc.life_revision:
			_revisions[id] = npc.life_revision
			save_game.life.interrupt(id)
		npc.daily_routine.update(npc.global_position, delta, not npc.can_follow_routine())
		if npc.daily_routine.activity in ["work", "patrol", "school"] and npc.can_follow_routine() \
			and (npc.daily_routine.activity == "patrol" or npc.global_position.distance_to(npc.daily_routine.destination) <= 4):
			save_game.economy.record_work(id, elapsed_minutes)
		if not encounters.is_busy(id):
			buildings.advance(npc, id)
			_revisions[id] = npc.life_revision
	if _tick < 1.0:
		return
	_tick = 0.0
	var ids: Array[String] = _actors.keys()
	ids.sort()
	for id: String in ids:
		var npc: BaseNpc = _actors[id]
		save_game.life.ensure_person(id, save_game.region_seed, ids, ["market", "garden", "square"], save_game.population)
		if watch.maintain(npc, id) or _maintain_safety(npc, id):
			_update_context(npc, id)
			continue
		_wake_for_schedule(npc, id)
		_update_context(npc, id)
		if npc.can_follow_routine() and not encounters.is_busy(id) and not _pending.has(id) \
			and _pending.size() < max_decision_workers:
			var person: Dictionary = save_game.life.get_person(id)
			if person.until <= save_game.life.minute:
				_choose_activity(npc, id)
	# Rotate ordering deterministically so low-ID residents do not always initiate.
	if not ids.is_empty():
		var offset: int = int(save_game.life.minute) % ids.size()
		for index: int in range(ids.size()):
			var first: BaseNpc = _actors[ids[(index + offset) % ids.size()]]
			for second_id: String in ids:
				var second: BaseNpc = _actors[second_id]
				if first != second and first.can_speak_reaction() and second.can_speak_reaction():
					encounters.consider(first, second)
	_update_environment()
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
	if _initialized:
		_save()
	for npc: BaseNpc in _actors.values():
		if is_instance_valid(npc):
			npc.daily_routine = null

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
	_pending[id] = true
	var revision: int = npc.life_revision
	var person: Dictionary = save_game.life.get_person(id)
	var preferred: Dictionary = NpcRoutinePlan.current(person.plan, save_game.life.minute)
	var options: Array[Dictionary] = _options(id, preferred)
	save_game.memory.ensure_npc(npc.get_npc_profile())
	var memory: Dictionary = save_game.memory.snapshot(id)
	var current: Dictionary = NpcCognitiveContext.build(memory, npc.get_cognitive_context())
	current.participants = [id]
	current.relationship_with_player = memory.relationship
	current.memories = NpcMemoryRetriever.new().retrieve(memory.memories,
		str(current.get("activity", "")) + " " + preferred.kind + " "
		+ str(current.get("safety_response", {}).get("concern", "")),
		current, npc.get_npc_profile().get_cognition(), save_game.memory.world_minute)
	var payload: Dictionary = {"protocol_version": 1,
		"npc": {"id": id, "profile": npc.get_backend_profile()},
		"current": current, "candidates": options}
	var result: Dictionary = await backend.request_life("routine", payload)
	_pending.erase(id)
	if not is_inside_tree() or not is_instance_valid(npc) or not npc.can_follow_routine() \
		or npc.life_revision != revision or encounters.is_busy(id):
		return
	if save_game.life.get_person(id).safety != person.safety:
		return # A routine decision cannot supersede a new or newly assessed concern.
	if NpcRoutinePlan.current(save_game.life.get_person(id).plan, save_game.life.minute) != preferred:
		save_game.life.interrupt(id)
		return # A delayed nighttime decision cannot overwrite the morning routine.
	var policy: Dictionary = result.get("policy", {})
	var selected: Dictionary = options[0]
	var duration: float = 20.0
	var accepted: bool = false
	var valid: bool = policy.get("activity") is String \
		and (policy.get("duration_minutes") is int or policy.get("duration_minutes") is float)
	if valid and is_finite(float(policy.duration_minutes)):
		for option: Dictionary in options:
			if option.id == policy.activity:
				selected = option
				duration = clampf(policy.duration_minutes, 10, 90)
				accepted = true
				break
	# Deterministic fallback keeps everyday life moving when providers are unavailable.
	save_game.life.select_activity(id, selected, duration,
		{"service": "jev" if accepted else "schedule_fallback", "policy": policy})
	_travel(npc, id, selected)
	_update_context(npc, id)
	_save()

func _maintain_safety(npc: BaseNpc, id: String) -> bool:
	if npc.is_in_group(&"town_guards"):
		return false
	var person: Dictionary = save_game.life.get_person(id)
	if not NpcSafetyState.sheltering(person.safety, save_game.life.minute):
		return false
	encounters.interrupt(id)
	if person.activity == "shelter" and person.decision.get("safety_origin") == person.safety.origin_id:
		return true
	npc.interrupt_for_safety()
	if not npc.can_follow_routine():
		return true
	# Do not retreat into the room where the threat was perceived. Outdoors, home is
	# a known refuge; a threat in one's own home calls for leaving for the public market.
	var refuge: String = "home:" + id if person.safety.space != "home:" + save_game.population.household_for(id) else "market"
	if not _places.has(refuge):
		return false
	var selected: Dictionary = {"kind": "shelter", "place": refuge}
	npc.life_revision += 1
	save_game.life.select_activity(id, selected, person.safety.until - save_game.life.minute,
		{"service": "safety_response", "safety_origin": person.safety.origin_id})
	_travel(npc, id, selected)
	_save()
	return true

func _options(id: String, preferred: Dictionary) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	_add_option(options, "PLAN", preferred.kind, preferred.place, "Follow today's planned activity.")
	if preferred.kind in ["school", "patrol", "meal"]:
		return options
	var resident: Dictionary = save_game.population.people[id]
	if preferred.kind == "rest" or save_game.life.get_person(id).activity != "rest":
		_add_option(options, "REST", "rest", "home:" + id, "Take a bounded rest break at home.")
	var hour: int = int(save_game.life.minute / 60.0) % 24
	if hour >= 6 and hour < 21:
		var venues: Array[String] = ["square", "market", "garden"]
		var random_venue := NpcRoutinePlan.random_for(save_game.region_seed,
			"%s:venue:%d" % [id, int(save_game.life.minute / 60)])
		var venue: String = venues[random_venue.randi_range(0, venues.size() - 1)]
		_add_option(options, "SOCIAL", "socialize", venue, "Spend some free time here; neighbors may pass by.")
		_add_option(options, "MEAL", "meal", "market", "Take a meal break near the market stalls.")
		if resident.age >= 16 and not String(resident.job).begins_with("retired") and resident.job != "guard":
			_add_option(options, "WORK", "work", "work:" + id, "Return to professional work and daily obligations.")
		_add_option(options, "WALK", "walk", "garden", "Take a walk near the farm garden.")
		var ties: Dictionary = save_game.life.get_person(id).ties
		var residents: Array = ties.keys()
		residents.sort()
		if not residents.is_empty():
			var random := NpcRoutinePlan.random_for(save_game.region_seed,
				"%s:visit:%s" % [id, int(save_game.life.minute / 60)])
			var other: String = residents[random.randi_range(0, residents.size() - 1)]
			if _actors.has(other):
				_add_option(options, "VISIT", "visit", "work:" + other, "Visit this neighbor if they are available.")
	return options

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

func _travel(npc: BaseNpc, id: String, selected: Dictionary) -> void:
	var place: Dictionary = _places.get(selected.place, _places["home:" + id])
	var space := StringName(place.get("space", "outdoors"))
	var random := NpcRoutinePlan.random_for(save_game.region_seed,
		"%s:spot:%s:%s" % [id, save_game.life.day(), selected.place])
	var offset := Vector2(random.randi_range(-2, 2), random.randi_range(-1, 1)) * 8.0
	var destination: Vector2 = place.position + (offset if space == &"outdoors" else Vector2.ZERO)
	if selected.kind == "meal" and buildings.rooms.has(space):
		destination = buildings.rooms[space].meal_for(id)
	buildings.travel(npc, id, space, destination, selected.kind, place.label)
	_revisions[id] = npc.life_revision # A scheduled wakeup is part of this plan, not an interruption.
	npc.state_time_remaining = 0.0

func _wake_for_schedule(npc: BaseNpc, id: String) -> void:
	var person: Dictionary = save_game.life.get_person(id)
	if person.activity != "rest" or person.until > save_game.life.minute or not npc.can_follow_routine():
		return
	var preferred: Dictionary = NpcRoutinePlan.current(person.plan, save_game.life.minute)
	if preferred.kind == "rest":
		return
	# Waking is a schedule obligation, independent of model latency or repeated REST choices.
	npc.life_revision += 1
	save_game.life.select_activity(id, preferred, 20, {"service": "scheduled_wakeup"})
	_travel(npc, id, preferred)
	_revisions[id] = npc.life_revision

func _update_context(npc: BaseNpc, id: String) -> void:
	var person: Dictionary = save_game.life.get_person(id)
	var neighbors: Array[Dictionary] = []
	for public_person: Dictionary in _public_people:
		if public_person.id == id:
			continue
		var known: Dictionary = public_person.duplicate(true)
		known.relationship = person.ties.get(public_person.id, {})
		neighbors.append(known)
	npc.life_context = {"world_time": save_game.life.clock_text(), "world_minute": save_game.life.minute,
		"safety_response": NpcSafetyState.context(person.safety, save_game.life.minute),
		"daily_plan": person.plan, "known_townspeople": neighbors,
		"recent_social": person.recent_social, "town_rumors": save_game.life.rumors.get_known(id, save_game.life.minute).slice(-4),
		"routine_decision": person.decision, "personality": npc.get_npc_profile().personality,
		"family_members": save_game.population.family_context(id),
		"household": save_game.population.household_for(id),
		"household_economy": save_game.economy.context(save_game.population.household_for(id))}
	if encounters != null:
		npc.life_context.social_status = encounters.diagnostics(id)
	if npc.is_in_group(&"town_guards"):
		npc.life_context.enforcement = save_game.justice.known_to(id)

func _save() -> Error:
	for id: String in _actors:
		if is_instance_valid(_actors[id]) and _actors[id].health > 0:
			save_game.life.remember_position(id, _actors[id].global_position, String(_actors[id].world_space))
	var error: Error = save_game.save_file()
	if error != OK:
		push_warning("Town life could not be saved: %s" % error)
	return error

func travel_to(npc: BaseNpc, id: String, kind: String, place: String, duration: float = 20) -> void:
	var selected: Dictionary = {"kind": kind, "place": place}
	save_game.life.select_activity(id, selected, duration, {"service": "town_obligation"})
	_travel(npc, id, selected)

func investigate(npc: BaseNpc, id: String, space: StringName, position: Vector2) -> void:
	encounters.interrupt(id)
	buildings.travel(npc, id, space, position, "investigate", "a disturbance")
