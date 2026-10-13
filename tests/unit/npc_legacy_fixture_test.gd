extends "res://tests/test_case.gd"

## Characterizes the v1 NpcWorldSave format with synthetic saves generated from the v1 code.
const DIR: String = "res://tests/fixtures/cognition/"
const ROUND_TRIP: Array[String] = ["v1_empty", "v1_town", "v1_town_rerolled", "v1_deaths",
	"v1_observations", "v1_rumors", "v1_prospective"]

func _text(name: String) -> String:
	return FileAccess.get_file_as_string(DIR + name + ".json")

func _fixture(name: String) -> Dictionary:
	return JSON.parse_string(_text(name)) as Dictionary

func _load(name: String) -> NpcWorldSave:
	var save := NpcWorldSave.new()
	assert_true(save.from_data(_fixture(name)), name + " must load")
	return save

func _normalized(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data)) as Dictionary

func _temp(name: String) -> String:
	return OS.get_temp_dir().path_join("arcadia-legacy-fixture-%s-%s.json" % [OS.get_process_id(), name])

func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _profile(id: String) -> NpcProfile:
	var profile := NpcProfile.new()
	profile.npc_id = StringName(id)
	return profile

func _memories(save: NpcWorldSave, id: String) -> Array:
	return save.memory.snapshot(id).memories

func _count_source(save: NpcWorldSave, id: String, source: String) -> int:
	var count: int = 0
	for memory: Dictionary in _memories(save, id):
		count += int(memory.source == source)
	return count

func test_valid_v1_fixtures_reserialize_unchanged_from_data_and_from_disk() -> void:
	for name: String in ROUND_TRIP:
		var data: Dictionary = _fixture(name)
		var save := NpcWorldSave.new()
		assert_true(save.from_data(data), name + " must load")
		assert_eq(_normalized(save.to_data()), data, name + " changed on re-serialization")
		var path: String = _temp(name)
		_write_text(path, _text(name))
		var from_disk := NpcWorldSave.new()
		from_disk.path = path
		assert_eq(from_disk.load_file(_temp("absent-legacy")), OK, name)
		assert_eq(_normalized(from_disk.to_data()), data, name + " changed through load_file")
		DirAccess.remove_absolute(path)

func test_town_fixture_holds_population_economy_justice_safety_and_two_memory_states() -> void:
	var save: NpcWorldSave = _load("v1_town")
	assert_eq(save.region_seed, 274415)
	assert_eq(save.npc_seed, 0)
	assert_eq(save.get_npc_seed(), 274415)
	assert_eq(save.life.minute, 3451.0)
	assert_eq(save.population.people.size(), 33)
	var life: Dictionary = save.life.to_data()
	assert_eq(life.people.size(), 33)
	assert_eq(life.personalities.size(), 33)
	assert_eq(life.people.garrin_holt.ties.size(), 32)
	assert_eq(life.people.garrin_holt.ties.holt_partner.familiarity, 1.0, "Kin ties are initialized.")
	assert_true(life.rumors.is_empty())
	var total: int = save.economy.treasury
	var changed: int = 0
	for coins: int in save.economy.accounts.values():
		total += coins
		changed += int(coins != 120)
	assert_eq(save.economy.accounts.size(), 12)
	assert_eq(total, 6000 + 12 * 120, "Coins are conserved.")
	assert_true(changed > 0, "Settled balances are non-trivial.")
	assert_eq(save.economy.settled_day, 1)
	assert_false(save.economy.ledger.is_empty())
	assert_true(save.economy.work_minutes.has("garrin_holt"))
	assert_eq(save.justice.reports.size(), 1)
	assert_eq(save.justice.current("voss_guard", "player", save.life.minute).status, "warning")
	var cautious: Dictionary = save.life.get_person("rowan_sibling_b").safety
	assert_true(NpcSafetyState.active(cautious, 3440.0))
	assert_false(NpcSafetyState.active(cautious, save.life.minute), "The caution lapsed at minute 3450.")
	assert_eq(cautious.response, "CAUTION")
	assert_true(NpcSafetyState.sheltering(save.life.get_person("ash_partner").safety, save.life.minute))
	assert_true(save.life.get_person("voss_child").safety.is_empty())
	var persisted: Dictionary = save.memory.to_save_data()
	var ids: Array = persisted.npcs.keys()
	ids.sort()
	assert_eq(ids, ["garrin_holt", "holt_partner"])
	var garrin: Dictionary = save.memory.snapshot("garrin_holt")
	assert_eq(garrin.memories.size(), 4)
	var types: Array = garrin.memories.map(func(memory: Dictionary) -> String: return memory.type)
	assert_true("episodic" in types and "semantic" in types)
	assert_eq(_count_source(save, "garrin_holt", "authored"), 2)
	assert_eq(garrin.recent_dialogue.size(), 6)
	assert_ne(garrin.relationship, NpcRelationshipState.initial())
	assert_ne(save.memory.snapshot("holt_partner").relationship, NpcRelationshipState.initial())
	assert_eq(save.memory.snapshot("holt_partner").recent_dialogue.size(), 4)

