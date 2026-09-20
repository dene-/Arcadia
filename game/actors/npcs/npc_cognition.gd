extends Node

## Application boundary for NPC cognition. Dialogue UI never owns event processing.
var save_game := NpcWorldSave.new()
var store: NpcMemoryStore = save_game.memory
var backend: DialogBackendClient
var events: NpcEventProcessor
var perception := NpcPerceptionRouter.new()

func _ready() -> void:
	var error: Error = save_game.load_file()
	if error != OK:
		push_warning("NPC memory save could not be loaded: %s" % error)
	backend = DialogBackendClient.new()
	add_child(backend)
	events = NpcEventProcessor.new()
	events.store = store
	events.backend = backend
	events.save_callback = save_game.save_file
	add_child(events)
	get_node("/root/WorldEvents").occurred.connect(_on_world_event)

func resume(source: BaseNpc) -> void:
	var profile: NpcProfile = source.get_npc_profile()
	if profile != null and not profile.npc_id.is_empty():
		events.resume(profile, source.get_cognitive_context(), source)

func _on_world_event(event: WorldEvent) -> void:
	# World truth is recorded synchronously at the lethal hit, before any network call.
	if event.kind == &"actor_died" and event.subject is BaseNpc:
		var profile: NpcProfile = event.subject.get_npc_profile()
		if profile != null:
			save_game.mark_dead(profile.npc_id)
	for observer: BaseNpc in get_tree().get_nodes_in_group(&"npc_observers"):
		var observed: Dictionary = perception.perceive(observer, event)
		if not observed.is_empty():
			events.observe(observer.get_npc_profile(), observer.get_cognitive_context(),
				observed, observer)
	var error: Error = save_game.save_file()
	if error != OK:
		push_warning("NPC world could not be saved: %s" % error)
