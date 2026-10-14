extends "res://tests/test_case.gd"

func test_seeded_personality_is_saved_and_not_rerolled_each_day() -> void:
	var state := TownLifeState.new()
	var first: Dictionary = state.personality_for("garrin", 42)
	assert_eq(first, state.personality_for("garrin", 99))
	assert_ne(first, state.personality_for("mirelle", 42))
	assert_ne(first, NpcTemperament.generate(43, "garrin"))
	state.advance(1440)
	assert_eq(first, state.personality_for("garrin", 42))
	var loaded := TownLifeState.new()
	assert_true(loaded.from_data(JSON.parse_string(JSON.stringify(state.to_data()))))
	var restored: Dictionary = loaded.personality_for("garrin", 99)
	assert_eq(first.personality, restored.personality)
	for tendency: String in first.traits:
		assert_true(is_equal_approx(first.traits[tendency], restored.traits[tendency]))

func test_sleep_duration_cannot_extend_past_breakfast_or_next_day() -> void:
	var state := TownLifeState.new()
	state.ensure_person("a", 42, ["a"], ["square"])
	var breakfast: float = state.get_person("a").plan[1].minute
	state.minute = breakfast - 1
	state.select_activity("a", {"kind": "rest", "place": "home:a"}, 90, {})
	assert_eq(state.get_person("a").until, breakfast)
	state.minute = 1439
	state.select_activity("a", {"kind": "rest", "place": "home:a"}, 90, {})
	assert_eq(state.get_person("a").until, 1440.0)

func test_daily_plans_change_by_person_and_day_and_local_knowledge_is_asymmetric() -> void:
	var state := TownLifeState.new()
	state.ensure_person("a", 123, ["a", "b", "c"], ["square", "garden"])
	state.ensure_person("b", 123, ["a", "b", "c"], ["square", "garden"])
	var person: Dictionary = state.get_person("a")
	assert_eq(person.ties.size(), 2)
	assert_ne(person.ties.b, state.get_person("b").ties.a)
	assert_ne(person.plan, state.get_person("b").plan)
	assert_eq(person.plan, NpcRoutinePlan.generate(123, "a", 0, ["square", "garden"]))
	state.advance(1440)
	state.ensure_person("a", 123, ["a", "b", "c"], ["square", "garden"])
	assert_ne(person.plan, state.get_person("a").plan)
	assert_eq(person.ties, state.get_person("a").ties)

func test_seeded_ties_reproduce_the_same_numbers_and_family_overrides_residents() -> void:
	var state := TownLifeState.new()
	state.ensure_person("a", 123, ["a", "b", "c"], ["square"])
	var random := NpcRoutinePlan.random_for(123, "a:social")
	var ties: Dictionary = state.get_person("a").ties
	assert_eq(ties.keys(), ["b", "c"])
	assert_eq(ties.b.familiarity, random.randf_range(0.45, 0.95))
	assert_eq(ties.b.trust, random.randf_range(-0.25, 0.65))
	assert_eq(ties.b.affection, random.randf_range(-0.4, 0.7))
	assert_eq(ties.c.familiarity, random.randf_range(0.45, 0.95))
	state.ensure_person("a", 123, ["a", "b", "c", "d"], ["square"])
	var late: Dictionary = state.get_person("a").ties
	assert_eq(late.b, ties.b)
	var late_random := NpcRoutinePlan.random_for(123, "a:tie:d")
	assert_eq(late.d.familiarity, late_random.randf_range(0.45, 0.95))
	var graph: NpcRelationshipGraph = state.minds.get_mind("a").relationships
	assert_true(graph.seed_relationship("b", {"familiarity": 1.0, "trust": 0.5, "affection": 0.5}, true))
	assert_eq(state.get_person("a").ties.b, {"familiarity": 1.0, "trust": 0.5, "affection": 0.5})
	assert_false(state.get_person("a").ties.has("player"))

