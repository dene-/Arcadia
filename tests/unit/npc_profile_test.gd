extends "res://tests/test_case.gd"

const NpcProfileResource = preload("res://game/resources/actors/npc_profile.gd")

func test_every_human_npc_supports_free_text_chat() -> void:
	var directory := DirAccess.open("res://game/resources/actors/humans")
	var count: int = 0
	for file_name: String in directory.get_files():
		if not file_name.ends_with("_npc_data.tres"):
			continue
		var data: NpcData = load(directory.get_current_dir().path_join(file_name))
		assert_true(data.able_to_chat, "%s must allow chat" % file_name)
		assert_not_null(data.profile)
		assert_false(data.profile.npc_id.is_empty())
		count += 1
	assert_eq(count, 9)

func test_to_backend_profile_maps_all_fields() -> void:
	var profile := NpcProfileResource.new()
	profile.profile_name = "Nara"
	profile.age = 42
	profile.sex = "Female"
	profile.job = "Tailor"
	profile.personality = "Patient"
	profile.family = "Has two siblings"
	profile.intelligence = "Careful speaker"
	profile.memories = PackedStringArray(["Met the player", "Lost a needle"])

	var payload := profile.to_backend_profile()

	assert_eq(payload["name"], "Nara")
	assert_eq(payload["age"], "42")
	assert_eq(payload["sex"], "Female")
	assert_eq(payload["job"], "Tailor")
	assert_eq(payload["personality"], "Patient")
	assert_eq(payload["family"], "Has two siblings")
	assert_eq(payload["intelligence"], "Careful speaker")
	assert_false(payload.has("memories"))
	assert_eq(profile.memories.size(), 2)

func test_backend_profile_never_exposes_the_memory_archive() -> void:
	var profile := NpcProfileResource.new()

	var payload := profile.to_backend_profile()

	assert_false(payload.has("memories"))
