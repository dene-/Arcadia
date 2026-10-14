extends "res://tests/test_case.gd"

const Routine = preload("res://tests/unit/npc_routine_task_test.gd")
const SEED: int = 4242
const NOW: float = 600.0

## A task that reports whatever engagement the test sets, as the real tasks do once confirmed.
class EngagedTask extends NpcTask:
	var engagement: StringName = &""

	func _init(activity: StringName = &"") -> void:
		kind = &"routine"
		engagement = activity

	func confirmed_engagement() -> StringName:
		return engagement

var _tuning: NpcBehaviorTuning

func before_each() -> void:
	_tuning = NpcBehaviorTuning.new()

static func _score(value: float, confidence: float = 0.8) -> Dictionary:
	return {"type": "score", "score": value, "confidence": confidence}

static func _choice(value: String, confidence: float = 0.85) -> Dictionary:
	return {"type": "choice", "choice": value, "confidence": confidence}

## One SELECT_GOAL answer: `ratings` is candidate id -> suitability 0..4, every duration BRIEF.
static func _answer(ratings: Dictionary,
		outcome: NpcDecisionResult.Outcome = NpcDecisionResult.Outcome.SUCCESS) -> NpcDecisionResult:
	var ticket: NpcDecisionTicket = NpcDecisionTicket.create("a", NpcDecisionTicket.SELECT_GOAL)
	var judgments: Dictionary = {}
	for candidate: String in ratings:
		ticket.candidate_ids.append(candidate)
		judgments["suitability:" + candidate] = _score(float(ratings[candidate]))
		judgments["duration:" + candidate] = _choice("BRIEF")
	return NpcDecisionResult.new(outcome, ticket, judgments)

static func _frame(components: Dictionary, incumbent: String = "", incumbent_minutes: float = INF,
		urgent: bool = false, tie_seed: int = 0) -> NpcDecisionPolicy.GoalFrame:
	var frame := NpcDecisionPolicy.GoalFrame.new()
	frame.components = components
	frame.incumbent = incumbent
	frame.incumbent_minutes = incumbent_minutes
	frame.urgent = urgent
	frame.tie_seed = tie_seed
	return frame

static func _options() -> Array[Dictionary]:
	return [{"id": "PLAN", "kind": "work", "place": "work:a"},
		{"id": "SOCIAL", "kind": "socialize", "place": "square"},
		{"id": "REST", "kind": "rest", "place": "home:a"},
		{"id": "WALK", "kind": "walk", "place": "garden"}]

## Two candidates with identical components and ratings: only the seed can order them.
static func _twins() -> Array[Dictionary]:
	return [{"id": "PLAN", "kind": "work", "place": "work:a"},
		{"id": "WALK", "kind": "walk", "place": "garden"},
		{"id": "STROLL", "kind": "walk", "place": "market"}]

func _neutral_mind() -> NpcMindState:
	var mind := NpcMindState.new("a")
	mind.needs = {"hunger": 0.1, "fatigue": 0.1, "social": 0.1}
	return mind

func _chosen(options: Array[Dictionary], mind: NpcMindState, traits: Dictionary,
		person: Dictionary, ratings: Dictionary) -> NpcDecisionPolicy.GoalChoice:
	var frame: NpcDecisionPolicy.GoalFrame = TownLife.goal_frame(options, mind, traits, person,
		NOW, SEED, _tuning)
	return NpcDecisionPolicy.goal_choice(_answer(ratings), _tuning, frame)

func test_sociable_and_reserved_residents_choose_differently_from_identical_answers() -> void:
	var ratings: Dictionary = {"PLAN": 3.0, "SOCIAL": 3.0, "REST": 3.0, "WALK": 3.0}
	var sociable: NpcDecisionPolicy.GoalChoice = _chosen(_options(), _neutral_mind(),
		{"sociability": 0.95}, {}, ratings)
	var reserved: NpcDecisionPolicy.GoalChoice = _chosen(_options(), _neutral_mind(),
		{"sociability": 0.05}, {}, ratings)
	assert_eq(sociable.scores.PLAN.total, reserved.scores.PLAN.total,
		"a candidate no trait touches scores identically for both")
	assert_true(float(sociable.scores.SOCIAL.personality) > 0.0)
	assert_true(float(reserved.scores.SOCIAL.personality) < 0.0)
	assert_eq(sociable.scores.PLAN.suitability, reserved.scores.PLAN.suitability,
		"the provider's answer is the same for both")
	assert_eq(sociable.scores.PLAN.total, reserved.scores.PLAN.total,
		"a candidate personality does not touch scores identically")

