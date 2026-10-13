extends "res://tests/test_case.gd"

## Acceptance for the pure v1 -> v2 save migration, driven by the synthetic M0 legacy fixtures.
const DIR: String = "res://tests/fixtures/cognition/"
const V1: Array[String] = ["v1_empty", "v1_town", "v1_town_rerolled", "v1_deaths", "v1_observations",
	"v1_rumors", "v1_prospective", "v1_missing_optional"]
const MEMORY_KEYS: Array[String] = ["recent_dialogue", "memories", "recent_events", "observations",
	"next_observation_id", "heard_origins"]
const TIE_KEYS: Array[String] = ["familiarity", "trust", "affection"]

func _fixture(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DIR + name + ".json")) as Dictionary

func _migrated(name: String) -> Dictionary:
	var result: Dictionary = NpcSaveMigration.upgrade(_fixture(name))
	assert_true(result.ok, name + " failed to migrate: " + str(result.error))
	return result.data

func _loaded(data: Dictionary) -> NpcWorldSave:
	var save := NpcWorldSave.new()
	assert_true(save.from_data(data))
	return save

# The per-NPC memory state a v1 source should keep, with the migration's documented defaults.
func _expected_state(state: Dictionary) -> Dictionary:
	return {"recent_dialogue": state.recent_dialogue, "memories": state.memories,
		"recent_events": state.recent_events, "observations": state.get("observations", []),
		"next_observation_id": state.get("next_observation_id", 1),
		"heard_origins": state.get("heard_origins", {})}

func test_every_v1_fixture_migrates_to_a_valid_current_v2_root() -> void:
	for name: String in V1:
		var result: Dictionary = NpcSaveMigration.upgrade(_fixture(name))
		assert_true(result.ok, name)
		assert_eq(result.error, "", name)
		assert_eq(result.data.version, 2, name)
		assert_eq(result.data.migration, {"source_version": NpcSaveMigration.SOURCE_WORLD_V1,
			"source_digest": "", "revision": NpcSaveMigration.REVISION}, name)
		assert_eq(result.data.memory.version, 2, name)
		assert_eq(result.data.world.life.version, 2, name)
		assert_eq(int(result.data.world.life.next_social_receipt), 1, name)
		assert_true(NpcWorldSave.new().from_data(result.data), name)

func test_world_and_memory_inventories_are_preserved() -> void:
	for name: String in V1:
		var source: Dictionary = _fixture(name)
		var data: Dictionary = _migrated(name)
		var world: Dictionary = source.world
		assert_eq(data.world.dead_npcs, world.dead_npcs, name)
		assert_eq(data.world.region_seed, int(world.get("region_seed", 0)), name)
		assert_eq(data.world.npc_seed, int(world.get("npc_seed", 0)), name)
		for key: String in ["population", "economy", "justice"]:
			assert_eq(data.world[key], world[key], name + " " + key)
		assert_eq(data.world.deaths, {"version": 1, "records": world.deaths}, name)
		var life: Dictionary = world.life
		assert_eq(data.world.life.minute, life.minute, name)
		assert_eq(data.world.life.next_event, life.next_event, name)
		assert_eq(data.world.life.personalities, life.get("personalities", {}), name)
		assert_eq(data.world.life.rumors, {"version": 1, "known": life.rumors}, name)
		assert_eq(data.world.life.people.keys(), life.people.keys(), name)
		for id: String in life.people:
			var expected: Dictionary = life.people[id].duplicate(true)
			expected.erase("ties")
			if not expected.has("safety"):
				expected.safety = {}
			assert_eq(data.world.life.people[id], expected, name + " " + id)
		var memory: Dictionary = source.memory
		for key: String in ["turn", "world_minute", "next_memory_id"]:
			assert_eq(data.memory[key], memory[key], name + " " + key)
		assert_eq(data.memory.npcs.keys(), memory.npcs.keys(), name)
		for id: String in memory.npcs:
			assert_eq(data.memory.npcs[id], _expected_state(memory.npcs[id]), name + " " + id)
			assert_eq(data.memory.npcs[id].memories.size(), memory.npcs[id].memories.size(), name + " " + id)

