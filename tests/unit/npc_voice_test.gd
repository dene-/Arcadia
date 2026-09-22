extends "res://tests/test_case.gd"

const PROCEDURAL_PROFILE: GDScript = preload("res://game/world/life/npc_procedural_profile.gd")

func test_old_personalities_gain_a_stable_voice_without_rerolling_town_state() -> void:
	var state := TownLifeState.new()
	state.ensure_person("a", 42, ["a", "b"], ["square"])
	var original: Dictionary = state.personality_for("a", 42)
	var data: Dictionary = state.to_data()
	data.personalities.a.erase("voice")
	data.personalities.a.speech_style = "Quiet and thoughtful."
	var loaded := TownLifeState.new()
	assert_true(loaded.from_data(JSON.parse_string(JSON.stringify(data))))
	var upgraded: Dictionary = loaded.personality_for("a", 42)
	assert_eq(upgraded.personality, original.personality)
	assert_eq(upgraded.voice, original.voice)
	for tendency: String in original.traits:
		assert_true(is_equal_approx(upgraded.traits[tendency], original.traits[tendency]))
	assert_eq(loaded.get_person("a"), JSON.parse_string(JSON.stringify(state.get_person("a"))))
	var reloaded := TownLifeState.new()
	assert_true(reloaded.from_data(JSON.parse_string(JSON.stringify(loaded.to_data()))))
	assert_eq(reloaded.personality_for("a", 999).voice, upgraded.voice)

func test_voice_reflects_contrasting_temperaments() -> void:
	var reserved: Dictionary = {"traits": {"sociability": 0.1, "discretion": 0.9,
		"patience": 0.9, "courage": 0.1, "curiosity": 0.1}}
	var outgoing: Dictionary = {"traits": {"sociability": 0.9, "discretion": 0.1,
		"patience": 0.1, "courage": 0.9, "curiosity": 0.9}}
	NpcTemperament.ensure_voice(reserved, 42, "a")
	NpcTemperament.ensure_voice(outgoing, 42, "b")
	assert_eq(reserved.voice.verbosity, "SPARE")
	assert_eq(outgoing.voice.verbosity, "EXPANSIVE")
	assert_eq(reserved.voice.cadence, "MEASURED")
	assert_eq(outgoing.voice.cadence, "BRISK")
	assert_eq(reserved.voice.directness, "TENTATIVE")
	assert_eq(outgoing.voice.directness, "BLUNT")
	assert_eq(reserved.voice.disclosure, "RESERVED")
	assert_eq(outgoing.voice.disclosure, "OPEN")
	assert_eq(reserved.voice.questions, "RARE")
	assert_eq(outgoing.voice.questions, "INQUISITIVE")

func test_corrupt_voice_is_rejected_without_replacing_existing_save_state() -> void:
	var state := TownLifeState.new()
	state.personality_for("a", 42)
	var original: Dictionary = state.to_data()
	for bad_voice: Variant in [{}, "brisk", {"register": "UNKNOWN"}]:
		var data: Dictionary = original.duplicate(true)
		data.personalities.a.voice = bad_voice
		assert_false(state.from_data(data))
		assert_eq(state.to_data(), original)

func test_runtime_profile_exposes_voice_without_mutating_saved_personality() -> void:
	var state := TownLifeState.new()
	var identity: Dictionary = state.personality_for("a", 42)
	var profile := NpcProfile.new()
	NpcTemperament.apply(profile, identity)
	var payload: Dictionary = profile.to_backend_profile()
	assert_eq(payload.voice, identity.voice)
	assert_eq(payload.personality, identity.personality)
	assert_eq(payload.social_traits, identity.traits)
	payload.voice.cadence = "changed in request"
	assert_eq(profile.voice.cadence, identity.voice.cadence)
	profile.voice.cadence = "changed in inspector"
	assert_eq(state.personality_for("a", 42).voice, identity.voice)

func test_authored_personality_survives_town_temperament_in_backend_profile() -> void:
	var population := TownPopulation.new()
	population.ensure_population(42)
	var profile: NpcProfile = population.profile_for("garrin_holt")
	var authored_personality: String = profile.personality
	var identity: Dictionary = TownLifeState.new().personality_for("garrin_holt", 42)
	assert_ne(authored_personality, identity.personality)
	NpcTemperament.apply(profile, identity)
	var payload: Dictionary = profile.to_backend_profile()
	assert_eq(payload.personality, authored_personality)
	assert_eq(payload.age, "44")
	assert_eq(payload.job, "Village blacksmith")
	assert_eq(payload.voice, identity.voice)
	assert_eq(payload.speech_style, identity.speech_style)

func test_procedural_profiles_reflect_work_age_and_saved_temperament() -> void:
	var population := TownPopulation.new()
	population.ensure_population(42)
	var state := TownLifeState.new()
	var personalities: Dictionary = {}
	for id: String in population.people:
		if TownPopulation.FOUNDERS.values().has(id):
			continue
		var profile: NpcProfile = population.profile_for(id)
		var saved: Dictionary = state.personality_for(id, 42)
		var original: Dictionary = saved.duplicate(true)
		NpcTemperament.apply(profile, saved)
		PROCEDURAL_PROFILE.apply(profile, population.people[id], saved)
		var payload: Dictionary = profile.to_backend_profile()
		assert_ne(payload.background, "A longtime member of Rekala's small community.")
		assert_false(payload.values.is_empty())
		assert_false(payload.goals.is_empty())
		assert_false(payload.personality.is_empty())
		assert_ne(payload.personality, saved.personality)
		assert_eq(payload.speech_style, saved.speech_style)
		assert_eq(saved, original, "Runtime profiles must not rewrite saved temperament.")
		personalities[id] = payload.personality
	assert_eq(personalities.size(), TownPopulation.MEMBERS.size())
	assert_ne(personalities.holt_child_b, personalities.voss_child)
	assert_ne(personalities.rowan_father, personalities.rowan_mother)
	var child: NpcProfile = population.profile_for("voss_child")
	var child_temperament: Dictionary = state.personality_for("voss_child", 42)
	NpcTemperament.apply(child, child_temperament)
	PROCEDURAL_PROFILE.apply(child, population.people.voss_child, child_temperament)
	assert_eq(child.voice.register, "FAMILIAR")
	assert_true(child.personality.contains("adults"))
	var guard: NpcProfile = population.profile_for("voss_guard")
	var guard_temperament: Dictionary = state.personality_for("voss_guard", 42)
	NpcTemperament.apply(guard, guard_temperament)
	PROCEDURAL_PROFILE.apply(guard, population.people.voss_guard, guard_temperament)
	assert_true(guard.values.contains("evidence"))
	assert_true(guard.goals.contains("children"))
