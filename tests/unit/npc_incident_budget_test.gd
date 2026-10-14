extends "res://tests/test_case.gd"

const _TOLERANCE: float = 0.0001

func _round_trip(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))

func _observation(serial: String, kind: String, incident: String, minute: float,
		role: String = "aggressor") -> NpcObservation:
	var observation: NpcObservation = NpcObservation.from_perception("elder", serial, minute, &"town", {
		"text": "The player and a villager clashed (%s)." % serial, "sense": "sight", "kind": kind,
		"player_involved": true,
		"participants": [{"id": "player", "name": "the player", "role": role},
			{"id": "mira", "name": "Mira", "role": "victim"}]})
	assert_not_null(observation)
	observation.incident_id = incident
	return observation

func _delta(trust: float = -0.08, fear: float = 0.08) -> Dictionary:
	return {"trust": trust, "fear": fear}

## Applies one observation's relationship change; returns whether the receipt was fresh.
func _apply(mind: NpcMindState, observation: NpcObservation, delta: Dictionary = _delta()) -> bool:
	return mind.apply_evidence_delta("player", observation, delta,
		"observation:" + observation.observation_id)

func _hits(mind: NpcMindState, incident: String, count: int, first_minute: float = 500.0) -> void:
	for index: int in range(count):
		_apply(mind, _observation("%s:hit:%d" % [incident, index], "actor_hurt", incident,
			first_minute + index * 0.1))

func _trust(mind: NpcMindState) -> float:
	return float(mind.relationships.get_relationship("player").trust)

func _fear(mind: NpcMindState) -> float:
	return float(mind.relationships.get_relationship("player").fear)

func test_ten_hits_and_three_hits_of_one_assault_end_within_the_budget() -> void:
	var many := NpcMindState.new("elder")
	var few := NpcMindState.new("elder")
	_hits(many, "assault:1", 10)
	_hits(few, "assault:1", 3)
	assert_true(absf(_trust(many) - _trust(few)) <= NpcIncidentBudget.BUDGET)
	assert_true(absf(_fear(many) - _fear(few)) <= NpcIncidentBudget.BUDGET)
	for mind: NpcMindState in [many, few]:
		assert_true(absf(_trust(mind)) <= NpcIncidentBudget.BUDGET + _TOLERANCE)
		assert_true(absf(_fear(mind)) <= NpcIncidentBudget.BUDGET + _TOLERANCE)
		assert_true(_trust(mind) < 0.0, "The assault still lowered trust")
		assert_true(_fear(mind) > 0.0, "The assault still raised fear")

func test_exhausted_budget_still_consumes_the_receipt() -> void:
	var mind := NpcMindState.new("elder")
	_hits(mind, "assault:1", 4)
	var spent: Dictionary = mind.incident_budget.spent("player", "assault:1", NpcIncidentBudget.ORDINARY)
	var late: NpcObservation = _observation("assault:1:late", "actor_hurt", "assault:1", 501.0)
	assert_true(_apply(mind, late), "Evidence is receipted even when the budget allows nothing more")
	assert_true(mind.relationships.has_receipt("observation:" + late.observation_id))
	assert_eq(mind.incident_budget.spent("player", "assault:1", NpcIncidentBudget.ORDINARY), spent)
	assert_false(_apply(mind, late), "A receipt applies once")

func test_a_fatal_escalation_opens_one_fresh_budget_once() -> void:
	var mind := NpcMindState.new("elder")
	_hits(mind, "assault:1", 10)
	var before: float = _trust(mind)
	assert_true(absf(before) <= NpcIncidentBudget.BUDGET + _TOLERANCE)
	var death: NpcObservation = _observation("assault:1:death", "actor_died", "assault:1", 502.0)
	assert_eq(mind.incident_budget.escalation_for("player", death), NpcIncidentBudget.FATAL)
	_apply(mind, death)
	var after_death: float = _trust(mind)
	assert_true(after_death < before - _TOLERANCE, "A death is a new escalation")
	assert_true(absf(after_death - before) <= NpcIncidentBudget.BUDGET + _TOLERANCE)
	for index: int in range(5):
		_apply(mind, _observation("assault:1:death:%d" % index, "actor_died", "assault:1", 503.0))
	assert_true(absf(_trust(mind) - before) <= NpcIncidentBudget.BUDGET + _TOLERANCE,
		"Only one fresh budget opens for the fatal kind")
	assert_true(absf(_trust(mind) - after_death) <= NpcIncidentBudget.BUDGET + _TOLERANCE)
	_hits(mind, "assault:1", 3, 504.0)
	assert_true(absf(_trust(mind) - before) <= NpcIncidentBudget.BUDGET + _TOLERANCE,
		"Further ordinary hits do not reopen the spent ordinary budget")

func test_fatal_evidence_is_recognised_by_its_fact_not_only_its_kind() -> void:
	var budget := NpcIncidentBudget.new()
	var fatal: NpcObservation = _observation("blow", "actor_hurt", "assault:1", 500.0)
	assert_eq(budget.escalation_for("player", fatal), NpcIncidentBudget.ORDINARY)
	fatal.facts["fatal"] = true
	assert_eq(budget.escalation_for("player", fatal), NpcIncidentBudget.FATAL)

