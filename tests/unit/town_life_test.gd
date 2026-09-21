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

func _event(id: String = "event:1") -> Dictionary:
	return {"origin_id": id, "text": "I saw Den hurt Garrin.", "sense": "sight", "player_involved": true}

func _policy() -> Dictionary:
	return {"remember": true, "importance": 0.8, "belief": 0.7, "affinity": 0.0, "trust_player": -0.03}

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

func test_world_save_migrates_old_life_and_rejects_corruption_atomically() -> void:
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
	assert_true(loaded.from_data(data))
	assert_true(loaded.life.get_person("a").is_empty())
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
