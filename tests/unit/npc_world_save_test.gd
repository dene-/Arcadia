extends "res://tests/test_case.gd"

## Points all three save paths at private temp files so the player's saves are never read.
func _isolate(save: NpcWorldSave, filename: String) -> void:
	save.path = OS.get_temp_dir().path_join(filename)
	save.legacy_world_path = save.path + ".legacy-world"
	save.legacy_memory_path = save.path + ".legacy-memory"

func test_deaths_and_memories_round_trip_atomically_and_reset_together() -> void:
	var save := NpcWorldSave.new()
	_isolate(save, "arcadia-world-save-test.json")
	save.region_seed = 274415
	var profile := NpcProfile.new()
	profile.npc_id = &"test_named_victim"
	save.memory.record_event(profile, "The player threatened me.")
	save.mark_dead(profile.npc_id)
	assert_eq(save.save_file(), OK)
	var loaded := NpcWorldSave.new()
	_isolate(loaded, "arcadia-world-save-test.json")
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
	_isolate(restarted, "arcadia-world-save-test.json")
	assert_eq(restarted.load_file(), OK)
	assert_eq(restarted.region_seed, 0)
	assert_false(restarted.is_dead(profile.npc_id))
	assert_true(restarted.memory.snapshot(String(profile.npc_id)).is_empty())
	DirAccess.remove_absolute(save.path)
	for name: String in DirAccess.get_files_at(OS.get_temp_dir()):
		if name.begins_with("arcadia-world-save-test.json.reset-"):
			DirAccess.remove_absolute(OS.get_temp_dir().path_join(name))

