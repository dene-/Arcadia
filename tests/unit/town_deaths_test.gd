extends "res://tests/test_case.gd"

const OK := TownDeaths.OK_RESULT
const BODY := "garrin"
const SPACE := "plaza"
const AT_BODY := Vector2(100.0, 50.0)

func _deaths() -> TownDeaths:
	var deaths := TownDeaths.new()
	deaths.record(BODY, SPACE, AT_BODY, 10.0)
	return deaths

func _reported(guard: String = "mira") -> TownDeaths:
	var deaths := _deaths()
	assert_eq(deaths.discover(BODY, guard, 11.0), OK)
	assert_eq(deaths.acknowledge_report(BODY, guard, guard, 12.0), OK)
	return deaths

func _recovering(guard: String = "mira") -> TownDeaths:
	var deaths := _reported(guard)
	assert_eq(deaths.begin_recovery(BODY, guard, 13.0), OK)
	return deaths

func _carried(guard: String = "mira") -> TownDeaths:
	var deaths := _recovering(guard)
	assert_eq(deaths.pick_up(BODY, guard, SPACE, AT_BODY, 14.0), OK)
	return deaths

func _stage(deaths: TownDeaths) -> String:
	return deaths.snapshot(BODY).stage

func _reloaded(deaths: TownDeaths) -> TownDeaths:
	var loaded := TownDeaths.new()
	var data: Variant = JSON.parse_string(JSON.stringify(deaths.to_data()))
	assert_true(loaded.from_data(data), "remains survive a JSON round trip")
	return loaded

func test_bury_before_discovery_acknowledgment_or_pickup_fails_and_changes_nothing() -> void:
	var deaths := _deaths()
	var before := deaths.snapshot(BODY)
	assert_eq(deaths.bury(BODY, "mira", 11.0), TownDeaths.WRONG_STAGE)
	assert_eq(deaths.snapshot(BODY), before)
	deaths.discover(BODY, "mira", 11.0)
	before = deaths.snapshot(BODY)
	assert_eq(deaths.bury(BODY, "mira", 12.0), TownDeaths.WRONG_STAGE)
	assert_eq(deaths.snapshot(BODY), before)
	deaths.acknowledge_report(BODY, "mira", "mira", 12.0)
	deaths.begin_recovery(BODY, "mira", 13.0)
	before = deaths.snapshot(BODY)
	assert_eq(deaths.bury(BODY, "mira", 14.0), TownDeaths.WRONG_STAGE)
	assert_eq(deaths.snapshot(BODY), before)

func test_two_guards_attempt_recovery_and_exactly_one_picks_up() -> void:
	var deaths := _reported("mira")
	var results: Array[StringName] = [
		deaths.begin_recovery(BODY, "mira", 13.0), deaths.begin_recovery(BODY, "tarn", 13.0)]
	assert_eq(results, [OK, TownDeaths.ALREADY_CLAIMED] as Array[StringName])
	assert_eq(deaths.pick_up(BODY, "tarn", SPACE, AT_BODY, 14.0), TownDeaths.NOT_OWNER)
	assert_eq(deaths.pick_up(BODY, "mira", SPACE, AT_BODY, 14.0), OK)
	assert_eq(deaths.snapshot(BODY).guard, "mira")

func test_carrier_death_leaves_the_body_at_the_carried_position_for_another_guard() -> void:
	var deaths := _carried("mira")
	var drop_point := Vector2(180.0, 90.0)
	assert_eq(deaths.update_carried_position(BODY, "mira", "street", drop_point), OK)
	assert_eq(deaths.release_assignment(BODY, "mira", 20.0), OK)
	var body := deaths.snapshot(BODY)
	assert_eq(body.stage, "reported")
	assert_eq(body.guard, "")
	assert_eq(body.space, "street")
	assert_eq(body.position, [180.0, 90.0])
	assert_eq(body.since, 20.0)
	assert_eq(deaths.begin_recovery(BODY, "tarn", 21.0), OK)
	assert_eq(deaths.pick_up(BODY, "tarn", "street", Vector2(170.0, 90.0), 22.0), OK)

