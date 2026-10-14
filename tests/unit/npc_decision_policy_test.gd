extends "res://tests/test_case.gd"

var _tuning: NpcBehaviorTuning

func before_each() -> void:
	_tuning = NpcBehaviorTuning.new()

static func _noul(probability: float) -> Dictionary:
	return {"type": "noul", "noul": probability}

static func _score(value: float, confidence: float = 0.8) -> Dictionary:
	return {"type": "score", "score": value, "confidence": confidence}

static func _choice(value: String, confidence: float = 0.85) -> Dictionary:
	return {"type": "choice", "choice": value, "confidence": confidence}

static func _result(kind: StringName, judgments: Dictionary,
		outcome: NpcDecisionResult.Outcome = NpcDecisionResult.Outcome.SUCCESS) -> NpcDecisionResult:
	var ticket: NpcDecisionTicket = NpcDecisionTicket.create("garrin_holt", kind)
	return NpcDecisionResult.new(outcome, ticket, judgments)

## Unchanged answers for every dimension toward `subject`, then `changes` applied:
## {dimension: [direction, magnitude, direction confidence, magnitude confidence]}.
static func _dispositions(judgments: Dictionary, subject: String, changes: Dictionary = {}) -> void:
	for dimension: String in NpcDecisionService.DIMENSIONS:
		var change: Array = changes.get(dimension, ["UNCHANGED", 0.0, 0.85, 0.8])
		var prefix: String = "disposition:%s:%s:" % [subject, dimension]
		judgments[prefix + "direction"] = _choice(change[0], change[2])
		judgments[prefix + "magnitude"] = _score(change[1], change[3])

func _appraisal(danger: float, changes: Dictionary = {}) -> NpcDecisionPolicy.Appraisal:
	var judgments: Dictionary = {"immediate_danger": _noul(danger), "remember": _noul(0.69),
		"importance": _score(2.0, 0.1), "fear": _score(4.0), "anger": _score(4.0, 0.6),
		"grief": _score(0.0), "relief": _score(0.0)}
	_dispositions(judgments, "player", changes)
	return NpcDecisionPolicy.appraisal(_result(NpcDecisionTicket.APPRAISE, judgments), _tuning)

func test_noul_gates_compare_the_probability_with_the_tuning_threshold() -> void:
	var calm: NpcDecisionPolicy.Appraisal = _appraisal(0.49)
	assert_false(calm.immediate_danger)
	assert_false(calm.remember, "0.69 is below the remember threshold")
	assert_true(_appraisal(0.5).immediate_danger)
	_tuning.danger_threshold = 0.4
	assert_true(_appraisal(0.49).immediate_danger)

func test_low_confidence_scores_and_choices_take_the_neutral_fallback() -> void:
	var appraised: NpcDecisionPolicy.Appraisal = _appraisal(0.0, {
		"trust": ["NEGATIVE", 4.0, 0.6, 0.8], "fear": ["POSITIVE", 4.0, 0.9, 0.5],
		"suspicion": ["POSITIVE", 2.0, 0.65, 0.65]})
	assert_eq(appraised.emotions.fear, 1.0)
	assert_eq(appraised.emotions.anger, 0.0, "A low-confidence emotion has no intensity")
	assert_eq(appraised.importance, 0.5, "Importance orders retention and is not gated")
	assert_eq(appraised.dispositions.player.keys(), ["suspicion"],
		"An unconfident direction or magnitude leaves the disposition unchanged")

func test_disposition_delta_scales_with_magnitude_up_to_the_incident_maximum() -> void:
	var appraised: NpcDecisionPolicy.Appraisal = _appraisal(0.0, {
		"trust": ["NEGATIVE", 4.0, 0.9, 0.9], "respect": ["POSITIVE", 2.0, 0.9, 0.9],
		"affection": ["UNCHANGED", 4.0, 0.9, 0.9]})
	assert_eq(appraised.dispositions.player.trust, -NpcIncidentBudget.MAX_CHANGE)
	assert_eq(appraised.dispositions.player.respect, NpcIncidentBudget.MAX_CHANGE / 2.0)
	assert_false(appraised.dispositions.player.has("affection"))

func _goal(judgments: Dictionary, candidates: Array[String]) -> NpcDecisionPolicy.GoalChoice:
	var result: NpcDecisionResult = _result(NpcDecisionTicket.SELECT_GOAL, judgments)
	result.ticket.candidate_ids = candidates
	return NpcDecisionPolicy.goal_choice(result, _tuning)