func test_legacy_import_preserves_memories_without_inventing_past_deaths() -> void:
	var save := NpcWorldSave.new()
	_isolate(save, "arcadia-legacy-test.json")
	var legacy: Dictionary = {"version": 1, "turn": 1, "world_minute": 480.0, "next_memory_id": 1,
		"npcs": {"legacy_person": {"recent_dialogue": [], "memories": [],
			"recent_events": ["I saw someone die."], "relationship": NpcRelationshipState.initial()}}}
	var text: String = JSON.stringify(legacy)
	var file := FileAccess.open(save.legacy_memory_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	assert_eq(save.load_file(), OK)
	assert_true(save.dead_npcs.is_empty())
	assert_eq(save.memory.snapshot("legacy_person").recent_events, ["I saw someone die."])
	assert_eq(save.memory.snapshot("legacy_person").relationship, NpcRelationshipState.initial())
	file = FileAccess.open(save.path, FileAccess.WRITE)
	file.store_string("broken")
	file.close()
	assert_eq(save.load_file(), ERR_FILE_CORRUPT)
	assert_eq(save.save_file(), ERR_FILE_CORRUPT)
	assert_eq(FileAccess.get_file_as_string(save.path), "broken")
	assert_eq(FileAccess.get_file_as_string(save.legacy_memory_path), text)
	DirAccess.remove_absolute(save.legacy_memory_path)
	DirAccess.remove_absolute(save.path)

func test_region_seed_survives_reload_and_only_v1_saves_may_omit_it() -> void:
	var save := NpcWorldSave.new()
	save.region_seed = 731
	save.mark_dead(&"named_victim")
	var loaded := NpcWorldSave.new()
	assert_true(loaded.from_data(save.to_data()))
	assert_eq(loaded.region_seed, 731)
	assert_true(loaded.is_dead(&"named_victim"))
	var incomplete: Dictionary = save.to_data()
	incomplete.world.erase("region_seed")
	assert_false(loaded.from_data(incomplete), "Defaults for missing keys are the migration's job.")
	assert_eq(loaded.region_seed, 731)
	var old: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/cognition/v1_deaths.json"))
	old.world.erase("region_seed")
	var upgraded: Dictionary = NpcSaveMigration.upgrade(old)
	assert_true(upgraded.ok)
	assert_true(loaded.from_data(upgraded.data))
	assert_eq(loaded.region_seed, 0)
	assert_eq(loaded.dead_npcs, old.world.dead_npcs)
	loaded.region_seed = 731
	for invalid: Variant in ["bad", -1, 2.5, 2147483647]:
		var data: Dictionary = save.to_data()
		data.world.region_seed = invalid
		data.world.dead_npcs = ["someone_else"]
		assert_false(loaded.from_data(data))
		assert_eq(loaded.region_seed, 731)
		assert_eq(loaded.dead_npcs, old.world.dead_npcs)

func test_npc_reset_rerolls_lives_preserves_map_and_backs_up_all_previous_state() -> void:
	var save := NpcWorldSave.new()
	_isolate(save, "arcadia-npc-reroll-test.json")
	save.region_seed = 731
	save.population.ensure_population(save.region_seed)
	var profile: NpcProfile = save.population.profile_for("garrin_holt")
	save.memory.record_event(profile, "Den attacked me.")
	save.mark_dead(profile.npc_id)
	save.deaths.record(String(profile.npc_id), "outdoors", Vector2.ZERO, 480)
	save.justice.notice("vale_guard", "player", "killing", 480)
	save.economy.ensure_households(save.population, 480)
	save.economy.record_work("garrin_holt", 120)
	save.life.minute = 1500
	var ids: Array[String] = ["garrin_holt", "holt_partner"]
	save.life.ensure_person(ids[0], save.get_npc_seed(), ids, ["square"], save.population)
	var before_personality: Dictionary = save.life.personality_for(ids[0], save.get_npc_seed())
	var before_ties: Dictionary = save.life.get_person(ids[0]).ties
	var before_population: Dictionary = save.population.to_data()
	assert_eq(save.save_file(), OK)
	var before_json: String = FileAccess.get_file_as_string(save.path)
	assert_eq(save.reset(true, true), OK)
	assert_eq(save.region_seed, 731)
	assert_true(save.npc_seed > 0)
	assert_ne(save.get_npc_seed(), 731)
	assert_true(save.dead_npcs.is_empty())
	assert_true(save.deaths.ids().is_empty())
	assert_true(save.justice.reports.is_empty())
	assert_true(save.memory.snapshot(ids[0]).is_empty())
	assert_eq(save.life.to_data(), TownLifeState.new().to_data())
	assert_true(save.minds.ids().is_empty(), "Reset drops every mind with the old lives.")
	assert_eq(save.economy.to_data(), TownEconomy.new().to_data())
	var loaded := NpcWorldSave.new()
	_isolate(loaded, "arcadia-npc-reroll-test.json")
	assert_eq(loaded.load_file(), OK)
	assert_eq(loaded.npc_seed, save.npc_seed)
	loaded.population.ensure_population(loaded.region_seed)
	assert_eq(loaded.population.to_data(), before_population)
	loaded.life.ensure_person(ids[0], loaded.get_npc_seed(), ids, ["square"], loaded.population)
	var after_personality: Dictionary = loaded.life.personality_for(ids[0], loaded.get_npc_seed())
	assert_ne(after_personality, before_personality)
	assert_ne(loaded.life.get_person(ids[0]).ties, before_ties)
	assert_eq(loaded.save_file(), OK)
	var restarted := NpcWorldSave.new()
	_isolate(restarted, "arcadia-npc-reroll-test.json")
	assert_eq(restarted.load_file(), OK)
	assert_eq(restarted.life.personality_for(ids[0], restarted.get_npc_seed()).personality,
		after_personality.personality)
	for relative: String in loaded.life.get_person(ids[0]).ties:
		var original: Dictionary = loaded.life.get_person(ids[0]).ties[relative]
		var restored: Dictionary = restarted.life.get_person(ids[0]).ties[relative]
		for feeling: String in original:
			assert_true(is_equal_approx(restored[feeling], original[feeling]))
	var backups: int = 0
	for name: String in DirAccess.get_files_at(OS.get_temp_dir()):
		if name.begins_with("arcadia-npc-reroll-test.json.reset-"):
			var backup_path: String = OS.get_temp_dir().path_join(name)
			assert_eq(FileAccess.get_file_as_string(backup_path), before_json)
			DirAccess.remove_absolute(backup_path)
			backups += 1
	assert_eq(backups, 1)
	DirAccess.remove_absolute(save.path)

func test_v2_requires_npc_seed_and_invalid_seeds_do_not_mutate_state() -> void:
	var save := NpcWorldSave.new()
	save.region_seed = 731
	assert_true(save.from_data(save.to_data()))
	var incomplete: Dictionary = save.to_data()
	incomplete.world.erase("npc_seed")
	assert_false(save.from_data(incomplete))
	assert_eq(save.get_npc_seed(), 731)
	save.npc_seed = 92
	for invalid: Variant in ["bad", -1, 1.5, 2147483647, INF, NAN]:
		var data: Dictionary = save.to_data()
		data.world.npc_seed = invalid
		data.world.region_seed = 42
		assert_false(save.from_data(data))
		assert_eq(save.get_npc_seed(), 92)
		assert_eq(save.region_seed, 731)

func test_knowledge_and_evidence_round_trip_and_a_revision_one_root_migrates_on_load() -> void:
	var save := NpcWorldSave.new()
	_isolate(save, "arcadia-world-save-knowledge-test.json")
	save.region_seed = 274415
	var mind: NpcMindState = save.minds.get_mind("test_witness")
	mind.knowledge.record_sighting("test_guard", "outdoors", Vector2(5, 6), 480.0, "sighting:1")
	var observation: NpcObservation = NpcObservation.from_perception("test_witness", "world:1", 480.0,
		&"outdoors", {"kind": "stranger_seen", "sense": "sight", "text": "A stranger passed."})
	assert_true(mind.evidence.enqueue(observation))
	assert_eq(save.save_file(), OK)
	var loaded := NpcWorldSave.new()
	_isolate(loaded, "arcadia-world-save-knowledge-test.json")
	assert_eq(loaded.load_file(), OK)
	var restored: NpcMindState = loaded.minds.get_mind("test_witness")
	assert_eq(restored.knowledge.to_data(), mind.knowledge.to_data())
	assert_eq(restored.knowledge.known_locations("test_guard").size(), 1)
	assert_true(restored.evidence.contains_pending(observation.observation_id))
	var r1: Dictionary = save.to_data()
	r1.migration.revision = 1
	for state: Dictionary in r1.minds.minds.values():
		state.version = 1
		state.knowledge = {}
		state.erase("evidence")
	assert_false(loaded.from_data(r1), "A revision-1 root only loads through the migration.")
	assert_true(restored.evidence.contains_pending(observation.observation_id), "A rejected root changes nothing.")
	var upgraded: Dictionary = NpcSaveMigration.upgrade(r1)
	assert_true(upgraded.ok, str(upgraded.get("error", "")))
	assert_true(loaded.from_data(upgraded.data))
	assert_true(loaded.minds.get_mind("test_witness").knowledge.to_data().facts.is_empty())