func test_rerolled_fixture_generates_personalities_and_ties_from_the_nonzero_npc_seed() -> void:
	var town: NpcWorldSave = _load("v1_town")
	var rerolled: NpcWorldSave = _load("v1_town_rerolled")
	assert_eq(rerolled.region_seed, 274415)
	assert_eq(rerolled.npc_seed, 918273)
	assert_eq(rerolled.get_npc_seed(), 918273)
	assert_eq(rerolled.population.to_data(), town.population.to_data(), "Identities follow the region seed.")
	var saved: Dictionary = rerolled.life.personality_for("sella_rowan", rerolled.get_npc_seed())
	var generated: Dictionary = NpcTemperament.generate(918273, "sella_rowan")
	assert_eq(saved.voice, generated.voice)
	assert_eq(saved.personality, generated.personality)
	for tendency: String in NpcTemperament.TRAITS:
		assert_true(is_equal_approx(saved.traits[tendency], generated.traits[tendency]))
	assert_ne(rerolled.life.get_person("garrin_holt").ties.sella_rowan,
		town.life.get_person("garrin_holt").ties.sella_rowan)

func test_unusual_but_valid_voices_survive_loading_unchanged() -> void:
	for name: String in ["v1_town", "v1_town_rerolled"]:
		var save: NpcWorldSave = _load(name)
		var reserved: Dictionary = save.life.personality_for("mirelle_voss", save.get_npc_seed())
		assert_eq(reserved.voice, {"register": "PRECISE", "cadence": "MEASURED", "verbosity": "SPARE",
			"directness": "TENTATIVE", "humor": "EARNEST", "disclosure": "RESERVED", "questions": "INQUISITIVE"})
		assert_eq(reserved.traits.sociability, 0.0)
		assert_eq(reserved.traits.discretion, 1.0)
		var loud: Dictionary = save.life.personality_for("tovan_reed", save.get_npc_seed())
		assert_eq(loud.voice, {"register": "FAMILIAR", "cadence": "BRISK", "verbosity": "EXPANSIVE",
			"directness": "BLUNT", "humor": "PLAYFUL", "disclosure": "OPEN", "questions": "RARE"})
		assert_eq(loud.traits.courage, 1.0)
		assert_eq(loud.traits.patience, 0.0)
		assert_true(NpcTemperament.is_valid(reserved) and NpcTemperament.is_valid(loud))

func test_deaths_fixture_has_one_body_in_every_stage_consistent_with_dead_npcs() -> void:
	var save: NpcWorldSave = _load("v1_deaths")
	var by_stage: Dictionary = {}
	for id: String in save.deaths.records:
		by_stage[save.deaths.records[id].stage] = id
		assert_true(save.is_dead(StringName(id)))
	assert_eq(save.deaths.records.size(), 6)
	assert_eq(by_stage.size(), 6)
	assert_eq(save.dead_npcs.size(), 6)
	for stage: String in TownDeaths.STAGES:
		assert_true(by_stage.has(stage), stage)
	var fallen: Dictionary = save.deaths.records[by_stage.fallen]
	assert_true(fallen.reporter.is_empty() and fallen.guard.is_empty() and fallen.known_by.is_empty())
	var discovered: Dictionary = save.deaths.records[by_stage.discovered]
	assert_false(discovered.reporter.is_empty())
	assert_true(discovered.guard.is_empty())
	assert_true(discovered.reporter in discovered.known_by)
	for stage: String in ["reported", "recovering", "carried", "buried"]:
		var entry: Dictionary = save.deaths.records[by_stage[stage]]
		assert_false(entry.reporter.is_empty(), stage)
		assert_false(entry.guard.is_empty(), stage)
		assert_true(entry.guard in entry.known_by, stage)
		assert_false(save.is_dead(StringName(entry.guard)), stage + " carrier is alive")
	var buried: Dictionary = save.deaths.records[by_stage.buried]
	assert_false(buried.burial_known_by.is_empty())
	for stage: String in ["fallen", "discovered", "reported", "recovering", "carried"]:
		assert_true(save.deaths.records[by_stage[stage]].burial_known_by.is_empty(), stage)

