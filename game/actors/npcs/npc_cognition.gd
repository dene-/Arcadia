extends Node

## Application boundary for NPC cognition. Dialogue UI never owns event processing.
var save_game := NpcWorldSave.new()
var store: NpcMemoryStore = save_game.memory
var backend: DialogBackendClient
var events: NpcEventProcessor
var perception := NpcPerceptionRouter.new()

func _ready() -> void:
	store.memories_admitted.connect(_on_memories_admitted)
	var error: Error = save_game.load_file()
	if error != OK:
		push_warning("NPC memory save could not be loaded: %s" % error)
	backend = DialogBackendClient.new()
	add_child(backend)
	events = NpcEventProcessor.new()
	events.store = store
	events.backend = backend
	events.save_callback = save_game.save_file
	events.perception_classified.connect(_on_perception_classified)
	add_child(events)
	get_node("/root/WorldEvents").occurred.connect(_on_world_event)

func resume(source: BaseNpc) -> void:
	var profile: NpcProfile = source.get_npc_profile()
	if profile != null and not profile.npc_id.is_empty():
		events.resume(profile, source.get_cognitive_context(), source)

func _on_world_event(event: WorldEvent) -> void:
	var origin_id: String = save_game.life.issue_event_id()
	# World truth is recorded synchronously at the lethal hit, before any network call.
	if event.kind == &"actor_died" and event.subject is BaseNpc:
		var profile: NpcProfile = event.subject.get_npc_profile()
		if profile != null:
			save_game.mark_dead(profile.npc_id)
	for observer: BaseNpc in get_tree().get_nodes_in_group(&"npc_observers"):
		var observed: Dictionary = perception.perceive(observer, event)
		if not observed.is_empty():
			observed.origin_id = origin_id
			events.observe(observer.get_npc_profile(), observer.get_cognitive_context(),
				observed, observer)
	var error: Error = save_game.save_file()
	if error != OK:
		push_warning("NPC world could not be saved: %s" % error)

func _on_perception_classified(id: String, event: Dictionary, policy: Dictionary) -> void:
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