func test_goal_choice_needs_confident_minimum_suitability_and_bounds_duration() -> void:
	var candidates: Array[String] = ["WORK", "MARKET", "REST"]
	var picked: NpcDecisionPolicy.GoalChoice = _goal({
		"suitability:WORK": _score(3.0), "duration:WORK": _choice("BRIEF"),
		"suitability:MARKET": _score(4.0, 0.3), "duration:MARKET": _choice("EXTENDED"),
		"suitability:REST": _score(3.0), "duration:REST": _choice("EXTENDED")}, candidates)
	assert_eq(picked.candidate_id, "WORK", "Unconfident MARKET is ignored and ties keep order")
	assert_eq(picked.duration_minutes, _tuning.brief_goal_minutes)
	var unsure: NpcDecisionPolicy.GoalChoice = _goal({
		"suitability:WORK": _score(2.0), "duration:WORK": _choice("EXTENDED", 0.2),
		"suitability:MARKET": _score(1.0), "duration:MARKET": _choice("BRIEF"),
		"suitability:REST": _score(1.5), "duration:REST": _choice("BRIEF")}, candidates)
	assert_eq(unsure.candidate_id, "WORK")
	assert_eq(unsure.duration_minutes, _tuning.ordinary_goal_minutes, "Unconfident duration is ORDINARY")
	var none: NpcDecisionPolicy.GoalChoice = _goal({
		"suitability:WORK": _score(1.75), "duration:WORK": _choice("BRIEF"),
		"suitability:MARKET": _score(1.0), "duration:MARKET": _choice("BRIEF"),
		"suitability:REST": _score(0.0), "duration:REST": _choice("BRIEF")}, candidates)
	assert_eq(none.candidate_id, "", "Nothing suitable keeps the current goal")
	assert_eq(none.duration_minutes, 0.0)

func test_social_falls_back_to_small_talk_and_the_default_tone() -> void:
	var result: NpcDecisionResult = _result(NpcDecisionTicket.SOCIAL, {"engage": _noul(0.4),
		"topic": _choice("news:attack", 0.5), "tone": _choice("concerned", 0.5)})
	var decided: NpcDecisionPolicy.Social = NpcDecisionPolicy.social(result, "friendly", _tuning)
	assert_false(decided.engage)
	assert_eq(decided.topic, NpcDecisionService.SMALL_TALK)
	assert_eq(decided.tone, "friendly")

func test_utterance_speaks_only_with_a_confident_permitted_intent() -> void:
	var permitted: Array[String] = ["warn"]
	var cases: Array[Array] = [[0.9, "warn", 0.9, true], [0.4, "warn", 0.9, false],
		[0.9, "warn", 0.5, false], [0.9, "protest", 0.9, false]]
	for case: Array in cases:
		var result: NpcDecisionResult = _result(NpcDecisionTicket.UTTERANCE,
			{"speak": _noul(case[0]), "intent": _choice(case[1], case[2])})
		var decided: NpcDecisionPolicy.Utterance = NpcDecisionPolicy.utterance(result, permitted, _tuning)
		assert_eq(decided.speak, case[3], str(case))
		assert_eq(decided.intent, "warn" if case[3] else "")

func _listen(believe: float, messenger_changes: Dictionary) -> NpcDecisionPolicy.Listening:
	var judgments: Dictionary = {"believe_account": _noul(believe), "remember": _noul(0.9),
		"importance": _score(3.0)}
	_dispositions(judgments, "mirelle", messenger_changes)
	_dispositions(judgments, "player", {"trust": ["NEGATIVE", 4.0, 0.9, 0.9]})
	return NpcDecisionPolicy.listening(_result(NpcDecisionTicket.LISTEN, judgments), "mirelle", _tuning)

func test_listening_never_blames_the_messenger_for_the_account() -> void:
	var believed: NpcDecisionPolicy.Listening = _listen(0.9, {})
	assert_true(believed.believe)
	assert_eq(believed.dispositions.player.trust, -NpcIncidentBudget.MAX_CHANGE)
	assert_false(believed.dispositions.has("mirelle"), "The accused's blame stays off the messenger")
	var doubted: NpcDecisionPolicy.Listening = _listen(0.5, {"trust": ["NEGATIVE", 2.0, 0.9, 0.9]})
	assert_false(doubted.believe)
	assert_false(doubted.dispositions.has("player"), "A disbelieved account changes no accused")
	assert_eq(doubted.dispositions.mirelle.trust, -NpcIncidentBudget.MAX_CHANGE / 2.0,
		"The messenger changes only through answers about the messenger")
	assert_true(doubted.remember)
	assert_eq(doubted.importance, 0.75)

func test_unsuccessful_or_mismatched_results_map_to_neutral_records() -> void:
	var failed: NpcDecisionResult = _result(NpcDecisionTicket.UTTERANCE,
		{"speak": _noul(1.0), "intent": _choice("warn", 1.0)}, NpcDecisionResult.Outcome.TIMEOUT)
	var permitted: Array[String] = ["warn"]
	assert_false(NpcDecisionPolicy.utterance(failed, permitted, _tuning).speak)
	var other_kind: NpcDecisionResult = _result(NpcDecisionTicket.SOCIAL, {"engage": _noul(1.0)})
	assert_false(NpcDecisionPolicy.appraisal(other_kind, _tuning).immediate_danger)
	assert_eq(NpcDecisionPolicy.social(null, "reserved", _tuning).tone, "reserved")
