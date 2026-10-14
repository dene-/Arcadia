extends Node

const RETRY_INTERVAL_MSEC: int = 1000

## Application boundary for NPC cognition. Dialogue UI never owns event processing.
var save_game := NpcWorldSave.new()
var store: NpcMemoryStore = save_game.memory
var backend: DialogBackendClient
## Owner of every v2 cognition and optional-speech request; its transport is `backend`.
var decisions: NpcDecisionService
var events: NpcEventProcessor
var perception := NpcPerceptionRouter.new()
var ambient := NpcAmbientHistory.new()
var _next_retry_msec: int = 0

func _ready() -> void:
	store.memories_admitted.connect(_on_memories_admitted)
	var error: Error = save_game.load_file()
	if error != OK:
		push_warning("NPC memory save could not be loaded: %s" % error)
	backend = DialogBackendClient.new()
	add_child(backend)
	decisions = NpcDecisionService.new()
	decisions.transport = backend
	add_child(decisions)
	events = NpcEventProcessor.new()
	events.store = store
	events.decisions = decisions
	events.save_callback = save_game.save_file
	events.perception_classified.connect(_on_perception_classified)
	add_child(events)
	get_node("/root/WorldEvents").occurred.connect(_on_world_event)

func resume(source: BaseNpc) -> void:
	var profile: NpcProfile = source.get_npc_profile()
	if profile != null and not profile.npc_id.is_empty():
		events.resume(profile, source.get_cognitive_context(), source)

func _on_world_event(event: WorldEvent) -> void:
	if event.kind == &"actor_spoke":
		ambient.record(event.subject, event.facts.text, get_tree().get_nodes_in_group(&"npc_observers"))
		return
	if not perception.handles(event.kind):
		return
	var origin_id: String = save_game.life.issue_event_id()
	# World truth is recorded synchronously at the lethal hit, before any network call.
	if event.kind == &"actor_died" and event.subject is BaseNpc:
		var profile: NpcProfile = event.subject.get_npc_profile()
		if profile != null:
			events.cancel(String(profile.npc_id))
			save_game.mark_dead(profile.npc_id)
			if event.subject.is_in_group(&"town_residents"):
				save_game.deaths.record(String(profile.npc_id), String(event.subject.world_space),
					event.subject.global_position, save_game.life.minute)
	var snapshot: WorldEventSnapshot = WorldEventSnapshot.capture(event, origin_id, save_game.life.minute)
	var positions: Dictionary = _known_positions(snapshot, event)
	for observer: BaseNpc in get_tree().get_nodes_in_group(&"npc_observers"):
		var perceived: Dictionary = perception.perceive(observer, event)
		if perceived.is_empty():
			continue
		var observer_id: String = String(observer.get_npc_profile().npc_id)
		var observation: NpcObservation = NpcObservation.from_perception(observer_id, origin_id,
			snapshot.minute, observer.world_space, perceived, _evidence_position(snapshot, perceived))
		if observation == null:
			continue
		# Reflexes and daily life still consume the legacy dictionary shape.
		var legacy: Dictionary = observation.to_event()
		observer.alert_response.notice(observer, legacy)
		save_game.life.notice_perception(observer_id, legacy, String(observer.world_space))
		# Knowledge is learned the moment evidence is perceived; no provider is involved.
		perceive(save_game.minds.get_mind(observer_id), observation, positions)
		var current: Dictionary = observer.get_cognitive_context()
		current.world_minute = save_game.life.minute
		events.observe(observer.get_npc_profile(), current, observation, observer)
	var error: Error = save_game.save_file()
	if error != OK:
		push_warning("NPC world could not be saved: %s" % error)

## Drives the evidence retry ladder in real time, independent of simulation speed.
func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	if now >= _next_retry_msec:
		_next_retry_msec = now + RETRY_INTERVAL_MSEC
		retry_deferred_evidence()