func test_observation_fixture_holds_every_status_and_applies_relationship_change_once() -> void:
	var save: NpcWorldSave = _load("v1_observations")
	var town: NpcWorldSave = _load("v1_town")
	var observations: Array = save.memory.snapshot("holt_partner").observations
	assert_eq(observations.size(), 4)
	var statuses: Dictionary = {}
	for observation: Dictionary in observations:
		statuses[int(observation.id)] = observation
	assert_eq(statuses[1].status, "pending")
	assert_eq(statuses[1].sense, "sight")
	assert_eq(statuses[2].status, "unavailable")
	assert_true(statuses[2].decision.is_empty())
	assert_eq(statuses[3].status, "classified")
	assert_eq(statuses[3].sense, "hearing")
	assert_eq(statuses[4].status, "classified")
	assert_true(statuses[4].player_involved)
	assert_eq(save.memory.pending_observations("holt_partner").size(), 1)
	assert_eq(save.memory.pending_observations("holt_partner")[0].id, 1)
	assert_eq(save.memory.to_save_data().npcs.holt_partner.next_observation_id, 5)
	var heard: Array = _memories(save, "holt_partner").filter(
		func(memory: Dictionary) -> bool: return "sounds of fighting" in memory.sensory_cues)
	assert_eq(heard.size(), 1)
	assert_eq(heard[0].source, "observed_event")
	assert_eq(heard[0].gist, statuses[3].text)
	var seen: Array = _memories(save, "holt_partner").filter(
		func(memory: Dictionary) -> bool: return memory.gist == statuses[4].text)
	assert_eq(seen.size(), 1)
	var before: Dictionary = town.memory.snapshot("holt_partner").relationship
	var after: Dictionary = save.memory.snapshot("holt_partner").relationship
	assert_true(is_equal_approx(after.trust - before.trust, 0.05), "Only the sight observation moved trust.")
	assert_true(is_equal_approx(after.respect - before.respect, 0.04))
	assert_eq(after.fear, before.fear)

func test_rumor_fixture_keeps_receipts_hearsay_memories_and_account_chains() -> void:
	var save: NpcWorldSave = _load("v1_rumors")
	var town: NpcWorldSave = _load("v1_town")
	var persisted: Dictionary = save.memory.to_save_data()
	assert_eq(persisted.npcs.sella_rowan.heard_origins.size(), 1)
	assert_eq(persisted.npcs.garrin_holt.heard_origins.size(), 1)
	assert_eq(persisted.npcs.holt_partner.heard_origins.size(), 2)
	assert_eq(_count_source(save, "sella_rowan", "hearsay"), 1)
	assert_eq(_count_source(save, "garrin_holt", "hearsay"), 1)
	assert_eq(_count_source(save, "holt_partner", "hearsay"), 1, "A receipt can outlive a discarded story.")
	var minute: float = save.life.minute
	var garrin: Array[Dictionary] = save.life.rumors.get_known("garrin_holt", minute)
	assert_eq(garrin.size(), 1)
	assert_eq(garrin[0].hops, 2)
	assert_eq(garrin[0].chain, ["bram_edevane", "sella_rowan", "garrin_holt"])
	assert_true(save.life.rumors.get_known("holt_partner", minute).any(
		func(account: Dictionary) -> bool: return account.hops == 3))
	assert_eq(save.life.rumors.get_known("bram_edevane", minute)[0].hops, 0)
	assert_eq(save.life.rumors.get_known("tovan_reed", minute).size(), 1)
	var trust: float = save.memory.snapshot("garrin_holt").relationship.trust
	assert_true(is_equal_approx(trust - town.memory.snapshot("garrin_holt").relationship.trust, -0.02),
		"Confident player-involved hearsay nudges trust.")
	assert_eq(save.memory.snapshot("holt_partner").relationship.trust,
		town.memory.snapshot("holt_partner").relationship.trust, "Weak hearsay does not.")
	var memories_before: int = _memories(save, "garrin_holt").size()
	save.memory.record_hearsay(_profile("garrin_holt"), garrin[0],
		{"remember": true, "importance": 0.9, "trust_player": -0.03})
	assert_eq(_memories(save, "garrin_holt").size(), memories_before, "Retelling is not new evidence.")
	assert_eq(save.memory.snapshot("garrin_holt").relationship.trust, trust)

