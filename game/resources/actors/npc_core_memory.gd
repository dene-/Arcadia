class_name NpcCoreMemory
extends Resource

## Authored memory. Details remain in the save; recall reveals only accessible fragments.
@export var memory_id: StringName
@export_enum("episodic", "semantic", "social", "prospective") var type: String = "episodic"
@export_multiline var gist: String = ""
@export_range(0, 100000) var age_turns: int = 0
@export_range(0.0, 1.0) var importance: float = 0.7
@export_range(0.0, 1.0) var emotional_intensity: float = 0.5
@export_range(0.0, 1.0) var vividness: float = 0.6
@export_range(0.0, 1.0) var confidence: float = 0.8
@export var topics: PackedStringArray = []
@export var people: PackedStringArray = []
@export var places: PackedStringArray = []
@export var sensory_cues: PackedStringArray = []
@export var important_details: PackedStringArray = []
@export var weak_details: PackedStringArray = []
@export var known_gaps: PackedStringArray = []

func to_memory() -> Dictionary:
	var memory: Dictionary = NpcMemory.create(
		"core:" + String(memory_id), type, gist, "authored", -age_turns
	)
	memory.merge({"importance": importance, "emotional_intensity": emotional_intensity,
		"vividness": vividness, "confidence": confidence}, true)
	for key: String in NpcMemory.TEXT_LISTS:
		memory[key] = Array(get(key))
	return memory