## Resumes residents whose deferred evidence is due again (real-time retry ladder) and who have
## no turn queued or running.
func retry_deferred_evidence() -> void:
	var minute: float = save_game.life.minute
	var now_msec: float = float(events.clock.call())
	for observer: BaseNpc in get_tree().get_nodes_in_group(&"npc_observers"):
		var profile: NpcProfile = observer.get_npc_profile()
		if profile == null or profile.npc_id.is_empty() or events.is_busy(String(profile.npc_id)):
			continue
		if save_game.minds.get_mind(String(profile.npc_id)).evidence.ready_count(now_msec) > 0:
			var current: Dictionary = observer.get_cognitive_context()
			current.world_minute = minute
			events.resume(profile, current, observer)

## Where the event's people were, by identity. Only what the event itself establishes is listed:
## the subject at the moment of publication, a live instigator, and a body's resting place.
func _known_positions(snapshot: WorldEventSnapshot, event: WorldEvent) -> Dictionary:
	var positions: Dictionary = {}
	if snapshot.has_position and not snapshot.subject_id.is_empty():
		positions[snapshot.subject_id] = snapshot.position
	if not snapshot.instigator_id.is_empty() and event.instigator is Node2D \
			and (event.instigator as Node2D).is_inside_tree():
		positions[snapshot.instigator_id] = (event.instigator as Node2D).global_position
	var point: Variant = _body_point(snapshot)
	if point is Vector2:
		for participant: Dictionary in snapshot.facts.get("participants", []):
			if participant.get("role") == "deceased" and not String(participant.get("id", "")).is_empty():
				positions[participant["id"]] = point
	return positions

## Position stored with the evidence: heard events carry none, so a noise never locates anyone.
static func _evidence_position(snapshot: WorldEventSnapshot, perceived: Dictionary) -> Variant:
	if perceived.get("sense") == "hearing":
		return null
	var point: Variant = _body_point(snapshot)
	if point is Vector2:
		return point
	return snapshot.position if snapshot.has_position else null

static func _body_point(snapshot: WorldEventSnapshot) -> Variant:
	var raw: Variant = snapshot.facts.get("position")
	if raw is Array and (raw as Array).size() == 2 and (raw[0] is float or raw[0] is int) \
			and (raw[1] is float or raw[1] is int):
		return Vector2(float(raw[0]), float(raw[1]))
	return null

## A resident sees a grave: it learns who lies there, never how they died. Repeat sightings of
## the same grave share one origin and add nothing.
func see_grave(observer_id: String, deceased_id: String, point: Vector2) -> void:
	var person: Variant = save_game.population.people.get(deceased_id)
	var deceased_name: String = String(person.get("name", deceased_id)) if person is Dictionary else deceased_id
	var observation: NpcObservation = grave_observation(observer_id, deceased_id, deceased_name,
		save_game.life.minute, point)
	if observation != null:
		perceive(save_game.minds.get_mind(observer_id), observation, {})

## Learns from one observation; the first evidence of a relative's death leaves a bereavement
## concern. Kin are the resident's own family facts, so only informed relatives grieve.
static func perceive(mind: NpcMindState, observation: NpcObservation, positions: Dictionary) -> void:
	var deceased: String = _deceased(observation)
	var knew: bool = deceased.is_empty() or _knows_dead(mind.knowledge, deceased)
	learn(mind.knowledge, observation, positions)
	if not knew and _knows_dead(mind.knowledge, deceased) and mind.knowledge.knows(deceased, "family_role"):
		mind.add_bereavement(deceased, observation.observation_id, observation.observed_minute)

## A grave seen in the cemetery: it shows who lies there and nothing about how they died.
static func grave_observation(observer_id: String, deceased_id: String, deceased_name: String,
		minute: float, point: Vector2) -> NpcObservation:
	return NpcObservation.from_perception(observer_id, "grave:" + deceased_id, minute, &"outdoors",
		{"kind": "body_buried", "sense": "sight", "text": "I saw the grave of %s." % deceased_name,
		"topics": ["death", "town"], "participants": [{"id": deceased_id, "name": deceased_name,
		"role": "deceased"}]}, point)

