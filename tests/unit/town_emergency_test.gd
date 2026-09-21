extends "res://tests/test_case.gd"

func test_watch_covers_midnight_and_keeps_daytime_sleep_after_save_migration() -> void:
	var save := NpcWorldSave.new()
	save.population.ensure_population(27)
	var night: Array[Dictionary] = TownResidentSchedule.generate(save.population, "vale_guard", 27, 0, ["square"])
	for minute: int in range(1110, 1830):
		assert_eq(NpcRoutinePlan.current(night, minute).kind, "patrol")
	assert_eq(NpcRoutinePlan.current(night, 800).kind, "rest")
	save.life.minute = 1400
	save.life.ensure_person("vale_guard", 27, ["vale_guard"], ["square"], save.population)
	var old: Dictionary = save.life.to_data()
	old.people.vale_guard.plan_revision = 3
	old.people.vale_guard.plan = [{"minute": 0, "kind": "rest", "place": "home:vale_guard"}]
	assert_true(save.life.from_data(old))
	save.life.ensure_person("vale_guard", 27, ["vale_guard"], ["square"], save.population)
	assert_eq(NpcRoutinePlan.current(save.life.get_person("vale_guard").plan, 1400).kind, "patrol")

func test_death_stages_round_trip_atomically_without_resurrecting_legacy_deaths() -> void:
	var save := NpcWorldSave.new()
	save.mark_dead(&"victim")
	save.deaths.record("victim", "home:family", Vector2(22, 44), 1400)
	save.deaths.records.victim.reporter = "witness"
	save.deaths.records.victim.known_by.append("witness")
	for stage: String in TownDeaths.STAGES:
		save.deaths.transition("victim", stage, 1405)
		var restored := NpcWorldSave.new()
		assert_true(restored.from_data(save.to_data()))
		assert_eq(restored.deaths.records.victim, save.deaths.records.victim)
	var corrupt: Dictionary = save.to_data()
	corrupt.world.deaths.victim.position[0] = "invalid"
	assert_false(save.from_data(corrupt))
	assert_eq(save.deaths.records.victim.stage, "buried")
	corrupt = save.to_data()
	corrupt.world.dead_npcs.clear()
	assert_false(save.from_data(corrupt))
	var legacy: Dictionary = save.to_data()
	legacy.world.erase("deaths")
	assert_true(save.from_data(legacy))
	assert_true(save.is_dead(&"victim"))
	assert_true(save.deaths.records.is_empty())

func test_noise_has_distinct_waking_and_orientation_beats_without_timer_starvation() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var npc: BaseNpc = load("res://game/actors/npcs/base_npc.tscn").instantiate()
	npc.npc_data = npc.npc_data.duplicate()
	npc.npc_data.profile = NpcProfile.new()
	npc.npc_data.profile.npc_id = &"wake_test"
	tree.root.add_child(npc)
	npc.set_physics_process(false)
	npc.sleep_at(npc.global_position + Vector2(0, -20))
	var event: Dictionary = {"danger_possible": true, "directly_affected": false, "origin_id": "noise:1"}
	npc.alert_response.notice(npc, event)
	var remaining: float = npc.alert_response.remaining
	assert_true(npc.is_sleeping())
	npc.alert_response.advance(npc, 0.8)
	npc.alert_response.notice(npc, event)
	assert_true(npc.alert_response.remaining < remaining)
	assert_true(npc.is_sleeping())
	npc.alert_response.advance(npc, 4)
	assert_false(npc.is_sleeping())
	assert_eq(npc.alert_response.phase, "getting_bearings")
	assert_false(npc.can_follow_routine())
	npc.alert_response.advance(npc, 2)
	assert_true(npc.can_follow_routine())
	npc.queue_free()
	await tree.process_frame
