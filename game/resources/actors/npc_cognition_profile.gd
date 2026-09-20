class_name NpcCognitionProfile
extends Resource

## Authored differences in attention and recall; never mutated by conversations.
@export_range(0.0, 1.0) var attention: float = 0.6
@export_range(0.0, 1.0) var factual_recall: float = 0.6
@export_range(0.0, 1.0) var social_recall: float = 0.6
@export_range(0.0, 1.0) var emotional_retention: float = 0.7
@export_range(0.0, 1.0) var name_recall: float = 0.5
@export_range(0.0, 1.0) var sensory_association: float = 0.5

func to_data() -> Dictionary:
	return {
		"attention": attention, "factual_recall": factual_recall,
		"social_recall": social_recall, "emotional_retention": emotional_retention,
		"name_recall": name_recall, "sensory_association": sensory_association,
	}