func test_social_exchange_changes_known_ties_once_per_receipt_and_survives_save() -> void:
	var state := TownLifeState.new()
	state.ensure_person("a", 123, ["a", "b"], ["square"])
	var before: Dictionary = state.get_person("a").ties.b
	state.remember_exchange("a", "b", "Hello", "social:1", "a", "b")
	var after: Dictionary = state.get_person("a").ties.b
	assert_true(is_equal_approx(after.familiarity, minf(1.0, before.familiarity + 0.02)))
	assert_eq(after.affection, before.affection)
	assert_eq(after.trust, before.trust)
	state.remember_exchange("a", "stranger", "Hello", "social:2", "a", "stranger")
	assert_false(state.get_person("a").ties.has("stranger"))
	state.remember_exchange("a", "b", "Again", "social:3", "b", "a")
	var data: Dictionary = JSON.parse_string(JSON.stringify(state.to_data()))
	assert_eq(data.version, 2)
	assert_eq(int(data.next_social_receipt), 4)
	assert_false(data.people.a.has("ties"))
	var last: Dictionary = data.people.a.recent_social[-1]
	assert_eq([last.session_id, last.speaker_id, last.listener_id, last.delivered],
		["social:3", "b", "a", true])
	var loaded := TownLifeState.new()
	assert_true(loaded.minds.from_data(JSON.parse_string(JSON.stringify(state.minds.to_data()))))
	assert_true(loaded.from_data(data))
	for key: String in ["familiarity", "trust", "affection"]:
		assert_true(is_equal_approx(loaded.get_person("a").ties.b[key], state.get_person("a").ties.b[key]))
	loaded.remember_exchange("a", "b", "Third", "social:4", "a", "b")
	var receipts: Array = loaded.minds.get_mind("a").relationships.to_data().receipts
	assert_eq(receipts, ["social:a:b:1", "social:a:b:3", "social:a:b:4"])

func test_life_data_rejects_v1_shapes() -> void:
	var state := TownLifeState.new()
	state.ensure_person("a", 123, ["a", "b"], ["square"])
	var data: Dictionary = state.to_data()
	var restored := TownLifeState.new()
	var broken: Dictionary = data.duplicate(true)
	broken.version = 1
	assert_false(restored.from_data(broken))
	broken = data.duplicate(true)
	broken.people.a.ties = {}
	assert_false(restored.from_data(broken))
	broken = data.duplicate(true)
	broken.people.a.erase("safety")
	assert_false(restored.from_data(broken))
	broken = data.duplicate(true)
	broken.erase("next_social_receipt")
	assert_false(restored.from_data(broken))
	state.remember_exchange("a", "b", "Hello", "social:1", "a", "b")
	data = state.to_data()
	for key: String in ["session_id", "speaker_id", "listener_id", "delivered"]:
		broken = data.duplicate(true)
		broken.people.a.recent_social[0].erase(key)
		assert_false(restored.from_data(broken), key)
	assert_true(restored.from_data(data))

func _event(id: String = "event:1") -> Dictionary:
	return {"origin_id": id, "text": "I saw Den hurt Garrin.", "sense": "sight", "player_involved": true}

func _policy() -> Dictionary:
	return {"remember": true, "importance": 0.8, "belief": 0.7, "affinity": 0.0,
		"dispositions": {"player": {"trust": -0.03}}}

func test_rumors_keep_provenance_do_not_loop_or_amplify_confidence() -> void:
	var rumors := TownRumors.new()
	rumors.observe("a", "Mirelle", _event(), _policy(), 500)
	var topic: Dictionary = rumors.candidates("a", "b", 500)[0]
	var heard: Dictionary = rumors.hear("b", "a", "Mirelle", topic, _policy(), 501)
	assert_eq(heard.hops, 1)
	assert_eq(heard.originator, "a")
	assert_eq(heard.confidence, 0.7)
	assert_true(rumors.candidates("b", "a", 502).is_empty())
	var policy: Dictionary = _policy()
	policy.belief = 0.99
	var twice: Dictionary = rumors.hear("c", "b", "Lysa", heard, policy, 502)
	assert_eq(twice.confidence, 0.7)
	assert_eq(twice.source_id, "b")
	assert_eq(twice.originator, "a")
	assert_eq(twice.chain, ["a", "b", "c"])
	assert_true(rumors.hear("c", "a", "Mirelle", topic, policy, 503).is_empty())
	assert_true(rumors.hear("d", "unknown", "Nobody", topic, policy, 503).is_empty())
	assert_true(rumors.get_known("nobody", 503).is_empty())
	var clone := TownRumors.new()
	assert_true(clone.from_data(rumors.to_data()))
	assert_eq(clone.get_known("c", 504), rumors.get_known("c", 504))

