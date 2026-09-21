extends "res://tests/test_case.gd"

func _event(origin: String = "world:1", personal: bool = true) -> Dictionary:
	return {"origin_id": origin, "text": "I was struck." if personal else "I heard fighting nearby.",
		"sense": "touch" if personal else "hearing", "directly_affected": personal,
		"player_involved": false, "danger_possible": true}

func test_personal_injury_has_a_bounded_fallback_and_distant_noise_does_not_force_flight() -> void:
	var hurt: Dictionary = NpcSafetyState.notice({}, _event(), "outdoors", 500.0)
	assert_true(NpcSafetyState.sheltering(hurt, 501.0))
	assert_false(NpcSafetyState.sheltering(hurt, 546.0))
	assert_eq(NpcSafetyState.assess(hurt, _event(), {}, 501.0), hurt)
	var heard: Dictionary = NpcSafetyState.notice({}, _event("world:2", false), "outdoors", 500.0)
	assert_eq(heard.response, "CAUTION")
	assert_false(NpcSafetyState.sheltering(heard, 501.0))
	assert_false(NpcSafetyState.context(heard, 501).has("attacker"))
	var selected: Dictionary = NpcSafetyState.assess(heard, _event("world:2", false),
		{"safety_response": "SHELTER"}, 501.0)
	assert_true(NpcSafetyState.sheltering(selected, 501.0))
	assert_true(NpcSafetyState.assess(heard, _event("world:2", false),
		{"safety_response": "NONE"}, 501.0).is_empty())

func test_old_assessments_noise_and_day_boundaries_cannot_overwrite_a_retreat() -> void:
	var state := TownLifeState.new()
	state.ensure_person("a", 42, ["a"], ["market"])
	state.minute = 1439.0
	state.notice_perception("a", _event(), "outdoors")
	state.select_activity("a", {"kind": "shelter", "place": "work:a"}, 45, {})
	assert_eq(state.get_person("a").until, 1484.0)
	state.advance(3)
	state.ensure_person("a", 42, ["a"], ["market"])
	assert_eq(state.get_person("a").until, 1484.0)
	state.notice_perception("a", _event("world:2", false), "outdoors")
	assert_eq(state.get_person("a").safety.origin_id, "world:1")
	state.notice_perception("a", _event("world:3"), "home:a")
	var current: Dictionary = state.get_person("a").safety
	state.assess_perception("a", _event(), {"safety_response": "NONE"})
	assert_eq(state.get_person("a").safety, current)
	state.advance(50)
	state.assess_perception("a", _event("world:3"), {"safety_response": "SHELTER"})
	assert_false(NpcSafetyState.sheltering(state.get_person("a").safety, state.minute))

func test_safety_concerns_round_trip_and_invalid_or_legacy_saves_are_handled_atomically() -> void:
	var state := TownLifeState.new()
	state.ensure_person("a", 42, ["a"], ["market"])
	state.notice_perception("a", _event(), "home:a")
	var loaded := TownLifeState.new()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state.to_data()))
	assert_true(loaded.from_data(saved))
	assert_eq(loaded.get_person("a").safety, saved.people.a.safety)
	saved.people.a.safety.until = NAN
	assert_false(loaded.from_data(saved))
	assert_true(NpcSafetyState.sheltering(loaded.get_person("a").safety, loaded.minute))
	saved.people.a.erase("safety")
	assert_true(loaded.from_data(saved))
	assert_true(loaded.get_person("a").safety.is_empty())

func test_unrelated_events_do_not_create_safety_concerns() -> void:
	var event: Dictionary = _event()
	event.erase("danger_possible")
	assert_true(NpcSafetyState.notice({}, event, "outdoors", 500).is_empty())