func test_scores_keep_every_weighted_component_for_traces() -> void:
	var mind: NpcMindState = _neutral_mind()
	mind.needs.social = 0.5
	var choice: NpcDecisionPolicy.GoalChoice = _chosen(_options(), mind, {"sociability": 0.75}, {},
		{"PLAN": 2.0, "SOCIAL": 3.0, "REST": 1.0, "WALK": 0.0})
	var social: Dictionary = choice.scores.SOCIAL
	for key: String in ["suitability", "need", "obligation", "concern", "commitment", "personality",
			"switching", "total", "eligible"]:
		assert_true(social.has(key), key)
	assert_eq(social.suitability, 3.0)
	assert_eq(social.need, 0.5)
	assert_eq(social.personality, 0.5)
	var expected: float = 3.0 / 4.0 + _tuning.goal_need_weight * 0.5 \
		+ _tuning.goal_personality_weight * 0.5
	assert_true(absf(float(social.total) - expected) < 0.0001, "total %s vs %s" % [social.total, expected])
	assert_eq(choice.scores.PLAN.obligation, 1.0, "today's plan is the full obligation")
	assert_false(choice.scores.REST.eligible, "an unsuitable rest with no pressing need is not a candidate")
	assert_false(choice.scores.WALK.eligible)

func test_endorsed_priority_and_plan_kept_choices() -> void:
	var endorsed: NpcDecisionPolicy.GoalChoice = NpcDecisionPolicy.goal_choice(
		_answer({"PLAN": 3.0, "WALK": 1.0}), _tuning, _frame({"PLAN": {}, "WALK": {}}))
	assert_eq(endorsed.candidate_id, "PLAN")
	assert_true(endorsed.endorsed)
	assert_eq(endorsed.duration_minutes, _tuning.brief_goal_minutes)
	# The judgment rated nothing suitable: a commitment makes its candidate eligible on its own.
	var committed: NpcDecisionPolicy.GoalChoice = NpcDecisionPolicy.goal_choice(
		_answer({"PLAN": 1.0, "CHECK": 0.0}), _tuning,
		_frame({"PLAN": {"obligation": 1.0}, "CHECK": {"commitment": 0.6}}))
	assert_eq(committed.candidate_id, "CHECK")
	assert_false(committed.endorsed, "only the resident's own priorities chose it")
	# A pressing need does the same for the candidate that relieves it.
	var hungry: NpcDecisionPolicy.GoalChoice = NpcDecisionPolicy.goal_choice(
		_answer({"PLAN": 1.0, "MEAL": 1.0}), _tuning,
		_frame({"PLAN": {}, "MEAL": {"need": _tuning.need_pressing}}))
	assert_eq(hungry.candidate_id, "MEAL")
	assert_false(hungry.endorsed)
	var peckish: NpcDecisionPolicy.GoalChoice = NpcDecisionPolicy.goal_choice(
		_answer({"PLAN": 1.0, "MEAL": 1.0}), _tuning,
		_frame({"PLAN": {}, "MEAL": {"need": _tuning.need_pressing - 0.01}}))
	assert_eq(peckish.candidate_id, "", "a need below pressing cannot override the judgment")
	# Nothing eligible: no candidate, so the caller keeps today's plan for plan_kept_minutes.
	assert_eq(peckish.duration_minutes, 0.0)
	assert_eq(peckish.scores.size(), 2, "the breakdown is kept even when nothing was chosen")