func test_attacking_a_surrendered_subject_opens_one_budget() -> void:
	var mind := NpcMindState.new("elder")
	_hits(mind, "assault:1", 10)
	var before: float = _trust(mind)
	_apply(mind, _observation("assault:1:yield", "surrender", "assault:1", 505.0, "surrendered"), {})
	assert_true(absf(_trust(mind) - before) < _TOLERANCE, "Surrendering is not itself an offence")
	var violation: NpcObservation = _observation("assault:1:after", "actor_hurt", "assault:1", 510.0)
	assert_eq(mind.incident_budget.escalation_for("player", violation),
		NpcIncidentBudget.SURRENDER_VIOLATION)
	_apply(mind, violation)
	var after_violation: float = _trust(mind)
	assert_true(after_violation < before - _TOLERANCE)
	for index: int in range(6):
		_apply(mind, _observation("assault:1:after:%d" % index, "actor_hurt", "assault:1", 511.0 + index))
	assert_true(absf(_trust(mind) - before) <= NpcIncidentBudget.BUDGET + _TOLERANCE,
		"Repeated strikes after the surrender spend only the one violation budget")

func test_an_attack_long_after_a_surrender_is_ordinary() -> void:
	var mind := NpcMindState.new("elder")
	_apply(mind, _observation("yield", "surrender", "assault:1", 500.0, "surrendered"), {})
	var late: NpcObservation = _observation("late", "actor_hurt", "assault:1",
		500.0 + NpcIncidentBudget.SURRENDER_WINDOW_MINUTES + 1.0)
	assert_eq(mind.incident_budget.escalation_for("player", late), NpcIncidentBudget.ORDINARY)

func test_a_pending_surrender_counts_when_the_attack_is_appraised_first() -> void:
	var mind := NpcMindState.new("elder")
	assert_true(mind.evidence.enqueue(
		_observation("yield", "surrender", "assault:1", 505.0, "surrendered")))
	var attack: NpcObservation = _observation("after", "actor_hurt", "assault:1", 506.0)
	assert_eq(mind.incident_budget.escalation_for("player", attack, mind.evidence.pending_observations()),
		NpcIncidentBudget.SURRENDER_VIOLATION)
	assert_eq(mind.incident_budget.escalation_for("player", attack), NpcIncidentBudget.ORDINARY)

func test_a_second_incident_has_its_own_budget() -> void:
	var mind := NpcMindState.new("elder")
	_hits(mind, "assault:1", 10)
	var after_first: float = _trust(mind)
	_hits(mind, "assault:2", 10, 600.0)
	var after_second: float = _trust(mind)
	assert_true(after_second < after_first - _TOLERANCE, "A different incident is not capped by the first")
	assert_true(absf(after_second - after_first) <= NpcIncidentBudget.BUDGET + _TOLERANCE)
	assert_eq(mind.incident_budget.spent("player", "assault:1", NpcIncidentBudget.ORDINARY).trust,
		mind.incident_budget.spent("player", "assault:2", NpcIncidentBudget.ORDINARY).trust)

func test_evidence_without_an_incident_is_its_own_incident() -> void:
	var mind := NpcMindState.new("elder")
	_apply(mind, _observation("one", "actor_hurt", "", 500.0))
	_apply(mind, _observation("two", "actor_hurt", "", 501.0))
	assert_true(absf(_trust(mind) - -0.16) < _TOLERANCE)

func test_budgets_are_kept_per_subject() -> void:
	var mind := NpcMindState.new("elder")
	_hits(mind, "assault:1", 10)
	assert_true(mind.incident_budget.spent("mira", "assault:1", NpcIncidentBudget.ORDINARY).is_empty())
	assert_eq(mind.incident_budget.allowance("mira", "assault:1", NpcIncidentBudget.ORDINARY,
		_delta()).trust, -0.08)

func test_budget_survives_a_save_round_trip() -> void:
	var mind := NpcMindState.new("elder")
	_hits(mind, "assault:1", 10)
	_apply(mind, _observation("assault:1:yield", "surrender", "assault:1", 505.0, "surrendered"), {})
	var restored := NpcMindState.new("elder")
	assert_true(restored.from_data(_round_trip(mind.to_data())))
	assert_eq(restored.incident_budget.to_data(), mind.incident_budget.to_data())
	assert_eq(restored.incident_budget.spent("player", "assault:1", NpcIncidentBudget.ORDINARY).trust,
		mind.incident_budget.spent("player", "assault:1", NpcIncidentBudget.ORDINARY).trust)
	var before: float = _trust(restored)
	_hits(restored, "assault:1", 5, 520.0)
	assert_true(absf(_trust(restored) - before) <= NpcIncidentBudget.BUDGET + _TOLERANCE)
	var rejoined: NpcObservation = _observation("assault:1:after", "actor_hurt", "assault:1", 510.0)
	assert_eq(restored.incident_budget.escalation_for("player", rejoined),
		NpcIncidentBudget.SURRENDER_VIOLATION, "The seen surrender is saved too")