func test_reload_mid_recovery_then_finish_burial_once() -> void:
	var deaths := _reloaded(_carried("mira"))
	assert_eq(_stage(deaths), "carried")
	assert_eq(deaths.bury(BODY, "tarn", 30.0), TownDeaths.NOT_OWNER)
	assert_eq(deaths.bury(BODY, "mira", 30.0), OK)
	var buried := deaths.snapshot(BODY)
	assert_eq(buried.stage, "buried")
	assert_eq(deaths.bury(BODY, "mira", 31.0), TownDeaths.WRONG_STAGE)
	assert_eq(deaths.snapshot(BODY), buried)
	assert_eq(_reloaded(deaths).snapshot(BODY), buried)
	assert_eq(deaths.ids(), [BODY] as Array[String])

func test_discovering_guard_acknowledges_its_own_report() -> void:
	var deaths := _deaths()
	assert_eq(deaths.discover(BODY, "mira", 11.0), OK)
	assert_eq(deaths.acknowledge_report(BODY, "mira", "mira", 12.0), OK)
	var body := deaths.snapshot(BODY)
	assert_eq(body.stage, "reported")
	assert_eq(body.guard, "mira")
	assert_eq(body.known_by, ["mira"])

func test_a_citizen_report_is_acknowledged_by_a_guard() -> void:
	var deaths := _deaths()
	deaths.discover(BODY, "pell", 11.0)
	assert_eq(deaths.acknowledge_report(BODY, "mira", "tarn", 12.0), TownDeaths.NOT_OWNER)
	assert_eq(deaths.claim_report(BODY, "tarn", 12.0), TownDeaths.ALREADY_CLAIMED)
	assert_eq(deaths.claim_report(BODY, "pell", 12.0), OK)
	assert_eq(deaths.acknowledge_report(BODY, "mira", "pell", 12.0), OK)
	var body := deaths.snapshot(BODY)
	assert_eq(body.reporter, "pell")
	assert_eq(body.guard, "mira")
	assert_eq(body.known_by, ["pell", "mira"])

func test_later_discoverers_only_gain_knowledge() -> void:
	var deaths := _deaths()
	deaths.discover(BODY, "pell", 11.0)
	assert_eq(deaths.discover(BODY, "tarn", 12.0), OK)
	assert_eq(deaths.discover(BODY, "tarn", 13.0), OK)
	var body := deaths.snapshot(BODY)
	assert_eq(body.reporter, "pell")
	assert_eq(body.known_by, ["pell", "tarn"])
	assert_eq(body.since, 11.0)

func test_reporter_loss_before_acknowledgment_releases_the_claim_but_keeps_knowledge() -> void:
	var deaths := _deaths()
	deaths.discover(BODY, "pell", 11.0)
	deaths.discover(BODY, "tarn", 11.5)
	assert_eq(deaths.release_assignment(BODY, "tarn", 12.0), TownDeaths.NOT_OWNER)
	assert_eq(deaths.release_assignment(BODY, "pell", 12.0), OK)
	var body := deaths.snapshot(BODY)
	assert_eq(body.stage, "discovered")
	assert_eq(body.reporter, "")
	assert_eq(body.known_by, ["pell", "tarn"])
	assert_eq(deaths.claim_report(BODY, "tarn", 13.0), OK)
	assert_eq(deaths.acknowledge_report(BODY, "mira", "tarn", 14.0), OK)

func test_recovering_guard_loss_reopens_the_recovery() -> void:
	var deaths := _recovering("mira")
	assert_eq(deaths.release_assignment(BODY, "mira", 20.0), OK)
	var body := deaths.snapshot(BODY)
	assert_eq(body.stage, "reported")
	assert_eq(body.guard, "")
	assert_eq(deaths.begin_recovery(BODY, "tarn", 21.0), OK)

func test_acknowledging_guard_loss_frees_the_body_without_changing_stage() -> void:
	var deaths := _reported("mira")
	assert_eq(deaths.release_assignment(BODY, "mira", 20.0), OK)
	assert_eq(_stage(deaths), "reported")
	assert_eq(deaths.begin_recovery(BODY, "tarn", 21.0), OK)

func test_release_rejects_unrelated_actors_and_buried_remains() -> void:
	var deaths := _carried("mira")
	var before := deaths.snapshot(BODY)
	assert_eq(deaths.release_assignment(BODY, "tarn", 20.0), TownDeaths.NOT_OWNER)
	assert_eq(deaths.release_assignment("nobody", "mira", 20.0), TownDeaths.UNKNOWN_BODY)
	assert_eq(deaths.snapshot(BODY), before)
	deaths.bury(BODY, "mira", 21.0)
	assert_eq(deaths.release_assignment(BODY, "mira", 22.0), TownDeaths.NOT_OWNER)