func test_transient_news_expires_and_eyewitness_perception_can_replace_hearsay() -> void:
	var rumors := TownRumors.new()
	var policy: Dictionary = _policy()
	policy.remember = false
	rumors.observe("a", "Mirelle", _event(), policy, 500)
	var topic: Dictionary = rumors.candidates("a", "b", 500)[0]
	rumors.hear("b", "a", "Mirelle", topic, policy, 501)
	assert_true(rumors.get_known("b", 681).is_empty())
	rumors.observe("b", "Lysa", _event(), _policy(), 502)
	assert_eq(rumors.get_known("b", 681)[0].hops, 0)
	assert_eq(rumors.get_known("b", 681)[0].originator, "b")

func test_world_save_round_trips_life_and_rejects_corruption_atomically() -> void:
	var save := NpcWorldSave.new()
	save.region_seed = 42
	save.life.ensure_person("a", 42, ["a", "b"], ["square"])
	save.life.remember_position("a", Vector2(4096, 4096), "home:a")
	save.life.personality_for("a", 42)
	save.life.rumors.observe("a", "Mirelle", _event(), _policy(), save.life.minute)
	save.mark_dead(&"b")
	var loaded := NpcWorldSave.new()
	assert_true(loaded.from_data(JSON.parse_string(JSON.stringify(save.to_data()))))
	assert_eq(loaded.life.get_person("a").plan,
		JSON.parse_string(JSON.stringify(save.life.get_person("a").plan)))
	assert_eq(loaded.life.rumors.get_known("a", 480)[0].text, _event().text)
	assert_eq(loaded.life.get_person("a").space, "home:a")
	var data: Dictionary = save.to_data()
	data.world.life.minute = -1
	assert_false(loaded.from_data(data))
	assert_eq(loaded.life.minute, 480.0)
	assert_true(loaded.is_dead(&"b"))
	data = save.to_data()
	data.world.erase("life")
	assert_false(loaded.from_data(data))
	assert_eq(loaded.life.get_person("a").space, "home:a")
	assert_true(loaded.is_dead(&"b"))

func test_hearsay_enters_memory_with_source_and_player_identity_is_explicit() -> void:
	var profile := NpcProfile.new()
	profile.npc_id = &"listener"
	var rumors := TownRumors.new()
	rumors.observe("a", "Mirelle", _event(), _policy(), 500)
	var account: Dictionary = rumors.hear("listener", "a", "Mirelle",
		rumors.candidates("a", "listener", 500)[0], _policy(), 501)
	var memory := NpcMemoryStore.new()
	memory.record_hearsay(profile, account, _policy())
	memory.record_hearsay(profile, account, _policy())
	var state: Dictionary = memory.snapshot("listener")
	assert_eq(state.memories.size(), 1)
	assert_eq(state.memories[0].source, "hearsay")
	assert_eq(state.relationship.trust, -0.03)
	assert_true(state.memories[0].gist.contains("Mirelle told me"))
	assert_eq(preload("res://game/resources/actors/player_data.tres").social_identity(),
		{"id": "player", "name": "Den", "sex": "Male"})

func test_forgotten_hearsay_cannot_repeat_its_trust_penalty_after_save() -> void:
	var profile := NpcProfile.new()
	profile.npc_id = &"listener"
	var rumors := TownRumors.new()
	rumors.observe("a", "Mirelle", _event(), _policy(), 500)
	var account: Dictionary = rumors.hear("listener", "a", "Mirelle",
		rumors.candidates("a", "listener", 500)[0], _policy(), 501)
	var policy: Dictionary = _policy()
	policy.remember = false
	var memory := NpcMemoryStore.new()
	memory.record_hearsay(profile, account, policy)
	assert_true(memory.snapshot("listener").memories.is_empty())
	assert_eq(memory.snapshot("listener").relationship.trust, -0.03)
	var loaded := NpcMemoryStore.new()
	assert_true(loaded.minds.from_data(JSON.parse_string(JSON.stringify(memory.minds.to_data()))))
	assert_true(loaded.from_save_data(JSON.parse_string(JSON.stringify(memory.to_save_data()))))
	loaded.record_hearsay(profile, account, policy)
	assert_eq(loaded.snapshot("listener").relationship.trust, -0.03)