func test_prospective_fixture_has_one_completed_and_one_open_intention() -> void:
	var save: NpcWorldSave = _load("v1_prospective")
	var intentions: Array = _memories(save, "garrin_holt").filter(
		func(memory: Dictionary) -> bool: return memory.type == "prospective")
	assert_eq(intentions.size(), 2)
	var done: Array = intentions.filter(func(memory: Dictionary) -> bool: return memory.completed)
	var open: Array = intentions.filter(func(memory: Dictionary) -> bool: return not memory.completed)
	assert_eq(done.size(), 1)
	assert_eq(open.size(), 1)
	assert_true(done[0].gist.begins_with("I promised"))
	assert_true(open[0].gist.begins_with("I intend"))
	assert_true(save.memory.complete_intention("garrin_holt", open[0].id))
	assert_eq(_memories(save, "garrin_holt").filter(
		func(memory: Dictionary) -> bool: return memory.completed).size(), 2)
	assert_false(save.memory.complete_intention("garrin_holt", "mem:9999"))

func test_missing_optional_keys_are_defaulted_on_load() -> void:
	var data: Dictionary = _fixture("v1_missing_optional")
	assert_false(data.world.has("npc_seed"))
	assert_false(data.world.life.has("personalities"))
	for person: Dictionary in data.world.life.people.values():
		assert_false(person.has("safety"))
	for state: Dictionary in data.memory.npcs.values():
		assert_false(state.has("observations") or state.has("next_observation_id") or state.has("heard_origins"))
	var save := NpcWorldSave.new()
	assert_true(save.from_data(data))
	var expected: Dictionary = _fixture("v1_town")
	expected.world.npc_seed = 0
	expected.world.life.personalities = {}
	for person: Dictionary in expected.world.life.people.values():
		person.safety = {}
	for state: Dictionary in expected.memory.npcs.values():
		state.observations = []
		state.next_observation_id = 1
		state.heard_origins = {}
	assert_eq(_normalized(save.to_data()), _normalized(expected))
	assert_eq(save.npc_seed, 0)
	assert_true(save.life.to_data().personalities.is_empty())
	assert_true(save.life.get_person("rowan_sibling_b").safety.is_empty())
	var restored: Dictionary = save.life.personality_for("sella_rowan", save.get_npc_seed())
	var original: Dictionary = _load("v1_town").life.personality_for("sella_rowan", 274415)
	assert_eq(restored.voice, original.voice, "Missing personalities regenerate deterministically.")

func test_memory_only_legacy_file_loads_when_the_world_file_is_missing_and_migrates_on_save() -> void:
	var legacy: String = _temp("legacy-memory")
	_write_text(legacy, _text("memory_only_legacy"))
	var save := NpcWorldSave.new()
	save.path = _temp("world-missing")
	DirAccess.remove_absolute(save.path)
	assert_eq(save.load_file(legacy), OK)
	assert_eq(save.life.minute, 1234.0)
	assert_eq(save.memory.world_minute, 1234.0)
	assert_eq(_normalized(save.memory.to_save_data()), _fixture("memory_only_legacy"))
	assert_true(save.dead_npcs.is_empty())
	assert_true(save.population.people.is_empty())
	assert_true(save.deaths.records.is_empty())
	assert_eq(save.region_seed, 0)
	assert_eq(save.save_file(), OK)
	var migrated := NpcWorldSave.new()
	migrated.path = save.path
	assert_eq(migrated.load_file(_temp("absent-legacy")), OK)
	assert_eq(migrated.life.minute, 1234.0)
	assert_eq(_normalized(migrated.memory.to_save_data()), _fixture("memory_only_legacy"))
	DirAccess.remove_absolute(legacy)
	DirAccess.remove_absolute(save.path)

func test_invalid_and_future_fixtures_are_rejected_and_leave_loaded_state_unchanged() -> void:
	for name: String in ["invalid_schema", "future_version"]:
		var save: NpcWorldSave = _load("v1_town")
		var before: Dictionary = save.to_data()
		assert_false(save.from_data(_fixture(name)), name)
		assert_eq(save.to_data(), before, name + " mutated a loaded save")
		var path: String = _temp(name)
		_write_text(path, _text(name))
		var from_disk: NpcWorldSave = _load("v1_town")
		from_disk.path = path
		assert_eq(from_disk.load_file(_temp("absent-legacy")), ERR_FILE_CORRUPT, name)
		assert_eq(from_disk.to_data(), before)
		assert_eq(from_disk.save_file(), ERR_FILE_CORRUPT, name + " must not be overwritten")
		assert_eq(FileAccess.get_file_as_string(path), _text(name))
		DirAccess.remove_absolute(path)
