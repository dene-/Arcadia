extends "res://tests/test_case.gd"

const NpcProfileResource = preload("res://game/resources/actors/npc_profile.gd")

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
	assert_eq(payload["memories"], "Met the player, Lost a needle")

func test_to_backend_profile_uses_empty_memory_string_when_no_memories_exist() -> void:
	var profile := NpcProfileResource.new()

	var payload := profile.to_backend_profile()

	assert_eq(payload["memories"], "")