func test_specific_fixture_facts_survive_migration() -> void:
	var town: NpcWorldSave = _loaded(_migrated("v1_town"))
	assert_eq(town.npc_seed, 0)
	assert_eq(town.get_npc_seed(), 274415)
	assert_eq(town.population.people.size(), 33)
	var total: int = town.economy.treasury
	for coins: int in town.economy.accounts.values():
		total += coins
	assert_eq(total, 6000 + 12 * 120)
	assert_eq(town.justice.current("voss_guard", "player", town.life.minute).status, "warning")
	var rerolled: NpcWorldSave = _loaded(_migrated("v1_town_rerolled"))
	assert_eq(rerolled.npc_seed, 918273)
	assert_eq(rerolled.life.personality_for("mirelle_voss", rerolled.get_npc_seed()),
		_fixture("v1_town_rerolled").world.life.personalities.mirelle_voss)
	var deaths: NpcWorldSave = _loaded(_migrated("v1_deaths"))
	var stages: Array = []
	for id: String in deaths.deaths.records:
		var entry: Dictionary = deaths.deaths.records[id]
		stages.append(entry.stage)
		assert_true(deaths.is_dead(StringName(id)))
		if entry.stage in ["reported", "recovering", "carried", "buried"]:
			assert_false(entry.reporter.is_empty() or entry.guard.is_empty(), entry.stage)
	stages.sort()
	var all_stages: Array = Array(TownDeaths.STAGES).duplicate()
	all_stages.sort()
	assert_eq(stages, all_stages)
	var observations: NpcWorldSave = _loaded(_migrated("v1_observations"))
	var statuses: Array = observations.memory.snapshot("holt_partner").observations.map(
		func(observation: Dictionary) -> String: return observation.status)
	assert_eq(statuses, ["pending", "unavailable", "classified", "classified"])
	var rumors: NpcWorldSave = _loaded(_migrated("v1_rumors"))
	assert_eq(rumors.memory.to_save_data().npcs.holt_partner.heard_origins.size(), 2)
	assert_eq(rumors.life.rumors.get_known("garrin_holt", rumors.life.minute)[0].chain,
		["bram_edevane", "sella_rowan", "garrin_holt"])
	var prospective: NpcWorldSave = _loaded(_migrated("v1_prospective"))
	var intentions: Array = prospective.memory.snapshot("garrin_holt").memories.filter(
		func(memory: Dictionary) -> bool: return memory.type == "prospective")
	assert_eq(intentions.map(func(memory: Dictionary) -> bool: return memory.completed).count(true), 1)
	assert_eq(intentions.size(), 2)
	assert_true(prospective.minds.get_mind("garrin_holt").commitments.to_data().items.is_empty(),
		"Prospective memories are not turned into commitments.")

func test_relationships_move_into_the_mind_store() -> void:
	for name: String in V1:
		var source: Dictionary = _fixture(name)
		var data: Dictionary = _migrated(name)
		var save: NpcWorldSave = _loaded(data)
		var minds: Dictionary = data.minds.minds
		for id: String in source.memory.npcs:
			var relationship: Dictionary = source.memory.npcs[id].relationship
			assert_eq(minds[id].relationships.subjects.player, relationship, name + " " + id)
			assert_eq(save.memory.snapshot(id).relationship, relationship, name + " " + id)
		for id: String in source.world.life.people:
			var ties: Dictionary = source.world.life.people[id].ties
			var subjects: Dictionary = minds.get(id, {"relationships": {"subjects": {}}}).relationships.subjects
			assert_eq(subjects.size(), ties.size() + int(source.memory.npcs.has(id)), name + " " + id)
			for other: String in ties:
				for key: String in TIE_KEYS:
					assert_eq(subjects[other][key], ties[other][key], name + " " + id + " " + other)
				for key: String in ["respect", "fear", "suspicion"]:
					assert_eq(subjects[other][key], 0.0, name + " " + id + " " + other)
			assert_eq(save.life.get_person(id).ties, ties, name + " " + id)
		for id: String in minds:
			var mind: Dictionary = minds[id]
			assert_eq(mind.relationships.receipts, [], name + " " + id)
			assert_eq(mind.commitments, {"next_id": 1, "items": []}, name + " " + id)
			for key: String in ["condition", "knowledge", "task"]:
				assert_eq(mind[key], {}, name + " " + id)
			assert_eq(mind.decision_sequence, 0, name + " " + id)