func test_a_failed_or_missing_provider_answer_leaves_only_the_residents_own_priorities() -> void:
	var frame: NpcDecisionPolicy.GoalFrame = _frame({"PLAN": {"obligation": 1.0},
		"CHECK": {"commitment": 0.6}})
	for result: NpcDecisionResult in [null, _answer({"PLAN": 4.0, "CHECK": 4.0},
			NpcDecisionResult.Outcome.TIMEOUT)]:
		var choice: NpcDecisionPolicy.GoalChoice = NpcDecisionPolicy.goal_choice(result, _tuning, frame)
		assert_eq(choice.candidate_id, "CHECK")
		assert_false(choice.endorsed)
		assert_eq(choice.duration_minutes, _tuning.ordinary_goal_minutes)
	var calm: NpcDecisionPolicy.GoalChoice = NpcDecisionPolicy.goal_choice(
		_answer({"PLAN": 4.0}, NpcDecisionResult.Outcome.TIMEOUT), _tuning,
		_frame({"PLAN": {"obligation": 1.0}}))
	assert_eq(calm.candidate_id, "", "without an answer or a priority the plan is kept")

func test_commitment_minimum_keeps_the_incumbent_against_a_clearly_better_candidate() -> void:
	var better: Dictionary = {"A": 2.0, "B": 4.0}
	var young: NpcDecisionPolicy.GoalChoice = NpcDecisionPolicy.goal_choice(_answer(better), _tuning,
		_frame({"A": {}, "B": {}}, "A", _tuning.commitment_minimum_minutes - 0.5))
	assert_eq(young.candidate_id, "A", "a goal younger than the minimum is not dropped")
	var seasoned: NpcDecisionPolicy.GoalChoice = NpcDecisionPolicy.goal_choice(_answer(better), _tuning,
		_frame({"A": {}, "B": {}}, "A", _tuning.commitment_minimum_minutes))
	assert_eq(seasoned.candidate_id, "B", "the minimum has passed and the gap exceeds the advantage")
	var unsuitable: NpcDecisionPolicy.GoalChoice = NpcDecisionPolicy.goal_choice(
		_answer({"A": 0.5, "B": 3.0}), _tuning,
		_frame({"A": {}, "B": {}}, "A", 1.0))
	assert_eq(unsuitable.candidate_id, "B", "an incumbent no longer eligible is not protected")

func test_switch_advantage_absorbs_small_differences_and_yields_to_large_ones() -> void:
	var seasoned: float = _tuning.commitment_minimum_minutes + 30.0
	var gap: float = _tuning.switch_advantage * 4.0 # the advantage expressed in suitability points
	var close: NpcDecisionPolicy.GoalChoice = NpcDecisionPolicy.goal_choice(
		_answer({"A": 2.0, "B": 2.0 + gap * 0.5}), _tuning, _frame({"A": {}, "B": {}}, "A", seasoned))
	assert_eq(close.candidate_id, "A")
	assert_eq(close.scores.A.switching, _tuning.switch_advantage)
	assert_eq(close.scores.B.switching, 0.0)
	var far: NpcDecisionPolicy.GoalChoice = NpcDecisionPolicy.goal_choice(
		_answer({"A": 2.0, "B": 2.0 + gap * 1.5}), _tuning, _frame({"A": {}, "B": {}}, "A", seasoned))
	assert_eq(far.candidate_id, "B")

func test_small_score_swings_never_switch_the_goal_over_many_decisions() -> void:
	var incumbent: String = "A"
	var minutes: float = 0.0
	var switches: int = 0
	for step: int in range(40):
		# The judgment drifts between decisions, but never by more than the switch advantage.
		var swing: float = 0.2 if step % 2 == 0 else -0.2
		var choice: NpcDecisionPolicy.GoalChoice = NpcDecisionPolicy.goal_choice(
			_answer({"A": 2.4 - swing, "B": 2.4 + swing}), _tuning,
			_frame({"A": {}, "B": {}}, incumbent, minutes, false, step))
		if choice.candidate_id != incumbent:
			switches += 1
			incumbent = choice.candidate_id
			minutes = 0.0
		minutes += 6.0
	assert_eq(switches, 0)

