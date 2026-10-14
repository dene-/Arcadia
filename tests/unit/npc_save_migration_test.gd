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

# The per-NPC memory state a v1 source should keep, with the migration's documented defaults and
# the revision-2 rewrites: unappraised display entries point at their inbox evidence. Revision 3
# puts every legacy dialogue line, delivered and untimed, into the legacy session.
func _expected_state(id: String, state: Dictionary) -> Dictionary:
	var observations: Array = []
	for entry: Dictionary in state.get("observations", []):
		var expected: Dictionary = entry.duplicate(true)
		if entry.status in ["pending", "unavailable"]:
			expected.status = "pending"
			expected.observation_id = "%s:%s" % [id, entry.get("origin_id", "legacy:%s:%d" % [id, int(entry.id)])]
		observations.append(expected)
	var memories: Array = state.memories.duplicate(true)
	for entry: Dictionary in state.get("observations", []):
		if entry.status == "classified" and entry.sense == "hearing" and entry.kind != "combat_noise":
			for memory: Dictionary in memories:
				if memory.gist == entry.text:
					memory.sensory_cues = []
	var dialogue: Array = []
	for entry: Dictionary in state.recent_dialogue:
		dialogue.append(_legacy_dialogue(entry))
	return {"recent_dialogue": dialogue, "memories": memories,
		"recent_events": state.recent_events, "observations": observations,
		"next_observation_id": state.get("next_observation_id", 1),
		"heard_origins": state.get("heard_origins", {})}

func _legacy_dialogue(entry: Dictionary) -> Dictionary:
	var expected: Dictionary = entry.duplicate(true)
	expected.merge({"session_id": NpcSaveMigration.LEGACY_SESSION, "minute": -1.0, "delivered": true})
	return expected

# A legacy social line keeps its minute and names both participants from its owner and "with".
func _legacy_social(id: String, person: Dictionary) -> Array:
	var lines: Array = []
	for entry: Dictionary in person.recent_social:
		var expected: Dictionary = entry.duplicate(true)
		expected.merge({"session_id": NpcSaveMigration.LEGACY_SESSION, "speaker_id": id,
			"listener_id": entry.with, "delivered": true})
		lines.append(expected)
	return lines

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
			var decision: Variant = expected.get("decision")
			expected.erase("decision")
			if decision is Dictionary and not String(decision.get("commitment_id", "")).is_empty():
				expected.commitment_id = decision.commitment_id
			if not expected.has("safety"):
				expected.safety = {}
			expected.recent_social = _legacy_social(id, life.people[id])
			assert_eq(data.world.life.people[id], expected, name + " " + id)
		var memory: Dictionary = source.memory
		for key: String in ["turn", "world_minute", "next_memory_id"]:
			assert_eq(data.memory[key], memory[key], name + " " + key)
		assert_eq(data.memory.npcs.keys(), memory.npcs.keys(), name)
		for id: String in memory.npcs:
			assert_eq(data.memory.npcs[id], _expected_state(id, memory.npcs[id]), name + " " + id)
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
	for id: String in deaths.deaths.ids():
		var entry: Dictionary = deaths.deaths.snapshot(id)
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
	assert_eq(statuses, ["pending", "pending", "classified", "classified"],
		"Unavailable entries are unassessed context again; the inbox owns the retry.")
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
			assert_eq(save.memory.minds.get_mind(id).relationships.get_relationship("player"), relationship, name + " " + id)
		for id: String in source.world.life.people:
			var ties: Dictionary = source.world.life.people[id].ties
			var subjects: Dictionary = minds.get(id, {"relationships": {"subjects": {}}}).relationships.subjects
			assert_eq(subjects.size(), ties.size() + int(source.memory.npcs.has(id)), name + " " + id)
			for other: String in ties:
				for key: String in TIE_KEYS:
					assert_eq(subjects[other][key], ties[other][key], name + " " + id + " " + other)
				for key: String in ["respect", "fear", "suspicion"]:
					assert_eq(subjects[other][key], 0.0, name + " " + id + " " + other)
			for other: String in ties:
				var saved: Dictionary = save.minds.get_mind(id).relationships.get_relationship(other)
				for key: String in TIE_KEYS:
					assert_eq(saved[key], ties[other][key], name + " " + id + " " + other)
		for id: String in minds:
			var mind: Dictionary = minds[id]
			assert_eq(mind.relationships.receipts, [], name + " " + id)
			assert_eq(mind.commitments, {"next_id": 1, "items": []}, name + " " + id)
			assert_eq(mind.version, NpcMindState.SCHEMA_VERSION, name + " " + id)
			assert_eq(mind.condition, {}, name + " " + id)
			assert_eq(mind.task, {}, name + " " + id)
			assert_eq(mind.knowledge, NpcKnowledge.new().to_data(), name + " " + id)
			if not name == "v1_observations":
				assert_eq(mind.evidence, NpcEvidenceInbox.new().to_data(), name + " " + id)
			assert_eq(mind.decision_sequence, 0, name + " " + id)
			var loaded: NpcMindState = save.minds.get_mind(id)
			assert_eq(loaded.needs, NpcMindState.neutral_needs(loaded.tuning), name + " " + id)
			assert_eq(loaded.emotion_causes(0.0), [] as Array[Dictionary], name + " " + id)

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
		assert_eq(data.memory.npcs[id], _expected_state(id, source.npcs[id]), id)
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