static func _knows_dead(knowledge: NpcKnowledge, subject: String) -> bool:
	for fact: Dictionary in knowledge.current(subject, "status"):
		if fact["value"] == "dead":
			return true
	return false

## Personal knowledge from one observation. `positions` maps identity -> where the event placed
## that person. Unseen or anonymous people are never located, and the observer is never "seen".
static func learn(knowledge: NpcKnowledge, observation: NpcObservation, positions: Dictionary) -> void:
	var seen: bool = observation.modality in [NpcObservation.Modality.SIGHT, NpcObservation.Modality.TOUCH]
	var minute: float = observation.observed_minute
	if seen:
		for id: String in observation.participant_ids():
			if id != observation.observer_id and positions.get(id) is Vector2:
				knowledge.record_sighting(id, String(observation.space_id), positions[id], minute,
					observation.observation_id)
	var deceased: String = _deceased(observation)
	if deceased.is_empty():
		return
	var evidence_id: String = observation.observation_id
	match observation.kind:
		&"actor_died", &"body_found":
			knowledge.record(deceased, "status", "dead", NpcKnowledge.Status.OBSERVED,
				NpcKnowledge.SELF_SOURCE, evidence_id, observation.origin_id, minute, 1.0)
		&"body_reported":
			knowledge.record_report(deceased, "status", "dead", observation.source_id,
				observation.origin_id, evidence_id, minute, 0.8)
		&"body_buried":
			if observation.modality == NpcObservation.Modality.SPOKEN_REPORT:
				knowledge.record_report(deceased, "burial", "buried", observation.source_id,
					observation.origin_id, evidence_id, minute, 0.8)
			else:
				knowledge.record(deceased, "burial", "buried", NpcKnowledge.Status.OBSERVED,
					NpcKnowledge.SELF_SOURCE, evidence_id, observation.origin_id, minute, 1.0)

## Whose death or burial the observation establishes; empty when none (the player respawns, so a
## resident never learns that "the player is dead").
static func _deceased(observation: NpcObservation) -> String:
	var deceased: String = ""
	match observation.kind:
		&"actor_died":
			if observation.modality in [NpcObservation.Modality.SIGHT, NpcObservation.Modality.TOUCH]:
				deceased = _participant_with_role(observation, "hurt_person")
		&"body_found", &"body_reported", &"body_buried":
			deceased = _participant_with_role(observation, "deceased")
	return "" if deceased == "player" else deceased

static func _participant_with_role(observation: NpcObservation, role: String) -> String:
	for participant: Dictionary in observation.participants:
		if participant.get("role") == role and not String(participant.get("id", "")).is_empty():
			return participant["id"]
	return ""

func _on_perception_classified(id: String, event: Dictionary, policy: Dictionary) -> void:
	save_game.life.assess_perception(id, event, policy)
	for observer: BaseNpc in get_tree().get_nodes_in_group(&"npc_observers"):
		if String(observer.get_npc_profile().npc_id) == id:
			save_game.life.rumors.observe(id, observer.get_npc_profile().profile_name,
				event, policy, save_game.life.minute)
			save_game.life.interrupt(id)
			return

func _on_memories_admitted(id: String, memories: Array) -> void:
	var name: String = id
	for npc: BaseNpc in get_tree().get_nodes_in_group(&"npc_observers"):
		if String(npc.get_npc_profile().npc_id) == id:
			name = npc.get_npc_profile().profile_name
			break
	for memory: Dictionary in memories:
		if not memory.source in ["player_claim", "npc_statement"]:
			continue
		var attribution: String = "I heard the player say: " if memory.source == "player_claim" else "I told the player: "
		save_game.life.rumors.observe(id, name, {"origin_id": "conversation:%s:%s" % [id, memory.id],
			"text": (attribution + memory.gist).substr(0, 500), "sense": "hearing",
			"player_involved": true, "basis": memory.source},
			{"remember": true, "importance": memory.importance}, save_game.life.minute)