func test_weak_accounts_cannot_change_trust_even_with_an_inconsistent_policy() -> void:
	var profile := NpcProfile.new()
	profile.npc_id = &"listener"
	var rumors := TownRumors.new()
	var event: Dictionary = _event()
	event.basis = "player_claim"
	rumors.observe("a", "Mirelle", event, _policy(), 500)
	var topic: Dictionary = rumors.candidates("a", "listener", 500)[0]
	assert_eq(topic.confidence, 0.6)
	var account: Dictionary = rumors.hear("listener", "a", "Mirelle", topic, _policy(), 501)
	var memory := NpcMemoryStore.new()
	memory.record_hearsay(profile, account, _policy())
	assert_eq(memory.snapshot("listener").relationship.trust, 0.0)
	assert_eq(memory.snapshot("listener").memories[0].confidence, 0.6)

func test_hearsay_dispositions_pass_through_the_incident_budget() -> void:
	var profile := NpcProfile.new()
	profile.npc_id = &"listener"
	var rumors := TownRumors.new()
	rumors.observe("a", "Mirelle", _event(), _policy(), 500)
	var account: Dictionary = rumors.hear("listener", "a", "Mirelle",
		rumors.candidates("a", "listener", 500)[0], _policy(), 501)
	var policy: Dictionary = _policy()
	policy.dispositions = {"player": {"trust": -0.5, "fear": 0.5}}
	var memory := NpcMemoryStore.new()
	memory.record_hearsay(profile, account, policy)
	var relationship: Dictionary = memory.snapshot("listener").relationship
	assert_true(absf(relationship.trust + NpcIncidentBudget.MAX_CHANGE) < 0.0001, "trust %s" % relationship.trust)
	assert_true(absf(relationship.fear - NpcIncidentBudget.MAX_CHANGE) < 0.0001, "fear %s" % relationship.fear)
	var spent: Dictionary = memory.minds.get_mind("listener").incident_budget.spent("player", "event:1",
		NpcIncidentBudget.ORDINARY)
	assert_true(absf(float(spent.trust) - NpcIncidentBudget.MAX_CHANGE) < 0.0001, "spent %s" % [spent])

func test_weak_accounts_change_only_how_the_listener_sees_the_messenger() -> void:
	var profile := NpcProfile.new()
	profile.npc_id = &"listener"
	var rumors := TownRumors.new()
	var event: Dictionary = _event()
	event.basis = "player_claim"
	rumors.observe("a", "Mirelle", event, _policy(), 500)
	var account: Dictionary = rumors.hear("listener", "a", "Mirelle",
		rumors.candidates("a", "listener", 500)[0], _policy(), 501)
	assert_true(float(account.confidence) < 0.7)
	var policy: Dictionary = _policy()
	policy.dispositions = {"a": {"trust": -0.05}, "player": {"trust": -0.05}}
	var memory := NpcMemoryStore.new()
	memory.record_hearsay(profile, account, policy)
	var graph: NpcRelationshipGraph = memory.minds.get_mind("listener").relationships
	assert_true(absf(graph.get_relationship("a").trust + 0.05) < 0.0001)
	assert_false(graph.has_subject("player"))
	assert_eq(memory.snapshot("listener").relationship.trust, 0.0)

func test_expired_accounts_are_not_known_and_stale_assessments_cannot_transfer_new_text() -> void:
	var rumors := TownRumors.new()
	var policy: Dictionary = _policy()
	policy.remember = false
	rumors.observe("a", "Mirelle", _event(), policy, 500)
	assert_false(rumors.knows("a", "event:1", 681))
	var topic: Dictionary = rumors.candidates("a", "b", 500)[0]
	var updated: Dictionary = _event()
	updated.text = "I saw a different person."
	rumors.observe("a", "Mirelle", updated, policy, 501)
	assert_true(rumors.hear("b", "a", "Mirelle", topic, policy, 502).is_empty())