func test_saved_budget_leaves_no_room_to_farm_after_a_reload() -> void:
	var mind := NpcMindState.new("elder")
	_hits(mind, "assault:1", 10)
	var restored := NpcMindState.new("elder")
	assert_true(restored.from_data(_round_trip(mind.to_data())))
	var before: float = _trust(restored)
	_hits(restored, "assault:1", 10, 560.0)
	assert_true(absf(_trust(restored) - before) < _TOLERANCE)

func test_saves_without_a_budget_still_load_with_an_empty_one() -> void:
	var data: Dictionary = NpcMindState.new("elder").to_data()
	data.erase("incident_budget")
	var mind := NpcMindState.new("elder")
	assert_true(mind.from_data(data))
	assert_eq(mind.incident_budget.to_data(), NpcIncidentBudget.new().to_data())

func _budget_with_one_record() -> Dictionary:
	var budget := NpcIncidentBudget.new()
	budget.spend("player", "assault:1", NpcIncidentBudget.ORDINARY, {"trust": -0.1})
	budget.record_surrender("player", 505.0)
	return _round_trip(budget.to_data())

func test_invalid_data_is_rejected_without_changing_the_budget() -> void:
	assert_true(NpcIncidentBudget.is_valid_data(_budget_with_one_record()))
	var broken: Array[Dictionary] = []
	var data: Dictionary = _budget_with_one_record()
	data["version"] = 2
	broken.append(data)
	data = _budget_with_one_record()
	data["extra"] = 1
	broken.append(data)
	data = _budget_with_one_record()
	data.erase("surrenders")
	broken.append(data)
	data = _budget_with_one_record()
	data["records"][0]["kind"] = "escalated"
	broken.append(data)
	data = _budget_with_one_record()
	data["records"][0]["subject"] = ""
	broken.append(data)
	data = _budget_with_one_record()
	data["records"][0]["incident_id"] = 7
	broken.append(data)
	data = _budget_with_one_record()
	data["records"][0]["used"] = {"trust": NpcIncidentBudget.BUDGET + 0.01}
	broken.append(data)
	data = _budget_with_one_record()
	data["records"][0]["used"] = {"trust": -0.01}
	broken.append(data)
	data = _budget_with_one_record()
	data["records"][0]["used"] = {"loyalty": 0.05}
	broken.append(data)
	data = _budget_with_one_record()
	data["records"][0]["used"] = {"trust": "lots"}
	broken.append(data)
	data = _budget_with_one_record()
	data["records"][0].erase("used")
	broken.append(data)
	data = _budget_with_one_record()
	data["records"].append(data["records"][0].duplicate(true))
	broken.append(data)
	data = _budget_with_one_record()
	data["surrenders"] = {"player": "yesterday"}
	broken.append(data)
	data = _budget_with_one_record()
	data["surrenders"] = {"": 5.0}
	broken.append(data)
	data = _budget_with_one_record()
	data["records"] = []
	data["records"].resize(NpcIncidentBudget.MAX_RECORDS + 1)
	broken.append(data)
	var budget := NpcIncidentBudget.new()
	assert_true(budget.from_data(_budget_with_one_record()))
	var kept: Dictionary = budget.to_data()
	for candidate: Dictionary in broken:
		assert_false(NpcIncidentBudget.is_valid_data(candidate), str(candidate))
		assert_false(budget.from_data(candidate))
		assert_eq(budget.to_data(), kept)
	assert_false(NpcIncidentBudget.is_valid_data("budget"))
	assert_false(NpcIncidentBudget.is_valid_data(null))

func test_a_mind_with_an_invalid_budget_is_rejected_whole() -> void:
	var mind := NpcMindState.new("elder")
	_hits(mind, "assault:1", 3)
	var data: Dictionary = _round_trip(mind.to_data())
	data["incident_budget"]["records"][0]["used"] = {"trust": 5.0}
	assert_false(NpcMindState.is_valid_data(data, "elder"))
	var target := NpcMindState.new("elder")
	assert_false(target.from_data(data))
	assert_eq(target.to_data(), NpcMindState.new("elder").to_data())

func test_oldest_records_are_forgotten_beyond_the_cap() -> void:
	var budget := NpcIncidentBudget.new()
	for index: int in range(NpcIncidentBudget.MAX_RECORDS + 5):
		budget.spend("player", "incident:%d" % index, NpcIncidentBudget.ORDINARY, {"trust": -0.05})
	assert_eq(budget.to_data().records.size(), NpcIncidentBudget.MAX_RECORDS)
	assert_true(budget.spent("player", "incident:0", NpcIncidentBudget.ORDINARY).is_empty())
	assert_false(budget.spent("player", "incident:%d" % (NpcIncidentBudget.MAX_RECORDS + 4),
		NpcIncidentBudget.ORDINARY).is_empty())
