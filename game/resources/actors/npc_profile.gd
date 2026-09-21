class_name NpcProfile
extends Resource

## AI/dialog profile data for an NPC, consumed by DialogManager and the backend client.

## Stable save identity. Never derive this from the display name.
@export var npc_id: StringName
@export_multiline var background: String = ""
@export_multiline var values: String = ""
@export_multiline var fears: String = ""
@export_multiline var goals: String = ""
@export_multiline var speech_style: String = ""
## Save-generated social tendencies, copied into a runtime profile by town life.
@export var social_traits: Dictionary = {}
## Stable procedural speech choices; separate from temporary mood and response policy.
@export var voice: Dictionary = {}
@export var home: String = "Rekala"
@export var cognition: NpcCognitionProfile
@export var knowledge_packs: Array[NpcKnowledgePack] = []
@export var core_memories: Array[NpcCoreMemory] = []

## Name sent to dialog UI and backend profile payloads.
@export var profile_name: String = ""
## Character age sent to backend profile payloads.
@export_range(0, 120, 1) var age: int = 30
## Character sex descriptor sent to backend profile payloads.
@export_enum("Female", "Male", "Non-binary") var sex: String = "Female"
## Character job or social role sent to backend profile payloads.
@export var job: String = ""
## Personality notes used by the dialog backend.
@export_multiline var personality: String = ""
## Family or relationship notes used by the dialog backend.
@export_multiline var family: String = ""
## Intelligence or speaking-style notes used by the dialog backend.
@export var intelligence: String = ""
## Legacy authored memories, imported into the memory store on first encounter.
@export var memories: PackedStringArray = PackedStringArray()

func get_cognition() -> NpcCognitionProfile:
	return cognition if cognition != null else NpcCognitionProfile.new()

func to_backend_profile() -> Dictionary:
	var knowledge: Array[Dictionary] = []
	for pack: NpcKnowledgePack in knowledge_packs:
		if pack != null:
			knowledge.append(pack.to_data())
	return {
		"id": String(npc_id), "background": background, "values": values,
		"fears": fears, "goals": goals, "speech_style": speech_style, "home": home,
		"social_traits": social_traits.duplicate(true),
		"voice": voice.duplicate(true),
		"cognition": get_cognition().to_data(), "knowledge": knowledge,
		"name": profile_name,
		"age": str(age),
		"sex": sex,
		"job": job,
		"personality": personality,
		"family": family,
		"intelligence": intelligence,
	}