func _evidence_of(data: Dictionary, id: String) -> Dictionary:
	var items: Dictionary = {}
	for item: Dictionary in data.minds.minds[id].evidence.items:
		items[item.observation.observation_id] = item
	return items

func test_unappraised_observations_become_inbox_evidence_and_classified_ones_do_not() -> void:
	var data: Dictionary = _migrated("v1_observations")
	var items: Dictionary = _evidence_of(data, "holt_partner")
	assert_eq(items.keys(), ["holt_partner:world:3", "holt_partner:world:4"])
	var pending: Dictionary = items["holt_partner:world:3"]
	assert_eq(pending.status, "PENDING")
	assert_eq(pending.attempts, 0)
	assert_eq(pending.observation.kind, "stranger_seen")
	assert_eq(pending.observation.modality, "SIGHT")
	assert_eq(pending.observation.observed_minute, 3451.0)
	assert_eq(pending.observation.space_id, "outdoors")
	assert_eq(pending.observation.participants, [], "No participants are invented.")
	var deferred: Dictionary = items["holt_partner:world:4"]
	assert_eq(deferred.status, "DEFERRED")
	assert_eq(deferred.attempts, 1)
	assert_eq(deferred.last_error, "legacy_unavailable")
	var save: NpcWorldSave = _loaded(data)
	var inbox: NpcEvidenceInbox = save.minds.get_mind("holt_partner").evidence
	assert_eq(inbox.ready_count(save.life.minute), 2, "Both are ready at the first retry.")
	for origin: String in ["world:5", "world:6"]:
		assert_false(inbox.contains_pending("holt_partner:" + origin), origin)
	var entries: Array = save.memory.snapshot("holt_partner").observations
	assert_eq(entries[0].observation_id, "holt_partner:world:3")
	assert_eq(entries[1].observation_id, "holt_partner:world:4")
	assert_false(entries[2].has("observation_id"))
	assert_eq(entries[2].status, "classified")

func test_only_fixtures_with_unappraised_entries_get_evidence() -> void:
	for name: String in V1:
		if name == "v1_observations":
			continue
		for id: String in _migrated(name).minds.minds:
			assert_eq(_migrated(name).minds.minds[id].evidence, NpcEvidenceInbox.new().to_data(), name + " " + id)

func test_reported_body_memory_loses_the_fighting_cue_but_combat_noise_keeps_it() -> void:
	var data: Dictionary = _migrated("v1_observations")
	var cues: Dictionary = {}
	for memory: Dictionary in data.memory.npcs.holt_partner.memories:
		cues[memory.id] = memory.sensory_cues
	assert_eq(cues["mem:5"], [], "A heard body report is not the sound of fighting.")
	assert_eq(cues["mem:6"], [])
	var source: Dictionary = _fixture("v1_observations")
	source.memory.npcs.holt_partner.observations[2].kind = "combat_noise"
	var noisy: Dictionary = NpcSaveMigration.upgrade(source)
	assert_true(noisy.ok)
	for memory: Dictionary in noisy.data.memory.npcs.holt_partner.memories:
		if memory.id == "mem:5":
			assert_eq(memory.sensory_cues, ["sounds of fighting"])

# A revision-2 root: dialogue and social history have no session fields yet.
func _revision_two(data: Dictionary) -> Dictionary:
	var r2: Dictionary = data.duplicate(true)
	r2.migration.revision = 2
	for state: Dictionary in r2.memory.npcs.values():
		for entry: Dictionary in state.recent_dialogue:
			for key: String in ["session_id", "minute", "delivered"]:
				entry.erase(key)
	for person: Dictionary in r2.world.life.people.values():
		for entry: Dictionary in person.recent_social:
			for key: String in ["session_id", "speaker_id", "listener_id", "delivered"]:
				entry.erase(key)
	return r2

