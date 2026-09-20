class_name NpcKnowledgePack
extends Resource

## Reusable expertise or local knowledge, including what the NPC does not know.
@export var knowledge_id: StringName
@export var title: String = ""
@export_multiline var knowledge: String = ""
@export_multiline var limitations: String = ""

func to_data() -> Dictionary:
	return {"id": String(knowledge_id), "title": title,
		"knowledge": knowledge, "limitations": limitations}