# --- Goal options, relative searches and grave visits (TownLife without a scene tree) ---

const Routine = preload("res://tests/unit/npc_routine_task_test.gd")
const SEEKER: String = "mirelle_voss"
const RELATIVE: String = "voss_nephew"
const WORLD_SEED: int = 274415

func _town(minute: float) -> TownLife:
	var town := TownLife.new()
	town.save_game = NpcWorldSave.new()
	town.save_game.region_seed = WORLD_SEED
	town.save_game.population.ensure_population(WORLD_SEED)
	var ids: Array[String] = [SEEKER, RELATIVE]
	for id: String in ids:
		town.save_game.life.ensure_person(id, WORLD_SEED, ids, ["square"] as Array[String])
		town._places["home:" + id] = {"label": id + " home", "position": Vector2(1, 1)}
		town._places["work:" + id] = {"label": id + " work", "position": Vector2(2, 2)}
	for place: String in ["square", "market", "garden"]:
		town._places[place] = {"label": place, "position": Vector2(3, 3)}
	town.save_game.life.minute = minute
	return town

func _open_check(town: TownLife, created: float = 0.0) -> String:
	var mind: NpcMindState = town.save_game.minds.get_mind(SEEKER)
	return mind.commitments.create(TownLife.CHECK_RELATIVE, [RELATIVE] as Array[String],
		["ev:worry"] as Array[String], created, -1.0, 0.7)

## The seeker is on the way to `place` for the commitment, as the goal choice records it.
func _searching(town: TownLife, commitment: String, place: String, kind: String = TownLife.CHECK_RELATIVE) -> void:
	town.save_game.life.select_activity(SEEKER, {"kind": kind, "place": place}, 30.0,
		{"commitment_id": commitment})

## A brain for the seeker with no task yet, driven by a fake actor and executor.
func _brain(town: TownLife, executor: Routine.FakeExecutor) -> NpcBrain:
	var brain := NpcBrain.new()
	var actor := Routine.FakeActor.new()
	executor.actor = actor
	brain.setup(SEEKER, town.save_game.minds.get_mind(SEEKER), actor, executor, town.tuning, 7)
	town._brains[SEEKER] = brain
	brain.advance(town.save_game.life.minute, 0.0)
	return brain