func test_pickup_out_of_range_or_in_another_space_is_not_at_body() -> void:
	var deaths := _recovering("mira")
	var before := deaths.snapshot(BODY)
	var far := AT_BODY + Vector2(TownDeaths.PICKUP_DISTANCE + 1.0, 0.0)
	assert_eq(deaths.pick_up(BODY, "mira", SPACE, far, 14.0), TownDeaths.NOT_AT_BODY)
	assert_eq(deaths.pick_up(BODY, "mira", "tavern", AT_BODY, 14.0), TownDeaths.NOT_AT_BODY)
	assert_eq(deaths.snapshot(BODY), before)
	var edge := AT_BODY + Vector2(TownDeaths.PICKUP_DISTANCE, 0.0)
	assert_eq(deaths.pick_up(BODY, "mira", SPACE, edge, 14.0), OK)

func test_drop_and_interrupt_return_the_body_to_reported() -> void:
	var deaths := _carried("mira")
	assert_eq(deaths.drop(BODY, "tarn", SPACE, AT_BODY, 15.0), TownDeaths.NOT_OWNER)
	assert_eq(deaths.drop(BODY, "mira", "alley", Vector2(7.0, 8.0), 15.0), OK)
	var body := deaths.snapshot(BODY)
	assert_eq([body.stage, body.guard, body.space, body.position, body.since],
		["reported", "", "alley", [7.0, 8.0], 15.0])
	deaths.begin_recovery(BODY, "mira", 16.0)
	assert_eq(deaths.interrupt_recovery(BODY, "tarn", 17.0), TownDeaths.NOT_OWNER)
	assert_eq(deaths.interrupt_recovery(BODY, "mira", 17.0), OK)
	assert_eq(_stage(deaths), "reported")
	assert_eq(deaths.snapshot(BODY).guard, "")

func test_carried_position_updates_require_the_carrier() -> void:
	var deaths := _recovering("mira")
	assert_eq(deaths.update_carried_position(BODY, "mira", SPACE, AT_BODY), TownDeaths.WRONG_STAGE)
	deaths.pick_up(BODY, "mira", SPACE, AT_BODY, 14.0)
	var before := deaths.snapshot(BODY)
	assert_eq(deaths.update_carried_position(BODY, "tarn", SPACE, Vector2(1.0, 1.0)),
		TownDeaths.NOT_OWNER)
	assert_eq(deaths.snapshot(BODY), before)

func test_burial_knowledge_is_recorded_once_and_only_for_buried_remains() -> void:
	var deaths := _carried("mira")
	assert_eq(deaths.mark_burial_known(BODY, "pell"), TownDeaths.WRONG_STAGE)
	deaths.bury(BODY, "mira", 20.0)
	assert_eq(deaths.mark_burial_known(BODY, "pell"), OK)
	assert_eq(deaths.mark_burial_known(BODY, "pell"), OK)
	assert_eq(deaths.snapshot(BODY).burial_known_by, ["pell"])
	assert_eq(deaths.mark_known(BODY, "pell"), OK)
	assert_eq(deaths.mark_known(BODY, "pell"), OK)
	assert_eq(deaths.snapshot(BODY).known_by, ["mira", "pell"])
	assert_eq(deaths.mark_known("nobody", "pell"), TownDeaths.UNKNOWN_BODY)

func test_allowed_chain_walks_every_stage_and_updates_since() -> void:
	var deaths := _deaths()
	var expected: Array = [["discovered", 11.0], ["reported", 12.0], ["recovering", 13.0],
		["carried", 14.0], ["buried", 15.0]]
	var results: Array[StringName] = [
		deaths.discover(BODY, "mira", 11.0),
		deaths.acknowledge_report(BODY, "mira", "mira", 12.0),
		deaths.begin_recovery(BODY, "mira", 13.0),
		deaths.pick_up(BODY, "mira", SPACE, AT_BODY, 14.0),
		deaths.bury(BODY, "mira", 15.0)]
	assert_eq(results, [OK, OK, OK, OK, OK] as Array[StringName])
	var body := deaths.snapshot(BODY)
	assert_eq([body.stage, body.since], expected[4])