func test_urgent_danger_bypasses_both_inertia_terms() -> void:
	var answer: NpcDecisionResult = _answer({"WORK": 2.5, "SHELTER": 4.0})
	var calm: NpcDecisionPolicy.GoalChoice = NpcDecisionPolicy.goal_choice(answer, _tuning,
		_frame({"WORK": {}, "SHELTER": {}}, "WORK", 1.0))
	assert_eq(calm.candidate_id, "WORK")
	var urgent: NpcDecisionPolicy.GoalChoice = NpcDecisionPolicy.goal_choice(answer, _tuning,
		_frame({"WORK": {}, "SHELTER": {}}, "WORK", 1.0, true))
	assert_eq(urgent.candidate_id, "SHELTER", "a goal younger than the minimum is dropped for danger")
	assert_eq(urgent.scores.WORK.switching, 0.0, "and the incumbent earns no switch advantage")
	var fearful: NpcMindState = _neutral_mind()
	assert_true(fearful.feel("fear", 0.9, "player", "ev:1", "", NOW))
	var frame: NpcDecisionPolicy.GoalFrame = TownLife.goal_frame(
		[{"id": "WORK", "kind": "work", "place": "work:a"},
			{"id": "REST", "kind": "rest", "place": "home:a"}], fearful, {}, {"activity": "work",
			"place": "work:a", "since": NOW - 1.0}, NOW, SEED, _tuning)
	assert_true(frame.urgent, "fear at or above urgent_fear is urgent")
	assert_eq(frame.incumbent, "WORK")
	var settled: NpcMindState = _neutral_mind()
	assert_true(settled.feel("fear", 0.5, "player", "ev:1", "", NOW))
	assert_false(TownLife.goal_frame([{"id": "WORK", "kind": "work", "place": "work:a"}], settled, {},
		{}, NOW, SEED, _tuning).urgent)

func test_the_incumbent_is_the_current_activity_at_its_place_and_age_comes_from_since() -> void:
	var person: Dictionary = {"activity": "socialize", "place": "square", "since": NOW - 3.0}
	var frame: NpcDecisionPolicy.GoalFrame = TownLife.goal_frame(_options(), _neutral_mind(), {},
		person, NOW, SEED, _tuning)
	assert_eq(frame.incumbent, "SOCIAL")
	assert_eq(frame.incumbent_minutes, 3.0)
	person.place = "market"
	assert_eq(TownLife.goal_frame(_options(), _neutral_mind(), {}, person, NOW, SEED, _tuning).incumbent,
		"", "the same activity somewhere else is a different goal")
	person.place = "square"
	person.erase("since")
	var legacy: NpcDecisionPolicy.GoalFrame = TownLife.goal_frame(_options(), _neutral_mind(), {},
		person, NOW, SEED, _tuning)
	assert_eq(legacy.incumbent, "SOCIAL")
	assert_eq(legacy.incumbent_minutes, INF, "an older save has no inertia")

func _tied_choice(seed_value: int) -> String:
	var frame: NpcDecisionPolicy.GoalFrame = _frame({"PLAN": {}, "WALK": {}, "STROLL": {}}, "", INF,
		false, seed_value)
	return NpcDecisionPolicy.goal_choice(_answer({"PLAN": 1.0, "WALK": 3.0, "STROLL": 3.0}), _tuning,
		frame).candidate_id

func test_seeded_tie_break_is_repeatable_and_depends_on_the_seed() -> void:
	var seen: Dictionary = {}
	for seed_value: int in range(32):
		var first: String = _tied_choice(seed_value)
		assert_eq(_tied_choice(seed_value), first, "seed %d" % seed_value)
		assert_true(first in ["WALK", "STROLL"])
		seen[first] = true
	assert_eq(seen.size(), 2, "different seeds break the tie both ways")