func test_upgrade_is_deterministic_idempotent_and_never_mutates_the_source() -> void:
	for name: String in V1 + ["memory_only_legacy"]:
		var source: Dictionary = _fixture(name)
		var first: Dictionary = NpcSaveMigration.upgrade(source)
		var second: Dictionary = NpcSaveMigration.upgrade(source)
		assert_eq(source, _fixture(name), name + " source was mutated")
		assert_eq(first, second, name)
		var again: Dictionary = NpcSaveMigration.upgrade(first.data)
		assert_true(again.ok, name)
		assert_eq(again.data, first.data, name)

func test_missing_optional_keys_get_defaults() -> void:
	var source: Dictionary = _fixture("v1_missing_optional")
	assert_false(source.world.has("npc_seed"))
	assert_false(source.world.life.has("personalities"))
	var data: Dictionary = _migrated("v1_missing_optional")
	assert_eq(data.world.npc_seed, 0)
	assert_eq(data.world.life.personalities, {})
	for person: Dictionary in data.world.life.people.values():
		assert_eq(person.safety, {})
	for state: Dictionary in data.memory.npcs.values():
		assert_eq(state.observations, [])
		assert_eq(state.next_observation_id, 1)
		assert_eq(state.heard_origins, {})
	var complete: Dictionary = _fixture("v1_town")
	complete.world.npc_seed = 0
	complete.world.life.personalities = {}
	for person: Dictionary in complete.world.life.people.values():
		person.safety = {}
	for state: Dictionary in complete.memory.npcs.values():
		state.observations = []
		state.next_observation_id = 1
		state.heard_origins = {}
	assert_eq(data, NpcSaveMigration.upgrade(complete).data, "Defaults equal the explicit values.")
	var save: NpcWorldSave = _loaded(data)
	assert_eq(save.life.personality_for("sella_rowan", save.get_npc_seed()).voice,
		NpcTemperament.generate(274415, "sella_rowan").voice, "Missing personalities regenerate.")

func test_memory_only_source_becomes_an_empty_world_at_its_clock() -> void:
	var source: Dictionary = _fixture("memory_only_legacy")
	var data: Dictionary = _migrated("memory_only_legacy")
	assert_eq(data.migration.source_version, NpcSaveMigration.SOURCE_MEMORY_ONLY)
	assert_eq(data.world.life.minute, 1234.0)
	assert_eq(data.memory.world_minute, 1234.0)
	assert_eq(data.world.dead_npcs, [])
	assert_eq(data.world.region_seed, 0)
	assert_eq(data.world.population, TownPopulation.new().to_data())
	assert_eq(data.world.life.people, {})
	for id: String in source.npcs:
		assert_eq(data.memory.npcs[id], _expected_state(source.npcs[id]), id)
		assert_eq(data.minds.minds[id].relationships.subjects, {"player": source.npcs[id].relationship}, id)
	var save: NpcWorldSave = _loaded(data)
	assert_eq(save.life.minute, 1234.0)

func test_invalid_unsupported_and_future_sources_fail_without_partial_data() -> void:
	var cases: Dictionary = {"invalid_schema": "invalid_candidate", "future_version": "unsupported_version"}
	for name: String in cases:
		var source: Dictionary = _fixture(name)
		var result: Dictionary = NpcSaveMigration.upgrade(source)
		assert_eq(result, {"ok": false, "data": {}, "error": cases[name]}, name)
		assert_eq(source, _fixture(name), name + " source was mutated")
	assert_eq(NpcSaveMigration.upgrade({}).error, "unsupported_version")
	assert_eq(NpcSaveMigration.upgrade({"version": 1}).error, "unsupported_version")
	var future: Dictionary = _migrated("v1_town")
	future.migration.revision = NpcSaveMigration.REVISION + 1
	assert_eq(NpcSaveMigration.upgrade(future), {"ok": false, "data": {}, "error": "future_revision"})
	var extra: Dictionary = _fixture("v1_town")
	extra.memory.npcs.garrin_holt.mood = "unknown"
	assert_eq(NpcSaveMigration.upgrade(extra).error, "invalid_source", "Unknown memory keys are not dropped.")

func test_digest_is_the_sha256_of_the_source_text() -> void:
	var text: String = FileAccess.get_file_as_string(DIR + "v1_town.json")
	assert_eq(NpcSaveMigration.digest(text), text.sha256_text())
	assert_eq(NpcSaveMigration.digest(text).length(), 64)