func _downgraded(data: Dictionary) -> Dictionary:
	var r1: Dictionary = _revision_two(data)
	r1.migration.revision = 1
	for mind: Dictionary in r1.minds.minds.values():
		mind.version = 1
		mind.knowledge = {}
		mind.erase("evidence")
	return r1

func test_revision_one_roots_upgrade_to_the_current_revision() -> void:
	var current: Dictionary = _migrated("v1_town")
	var r1: Dictionary = _downgraded(current)
	assert_false(NpcWorldSave.new().from_data(r1), "A revision-1 root is not loadable as is.")
	var result: Dictionary = NpcSaveMigration.upgrade(r1)
	assert_true(result.ok, str(result.error))
	assert_eq(result.data, current)
	assert_eq(result.data.migration.revision, NpcSaveMigration.REVISION)
	var zero: Dictionary = _downgraded(current)
	zero.migration.revision = 0
	assert_eq(NpcSaveMigration.upgrade(zero).error, "invalid_source")

func test_revision_two_history_joins_the_legacy_session() -> void:
	var current: Dictionary = _migrated("v1_town")
	assert_eq(current.migration.revision, 3)
	var r2: Dictionary = _revision_two(current)
	assert_false(NpcWorldSave.new().from_data(r2), "History without sessions is not loadable as is.")
	var result: Dictionary = NpcSaveMigration.upgrade(r2)
	assert_true(result.ok, str(result.error))
	assert_eq(result.data, current)
	var line: Dictionary = result.data.memory.npcs.garrin_holt.recent_dialogue[0]
	assert_eq([line.session_id, line.minute, line.delivered], ["legacy", -1.0, true])
	var social: Dictionary = result.data.world.life.people.garrin_holt.recent_social[0]
	assert_eq([social.session_id, social.speaker_id, social.listener_id, social.delivered, social.minute],
		["legacy", "garrin_holt", "holt_partner", true, 3435.0])
	var broken: Dictionary = _revision_two(current)
	broken.world.life.people.garrin_holt.recent_social = [7]
	assert_eq(NpcSaveMigration.upgrade(broken).error, "invalid_source")

func test_revision_one_display_entries_use_saved_space_and_legacy_origin() -> void:
	var r1: Dictionary = _downgraded(_migrated("v1_town"))
	var state: Dictionary = r1.memory.npcs.garrin_holt
	state.observations = [
		{"id": 1, "text": "I heard a shout.", "sense": "hearing", "player_involved": false,
			"status": "unavailable", "created_at": 10.0, "decision": {}, "world_minute": 500.0},
		{"id": 2, "text": "I saw smoke.", "sense": "sight", "player_involved": false,
			"status": "pending", "created_at": 11.0, "decision": {}, "kind": "smoke_seen",
			"origin_id": "world:9"}]
	state.next_observation_id = 3
	r1.world.life.people.garrin_holt.space = "holt_house"
	var result: Dictionary = NpcSaveMigration.upgrade(r1)
	assert_true(result.ok, str(result.error))
	var items: Dictionary = _evidence_of(result.data, "garrin_holt")
	assert_eq(items.keys(), ["garrin_holt:legacy:garrin_holt:1", "garrin_holt:world:9"])
	var shout: Dictionary = items["garrin_holt:legacy:garrin_holt:1"]
	assert_eq(shout.status, "DEFERRED")
	assert_eq(shout.observation.modality, "NOISE")
	assert_eq(shout.observation.observed_minute, 500.0)
	assert_eq(shout.observation.space_id, "holt_house")
	var smoke: Dictionary = items["garrin_holt:world:9"]
	assert_eq(smoke.observation.observed_minute, r1.memory.world_minute)
	assert_eq(NpcSaveMigration.upgrade(result.data).data, result.data)

func test_entries_that_cannot_become_evidence_fail_the_migration() -> void:
	var r1: Dictionary = _downgraded(_migrated("v1_town"))
	r1.memory.npcs.garrin_holt.observations = [{"id": 1, "text": "x", "sense": "sight",
		"player_involved": false, "status": "pending", "created_at": 1.0, "decision": {},
		"kind": "k".repeat(NpcObservation.MAX_KIND_LENGTH + 1)}]
	r1.memory.npcs.garrin_holt.next_observation_id = 2
	assert_eq(NpcSaveMigration.upgrade(r1).error, "invalid_source")