func _ids(options: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for option: Dictionary in options:
		ids.append(option.id)
	return ids

func test_commitment_options_exist_only_between_six_and_nine_in_the_evening() -> void:
	var plan: Dictionary = {"kind": "rest", "place": "home:" + SEEKER}
	var cases: Dictionary = {359.0: false, 360.0: true, 600.0: true, 1259.0: true, 1260.0: false, 1500.0: false}
	for minute: float in cases:
		var town: TownLife = _town(minute)
		_open_check(town)
		town.save_game.minds.get_mind(SEEKER).knowledge.record_sighting(RELATIVE, "outdoors",
			Vector2(10, 10), 5.0, "ev:seen")
		var options: Array[Dictionary] = town._options(SEEKER, plan)
		assert_eq("CHECK_RELATIVE" in _ids(options), cases[minute], "minute %d" % int(minute))
		assert_true("PLAN" in _ids(options))
		for option: Dictionary in options:
			if option.id == "CHECK_RELATIVE":
				assert_eq(option.subject, RELATIVE)
				assert_false(String(option.commitment_id).is_empty())
				assert_eq(option.place, "seen:" + RELATIVE, "the last seen place is searched first")
		town.free()

func test_search_visits_seen_then_home_then_work_defers_and_resumes_from_the_start() -> void:
	var town: TownLife = _town(600.0)
	var mind: NpcMindState = town.save_game.minds.get_mind(SEEKER)
	mind.knowledge.record_sighting(RELATIVE, "outdoors", Vector2(10, 10), 5.0, "ev:seen")
	var commitment: String = _open_check(town)
	var sequence: Array[String] = [TownLife.SEEN_PREFIX + RELATIVE, "home:" + RELATIVE, "work:" + RELATIVE]
	assert_eq(town._search_places(SEEKER, RELATIVE), sequence)
	var plan: Dictionary = {"kind": "rest", "place": "home:" + SEEKER}
	for step: int in range(sequence.size()):
		var offered: Array[Dictionary] = town._options(SEEKER, plan).filter(
			func(option: Dictionary) -> bool: return option.id == "CHECK_RELATIVE")
		assert_eq(offered.size(), 1, "step %d" % step)
		assert_eq(offered[0].place, sequence[step])
		_searching(town, commitment, offered[0].place)
		town._search_failed(SEEKER)
		var person: Dictionary = town.save_game.life.get_person(SEEKER)
		assert_false(person.decision.has("commitment_id"), "a stale routine never searches again")
		assert_eq(person.until, town.save_game.life.minute, "the finished stop is interrupted")
		assert_eq(person.decision.search, "%s:%d" % [commitment, step + 1])
	var deferred: Dictionary = town.save_game.life.search_for(SEEKER, commitment)
	assert_eq(deferred.step, 0)
	assert_eq(deferred.deferred_until, 600.0 + town.tuning.search_defer_minutes)
	assert_false("CHECK_RELATIVE" in _ids(town._options(SEEKER, plan)), "the search waits out its deferral")
	town.save_game.life.minute = deferred.deferred_until
	var resumed: Array[Dictionary] = town._options(SEEKER, plan).filter(
		func(option: Dictionary) -> bool: return option.id == "CHECK_RELATIVE")
	assert_eq(resumed.size(), 1, "after the deferral the search resumes")
	assert_eq(resumed[0].place, sequence[0], "from the first place again")
	assert_eq(mind.commitments.get_commitment(commitment).status, "open")
	town.free()

func test_a_search_without_a_known_sighting_starts_at_the_relatives_home() -> void:
	var town: TownLife = _town(600.0)
	_open_check(town)
	assert_eq(town._search_places(SEEKER, RELATIVE), ["home:" + RELATIVE, "work:" + RELATIVE] as Array[String])
	town.free()

func test_seeing_the_relative_completes_the_check_and_ends_the_search() -> void:
	var town: TownLife = _town(600.0)
	var mind: NpcMindState = town.save_game.minds.get_mind(SEEKER)
	var commitment: String = _open_check(town, 590.0)
	town.save_game.life.set_search(SEEKER, commitment, 1, 0.0)
	_searching(town, commitment, "home:" + RELATIVE)
	mind.knowledge.record_sighting(RELATIVE, "outdoors", Vector2(10, 10), 580.0, "ev:before")
	var brain: NpcBrain = _brain(town, Routine.FakeExecutor.new())
	town._maintain_commitments(SEEKER)
	assert_eq(mind.commitments.get_commitment(commitment).status, "open",
		"a sighting from before the worry does not count")
	mind.knowledge.record_sighting(RELATIVE, "outdoors", Vector2(12, 10), 599.0, "ev:now")
	town.save_game.life.minute = 601.0
	town._maintain_commitments(SEEKER)
	assert_eq(mind.commitments.get_commitment(commitment).status, "completed")
	assert_eq(town.save_game.life.search_for(SEEKER, commitment), {"step": 0, "deferred_until": 0.0})
	assert_false(town.save_game.life.to_data().people[SEEKER].searches.has(commitment))
	assert_eq(town.save_game.life.get_person(SEEKER).until, 601.0, "the finished search is interrupted")
	assert_false("CHECK_RELATIVE" in _ids(town._options(SEEKER, {"kind": "rest", "place": "home:" + SEEKER})))
	brain.free()
	town.free()

func test_the_sighting_that_raised_the_worry_does_not_complete_the_check() -> void:
	var town: TownLife = _town(600.0)
	var mind: NpcMindState = town.save_game.minds.get_mind(SEEKER)
	var commitment: String = _open_check(town, 600.0)
	mind.knowledge.record_sighting(RELATIVE, "outdoors", Vector2(10, 10), 600.0, "ev:hurt")
	town._maintain_commitments(SEEKER)
	assert_eq(mind.commitments.get_commitment(commitment).status, "open",
		"seeing the relative hurt at the minute of the worry is not finding them")
	mind.knowledge.record_sighting(RELATIVE, "outdoors", Vector2(12, 10), 601.0, "ev:later")
	town.save_game.life.minute = 601.0
	town._maintain_commitments(SEEKER)
	assert_eq(mind.commitments.get_commitment(commitment).status, "completed")
	town.free()

func test_learning_the_relative_died_cancels_the_check() -> void:
	var town: TownLife = _town(600.0)
	var mind: NpcMindState = town.save_game.minds.get_mind(SEEKER)
	var commitment: String = _open_check(town, 500.0)
	town.save_game.life.set_search(SEEKER, commitment, 2, 0.0)
	_searching(town, commitment, "work:" + RELATIVE)
	mind.knowledge.record(RELATIVE, "status", "dead", NpcKnowledge.Status.OBSERVED,
		NpcKnowledge.SELF_SOURCE, "ev:death", "death:" + RELATIVE, 590.0, 1.0)
	town._maintain_commitments(SEEKER)
	assert_eq(mind.commitments.get_commitment(commitment).status, "cancelled")
	assert_false(town.save_game.life.to_data().people[SEEKER].searches.has(commitment))
	town.free()

func test_a_grave_visit_completes_on_arrival_and_not_while_travelling() -> void:
	var town: TownLife = _town(600.0)
	var mind: NpcMindState = town.save_game.minds.get_mind(SEEKER)
	var commitment: String = mind.commitments.create(TownLife.VISIT_GRAVE, [RELATIVE] as Array[String],
		["ev:funeral"] as Array[String], 590.0, -1.0, 0.8)
	_searching(town, commitment, TownLife.GRAVE_PREFIX + RELATIVE, TownLife.VISIT_GRAVE)
	var executor: Routine.FakeExecutor = Routine.FakeExecutor.new()
	var brain: NpcBrain = _brain(town, executor)
	var task: NpcRoutineTask = NpcRoutineTask.create({"activity": TownLife.VISIT_GRAVE,
		"place": TownLife.GRAVE_PREFIX + RELATIVE, "label": "Visiting the grave", "space": "town",
		"point": [40.0, 24.0], "until_minute": 630.0}, town.tuning)
	assert_true(brain.request_task(task))
	town._maintain_commitments(SEEKER)
	assert_eq(mind.commitments.get_commitment(commitment).status, "open", "still on the way")
	executor.arrive()
	brain.advance(601.0, 1.0)
	town._maintain_commitments(SEEKER)
	assert_eq(mind.commitments.get_commitment(commitment).status, "completed")
	brain.free()
	town.free()

func test_open_searches_survive_a_world_save_round_trip() -> void:
	var town: TownLife = _town(600.0)
	var commitment: String = _open_check(town, 500.0)
	town.save_game.life.set_search(SEEKER, commitment, 1, 0.0)
	var second: String = town.save_game.minds.get_mind(SEEKER).commitments.create(TownLife.CHECK_RELATIVE,
		["cassian_vale"] as Array[String], [] as Array[String], 500.0, -1.0, 0.4)
	town.save_game.life.set_search(SEEKER, second, 0, 780.0)
	var loaded := NpcWorldSave.new()
	assert_true(loaded.from_data(JSON.parse_string(JSON.stringify(town.save_game.to_data()))))
	assert_eq(loaded.life.search_for(SEEKER, commitment), {"step": 1, "deferred_until": 0.0})
	assert_eq(loaded.life.search_for(SEEKER, second), {"step": 0, "deferred_until": 780.0})
	assert_eq(loaded.minds.get_mind(SEEKER).commitments.get_commitment(commitment).status, "open")
	var resumed: TownLife = _town(600.0)
	resumed.save_game = loaded
	var offered: Array[Dictionary] = resumed._options(SEEKER, {"kind": "rest", "place": "home:" + SEEKER})
	var checks: Array[Dictionary] = offered.filter(
		func(option: Dictionary) -> bool: return option.id == "CHECK_RELATIVE")
	assert_eq(checks.size(), 1)
	assert_eq(checks[0].commitment_id, commitment, "the deferred search is not offered, the saved step is")
	assert_eq(checks[0].place, "work:" + RELATIVE)
	resumed.free()
	town.free()
