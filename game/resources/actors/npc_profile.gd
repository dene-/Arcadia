class_name NpcProfile
extends Resource

## AI/dialog profile data for an NPC, consumed by DialogManager and the backend client.

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
## Persistent memories included in backend profile payloads.
@export var memories: PackedStringArray = PackedStringArray()

func to_backend_profile() -> Dictionary:
	return {
		"name": profile_name,
		"age": str(age),
		"sex": sex,
		"job": job,
		"personality": personality,
		"family": family,
		"intelligence": intelligence,
		"memories": ", ".join(memories),
	}