func test_disallowed_transitions_return_wrong_stage_and_leave_the_record_alone() -> void:
	var cases: Dictionary = {
		"fallen": [_deaths(), ["claim_report", "acknowledge", "begin", "pick_up", "drop",
			"interrupt", "bury", "carried_position", "mark_burial_known"]],
		"discovered": [_deaths(), ["begin", "pick_up", "drop", "interrupt", "bury",
			"carried_position", "mark_burial_known"]],
		"reported": [_reported(), ["claim_report", "acknowledge", "pick_up", "drop",
			"interrupt", "bury", "carried_position", "mark_burial_known"]],
		"recovering": [_recovering(), ["claim_report", "acknowledge", "begin", "drop",
			"bury", "carried_position", "mark_burial_known"]],
		"carried": [_carried(), ["claim_report", "acknowledge", "begin", "pick_up",
			"interrupt", "mark_burial_known"]],
	}
	cases["discovered"][0].discover(BODY, "mira", 11.0)
	var buried := _carried()
	buried.bury(BODY, "mira", 20.0)
	cases["buried"] = [buried, ["discover", "claim_report", "acknowledge", "begin", "pick_up",
		"drop", "interrupt", "bury", "carried_position"]]
	for stage: String in cases:
		var deaths: TownDeaths = cases[stage][0]
		assert_eq(_stage(deaths), stage)
		for call: String in cases[stage][1]:
			var before := deaths.snapshot(BODY)
			assert_eq(_attempt(deaths, call), TownDeaths.WRONG_STAGE, "%s from %s" % [call, stage])
			assert_eq(deaths.snapshot(BODY), before, "%s from %s leaves the record" % [call, stage])

func _attempt(deaths: TownDeaths, call: String) -> StringName:
	match call:
		"discover": return deaths.discover(BODY, "mira", 40.0)
		"claim_report": return deaths.claim_report(BODY, "mira", 40.0)
		"acknowledge": return deaths.acknowledge_report(BODY, "mira", "mira", 40.0)
		"begin": return deaths.begin_recovery(BODY, "mira", 40.0)
		"pick_up": return deaths.pick_up(BODY, "mira", SPACE, AT_BODY, 40.0)
		"drop": return deaths.drop(BODY, "mira", SPACE, AT_BODY, 40.0)
		"interrupt": return deaths.interrupt_recovery(BODY, "mira", 40.0)
		"bury": return deaths.bury(BODY, "mira", 40.0)
		"carried_position": return deaths.update_carried_position(BODY, "mira", SPACE, AT_BODY)
		"mark_burial_known": return deaths.mark_burial_known(BODY, "mira")
	return &"unhandled"

func test_unknown_bodies_and_invalid_arguments_are_rejected() -> void:
	var deaths := _deaths()
	assert_eq(deaths.discover("nobody", "mira", 11.0), TownDeaths.UNKNOWN_BODY)
	assert_eq(deaths.bury("nobody", "mira", 11.0), TownDeaths.UNKNOWN_BODY)
	assert_eq(deaths.snapshot("nobody"), {})
	var before := deaths.snapshot(BODY)
	assert_eq(deaths.discover("", "mira", 11.0), TownDeaths.INVALID)
	assert_eq(deaths.discover(BODY, "", 11.0), TownDeaths.INVALID)
	assert_eq(deaths.discover(BODY, "mira", NAN), TownDeaths.INVALID)
	assert_eq(deaths.discover(BODY, "mira", INF), TownDeaths.INVALID)
	assert_eq(deaths.snapshot(BODY), before)
	var carried := _carried()
	assert_eq(carried.drop(BODY, "mira", "", AT_BODY, 20.0), TownDeaths.INVALID)
	assert_eq(carried.drop(BODY, "mira", SPACE, Vector2(NAN, 0.0), 20.0), TownDeaths.INVALID)
	assert_eq(carried.update_carried_position(BODY, "mira", SPACE, Vector2(INF, 0.0)), TownDeaths.INVALID)
	assert_eq(carried.bury(BODY, "", 20.0), TownDeaths.INVALID)
	assert_eq(_stage(carried), "carried")

func test_snapshots_are_copies_and_ids_are_sorted() -> void:
	var deaths := _deaths()
	deaths.record("alba", "tavern", Vector2.ZERO, 5.0)
	assert_eq(deaths.ids(), ["alba", BODY] as Array[String])
	var copy := deaths.snapshot(BODY)
	copy.stage = "buried"
	copy.known_by.append("ghost")
	assert_eq(_stage(deaths), "fallen")
	assert_eq(deaths.snapshot(BODY).known_by, [])