func test_tie_seed_follows_the_saved_decision_sequence() -> void:
	var first := NpcMindState.new("a")
	var second := NpcMindState.new("a")
	var traits: Dictionary = {}
	var one: NpcDecisionPolicy.GoalFrame = TownLife.goal_frame(_twins(), first, traits, {}, NOW, SEED, _tuning)
	var same: NpcDecisionPolicy.GoalFrame = TownLife.goal_frame(_twins(), second, traits, {}, NOW, SEED, _tuning)
	assert_eq(one.tie_seed, same.tie_seed, "same seed and sequence")
	var next: NpcDecisionPolicy.GoalFrame = TownLife.goal_frame(_twins(), first, traits, {}, NOW, SEED, _tuning)
	assert_ne(next.tie_seed, one.tie_seed, "each decision draws its own tie seed")
	assert_eq(first.decision_sequence, 2)
	var other_seed: NpcDecisionPolicy.GoalFrame = TownLife.goal_frame(_twins(), NpcMindState.new("a"),
		traits, {}, NOW, SEED + 1, _tuning)
	assert_ne(other_seed.tie_seed, one.tie_seed)
	var other_resident: NpcDecisionPolicy.GoalFrame = TownLife.goal_frame(_twins(),
		NpcMindState.new("b"), traits, {}, NOW, SEED, _tuning)
	assert_ne(other_resident.tie_seed, one.tie_seed)
	var ratings: Dictionary = {"PLAN": 1.0, "WALK": 3.0, "STROLL": 3.0}
	var replay: Array[String] = []
	for index: int in range(2):
		var mind := NpcMindState.new("a")
		for decision: int in range(6):
			var frame: NpcDecisionPolicy.GoalFrame = TownLife.goal_frame(_twins(), mind, traits, {},
				NOW, SEED, _tuning)
			replay.append(NpcDecisionPolicy.goal_choice(_answer(ratings), _tuning, frame).candidate_id)
	assert_eq(replay.slice(0, 6), replay.slice(6, 12), "the same decision sequence replays its choices")

func test_saving_and_loading_midway_gives_the_same_next_choice() -> void:
	var mind := NpcMindState.new("a")
	mind.advance_needs(300.0, false, 0.8, _tuning)
	assert_true(mind.feel("grief", 0.7, "b", "ev:death", "incident:1", NOW - 20.0))
	var commitment: String = mind.commitments.create("check_relative", ["b"] as Array[String],
		[] as Array[String], NOW - 10.0, -1.0, 0.6)
	assert_false(commitment.is_empty())
	for index: int in range(3):
		mind.next_decision()
	var life := TownLifeState.new()
	life.ensure_person("a", SEED, ["a", "b"] as Array[String], ["square"] as Array[String])
	life.minute = NOW
	life.select_activity("a", {"kind": "walk", "place": "garden"}, 45.0, {"service": "jev"})
	life.set_search("a", commitment, 1, 0.0)
	var traits: Dictionary = life.personality_for("a", SEED).traits
	var options: Array[Dictionary] = _twins()
	options.append({"id": "CHECK_RELATIVE", "kind": "check_relative", "place": "home:b",
		"commitment_id": commitment, "subject": "b"})
	var ratings: Dictionary = {"PLAN": 1.0, "WALK": 2.5, "STROLL": 2.5, "CHECK_RELATIVE": 1.0}
	var loaded_mind := NpcMindState.new("a")
	assert_true(loaded_mind.from_data(JSON.parse_string(JSON.stringify(mind.to_data()))))
	var loaded_life := TownLifeState.new()
	assert_true(loaded_life.from_data(JSON.parse_string(JSON.stringify(life.to_data()))))
	assert_eq(loaded_life.search_for("a", commitment), {"step": 1, "deferred_until": 0.0})
	var before: NpcDecisionPolicy.GoalChoice = NpcDecisionPolicy.goal_choice(_answer(ratings), _tuning,
		TownLife.goal_frame(options, mind, traits, life.get_person("a"), NOW + 5.0, SEED, _tuning))
	var after: NpcDecisionPolicy.GoalChoice = NpcDecisionPolicy.goal_choice(_answer(ratings), _tuning,
		TownLife.goal_frame(options, loaded_mind, loaded_life.personality_for("a", SEED).traits,
		loaded_life.get_person("a"), NOW + 5.0, SEED, _tuning))
	assert_eq(before.candidate_id, "CHECK_RELATIVE", "the open commitment is a priority of its own")
	assert_eq(after.candidate_id, before.candidate_id)
	assert_eq(after.scores, before.scores)
	assert_eq(loaded_mind.decision_sequence, mind.decision_sequence)
	# The same round trip while the choice is a pure tie: the saved sequence picks the same side.
	mind.commitments.resolve(commitment, "cancelled", NOW)
	loaded_mind.commitments.resolve(commitment, "cancelled", NOW)
	var tied_before: String = _tie_after_loading(mind, traits, life.get_person("a"))
	var tied_after: String = _tie_after_loading(loaded_mind, traits, loaded_life.get_person("a"))
	assert_eq(tied_after, tied_before)
	assert_true(tied_before in ["WALK", "STROLL"])

