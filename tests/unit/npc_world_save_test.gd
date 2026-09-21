extends "res://tests/test_case.gd"

func test_deaths_and_memories_round_trip_atomically_and_reset_together() -> void:
	var save := NpcWorldSave.new()
	save.path = OS.get_temp_dir().path_join("arcadia-world-save-test.json")
	save.region_seed = 274415
	var profile := NpcProfile.new()
	profile.npc_id = &"test_named_victim"
	save.memory.record_event(profile, "The player threatened me.")
	save.mark_dead(profile.npc_id)
	assert_eq(save.save_file(), OK)
	var loaded := NpcWorldSave.new()
	loaded.path = save.path
	assert_eq(loaded.load_file(), OK)
	assert_eq(loaded.region_seed, 274415)
	assert_true(loaded.is_dead(profile.npc_id))
	assert_eq(loaded.memory.snapshot(String(profile.npc_id)).recent_events.size(), 1)
	var invalid: Dictionary = loaded.to_data()
	invalid.memory.version = 999
	invalid.world.dead_npcs.clear()
	assert_false(loaded.from_data(invalid))
	assert_true(loaded.is_dead(profile.npc_id))
	assert_eq(loaded.reset(true), OK)
	assert_eq(loaded.region_seed, 274415)
	assert_false(loaded.is_dead(profile.npc_id))
	assert_true(loaded.memory.snapshot(String(profile.npc_id)).is_empty())
	assert_eq(loaded.reset(), OK)
	var restarted := NpcWorldSave.new()
	restarted.path = save.path
	assert_eq(restarted.load_file(), OK)
	assert_eq(restarted.region_seed, 0)
	assert_false(restarted.is_dead(profile.npc_id))
	assert_true(restarted.memory.snapshot(String(profile.npc_id)).is_empty())
	DirAccess.remove_absolute(save.path)
	for name: String in DirAccess.get_files_at(OS.get_temp_dir()):
		if name.begins_with("arcadia-world-save-test.json.reset-"):
			DirAccess.remove_absolute(OS.get_temp_dir().path_join(name))

func test_legacy_import_preserves_memories_without_inventing_past_deaths() -> void:
	var legacy := NpcMemoryStore.new()
	var profile := NpcProfile.new()
	profile.npc_id = &"legacy_person"
	legacy.record_event(profile, "I saw someone die.")
	var path: String = OS.get_temp_dir().path_join("arcadia-legacy-test.json")
	assert_eq(legacy.save_file(path), OK)
	var save := NpcWorldSave.new()
	save.path = path + ".new"
	assert_eq(save.load_file(path), OK)
	assert_true(save.dead_npcs.is_empty())
	assert_eq(save.memory.snapshot("legacy_person").recent_events, ["I saw someone die."])
	var file := FileAccess.open(save.path, FileAccess.WRITE)
	file.store_string("broken")
	file.close()
	assert_eq(save.load_file(path), ERR_FILE_CORRUPT)
	assert_eq(save.save_file(), ERR_FILE_CORRUPT)
	assert_eq(FileAccess.get_file_as_string(save.path), "broken")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(save.path)

func test_region_seed_survives_reload_and_old_saves_upgrade_without_losing_memories() -> void:
	var save := NpcWorldSave.new()
	save.region_seed = 731
	save.mark_dead(&"named_victim")
	var loaded := NpcWorldSave.new()
	assert_true(loaded.from_data(save.to_data()))
	assert_eq(loaded.region_seed, 731)
	assert_true(loaded.is_dead(&"named_victim"))
	var old: Dictionary = save.to_data()
	old.world.erase("region_seed")
	assert_true(loaded.from_data(old))
	assert_eq(loaded.region_seed, 0)
	assert_true(loaded.is_dead(&"named_victim"))
	for invalid: Variant in ["bad", -1, 2.5, 2147483647]:
		var data: Dictionary = save.to_data()
		data.world.region_seed = invalid
		assert_false(loaded.from_data(data))
		assert_eq(loaded.region_seed, 0)
		assert_true(loaded.is_dead(&"named_victim"))
