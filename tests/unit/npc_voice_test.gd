extends "res://tests/test_case.gd"

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