func _tie_after_loading(mind: NpcMindState, traits: Dictionary, person: Dictionary) -> String:
	var options: Array[Dictionary] = [{"id": "WALK", "kind": "walk", "place": "garden"},
		{"id": "STROLL", "kind": "walk", "place": "market"}]
	var frame: NpcDecisionPolicy.GoalFrame = TownLife.goal_frame(options, mind, traits,
		person, NOW + 6.0, SEED, _tuning)
	return NpcDecisionPolicy.goal_choice(_answer({"WALK": 3.0, "STROLL": 3.0}), _tuning,
		frame).candidate_id

func _worker(id: String, age: int, job: String, guard: bool = false) -> BaseNpc:
	var npc: BaseNpc = load("res://game/actors/npcs/base_npc.tscn").instantiate()
	npc.npc_data = npc.npc_data.duplicate(true)
	npc.npc_data.profile = NpcProfile.new()
	npc.npc_data.profile.npc_id = StringName(id)
	npc.npc_data.profile.age = age
	npc.npc_data.profile.job = job
	if guard:
		npc.add_to_group(&"town_guards")
	(Engine.get_main_loop() as SceneTree).root.add_child(npc)
	npc.set_physics_process(false)
	return npc

func _engaged(npc: BaseNpc, id: String, activity: StringName, rig: Routine.Rig) -> EngagedTask:
	var brain := NpcBrain.new()
	brain.name = NpcBrain.NODE_NAME
	npc.add_child(brain)
	brain.setup(id, NpcMindState.new(id), npc, rig.executor, _tuning, SEED)
	var task := EngagedTask.new(activity)
	assert_true(brain.request_task(task))
	return task

func test_only_confirmed_work_or_patrol_earns_credit() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var rig := Routine.Rig.new()
	var cases: Array[Dictionary] = [
		{"id": "baker", "age": 40, "job": "baker", "guard": false, "activity": &"work", "credit": true},
		{"id": "baker_resting", "age": 40, "job": "baker", "guard": false, "activity": &"meal", "credit": false},
		{"id": "baker_walking", "age": 40, "job": "baker", "guard": false, "activity": &"", "credit": false},
		{"id": "baker_patrol", "age": 40, "job": "baker", "guard": false, "activity": &"patrol", "credit": false},
		{"id": "pupil", "age": 10, "job": "student", "guard": false, "activity": &"work", "credit": false},
		{"id": "elder", "age": 70, "job": "retired miller", "guard": false, "activity": &"work", "credit": false},
		{"id": "watchman", "age": 35, "job": "guard", "guard": true, "activity": &"patrol", "credit": true},
		{"id": "watchman_work", "age": 35, "job": "guard", "guard": true, "activity": &"work", "credit": false}]
	for case: Dictionary in cases:
		var npc: BaseNpc = _worker(case.id, case.age, case.job, case.guard)
		_engaged(npc, case.id, case.activity, rig)
		assert_eq(npc.earns_work_credit(), case.credit, "%s doing '%s'" % [case.id, case.activity])
		npc.queue_free()
	var bare: BaseNpc = _worker("bare", 40, "baker")
	assert_false(bare.earns_work_credit(), "a resident without a brain earns nothing")
	var engaged: BaseNpc = _worker("interrupted", 40, "baker")
	var task: EngagedTask = _engaged(engaged, "interrupted", &"work", rig)
	assert_true(engaged.earns_work_credit())
	NpcBrain.of(engaged).interrupt(NpcTask.Interrupt.HURT)
	assert_ne(task.status, NpcTask.Status.RUNNING)
	assert_false(engaged.earns_work_credit(), "a suspended task earns nothing")
	bare.queue_free()
	engaged.queue_free()
	rig.dispose()
	await tree.process_frame
