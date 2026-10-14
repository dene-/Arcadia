extends "res://tests/test_case.gd"

const Rig = preload("res://tests/fixtures/npc_processor_rig.gd")
const Appraisals = preload("res://tests/fixtures/npc_appraisal_fixture.gd")
const NPC: String = "vale"

class Body extends RefCounted:
	var health: float = 100.0
	var max_health: float = 100.0

func _mind() -> NpcMindState:
	return NpcMindState.new(NPC)

func _observation(participants: Array, incident_id: String = "") -> NpcObservation:
	var observation := NpcObservation.from_perception(NPC, "event:1", 30.0, &"outdoors",
		{"text": "Voss struck Tess.", "sense": "sight", "participants": participants})
	observation.incident_id = incident_id
	return observation

func _appraisal(emotions: Dictionary[String, float]) -> NpcDecisionPolicy.Appraisal:
	var appraisal: NpcDecisionPolicy.Appraisal = Appraisals.make()
	appraisal.emotions = emotions
	return appraisal

# Needs

func test_needs_start_neutral_and_advance_by_game_minutes() -> void:
	var mind := _mind()
	var tuning := NpcBehaviorTuning.new()
	assert_eq(mind.needs, NpcMindState.neutral_needs(tuning))
	mind.advance_needs(60.0, false, 0.5, tuning)
	assert_true(is_equal_approx(mind.needs.hunger, 0.25 + 60.0 / 480.0))
	assert_true(is_equal_approx(mind.needs.fatigue, 0.2 + 60.0 / 960.0))
	assert_true(is_equal_approx(mind.needs.social, 0.3 + 60.0 / 2880.0))
	var awake: float = mind.needs.fatigue
	mind.advance_needs(60.0, true, 0.5, tuning)
	assert_true(is_equal_approx(mind.needs.fatigue, awake - 60.0 / 480.0), "Sleep eases fatigue")

func test_a_more_sociable_resident_grows_lonely_faster() -> void:
	var tuning := NpcBehaviorTuning.new()
	var shy := _mind()
	var warm := _mind()
	shy.advance_needs(120.0, false, 0.0, tuning)
	warm.advance_needs(120.0, false, 1.0, tuning)
	assert_true(warm.needs.social > shy.needs.social)
	assert_eq(warm.needs.hunger, shy.needs.hunger)

func test_needs_clamp_and_ignore_invalid_time() -> void:
	var tuning := NpcBehaviorTuning.new()
	var mind := _mind()
	var before: Dictionary = mind.needs.duplicate()
	for minutes: float in [0.0, -5.0, NAN, INF]:
		mind.advance_needs(minutes, false, 0.5, tuning)
	mind.advance_needs(10.0, false, NAN, tuning)
	assert_eq(mind.needs, before)
	mind.advance_needs(100000.0, false, 1.0, tuning)
	assert_eq(mind.needs, {"hunger": 1.0, "fatigue": 1.0, "social": 1.0})
	mind.advance_needs(100000.0, true, 1.0, tuning)
	assert_eq(mind.needs.fatigue, 0.0)

func test_a_meal_satisfies_hunger_and_an_exchange_eases_loneliness() -> void:
	var tuning := NpcBehaviorTuning.new()
	var mind := _mind()
	mind.advance_needs(100000.0, false, 1.0, tuning)
	mind.complete_meal(tuning)
	assert_eq(mind.needs.hunger, tuning.meal_hunger)
	mind.needs.hunger = 0.05
	mind.complete_meal(tuning)
	assert_eq(mind.needs.hunger, 0.05, "A meal never makes anyone hungrier")
	mind.complete_exchange(tuning)
	assert_true(is_equal_approx(mind.needs.social, 1.0 - tuning.exchange_social_relief))
	mind.needs.social = 0.05
	mind.complete_exchange(tuning)
	assert_eq(mind.needs.social, 0.0)

func test_need_bands_follow_tuning_thresholds() -> void:
	var mind := _mind()
	assert_eq(mind.condition_band(0.0).hunger, "low")
	mind.needs.hunger = 0.4
	mind.needs.fatigue = 0.75
	var band: Dictionary = mind.condition_band(0.0)
	assert_eq(band.hunger, "moderate")
	assert_eq(band.fatigue, "pressing")
	assert_eq(band.social, "low")
	assert_eq(band.emotion, "")
	assert_eq(band.emotion_band, "none")

# Emotions

func test_one_cause_is_felt_once_and_reappraisal_only_refines_it() -> void:
	var mind := _mind()
	assert_true(mind.feel("fear", 0.8, "voss", "ev:1", "incident:1", 0.0))
	assert_false(mind.feel("fear", 0.6, "voss", "ev:2", "incident:1", 5.0),
		"Another view of one incident adds no second impulse")
	assert_eq(mind.emotion_causes(0.0).size(), 1)
	assert_true(mind.feel("fear", 0.9, "voss", "ev:2", "incident:1", 15.0))
	assert_true(is_equal_approx(mind.emotion("fear", 15.0), 0.45),
		"Refining keeps the original onset: one fear half-life later")
	assert_true(mind.feel("anger", 0.4, "voss", "ev:2", "incident:1", 15.0),
		"A different emotion of one cause is its own record")
	assert_true(mind.feel("fear", 0.3, "", "ev:3", "", 15.0), "Without an incident the evidence is the cause")
	assert_eq(mind.emotion_causes(15.0).size(), 3)

func test_feel_rejects_bad_inputs() -> void:
	var mind := _mind()
	assert_false(mind.feel("joy", 0.5, "", "ev:1", "", 0.0))
	assert_false(mind.feel("fear", 0.0, "", "ev:1", "", 0.0))
	assert_false(mind.feel("fear", NAN, "", "ev:1", "", 0.0))
	assert_false(mind.feel("fear", 0.5, "", "", "", 0.0))
	assert_false(mind.feel("fear", 0.5, "", "ev:1", "", NAN))
	assert_false(mind.feel("fear", 0.5, "", "ev:1", "", -1.0))
	assert_false(mind.feel("fear", 0.5, "x".repeat(NpcMindState.MAX_REF_LENGTH + 1), "ev:1", "", 0.0))
	assert_eq(mind.emotion_causes(0.0), [] as Array[Dictionary])
	assert_true(mind.feel("fear", 5.0, "", "ev:1", "", 0.0))
	assert_eq(mind.emotion("fear", 0.0), 1.0, "Intensity is capped at 1")

func test_emotions_decay_by_their_own_half_life_and_drop_out_when_faint() -> void:
	var mind := _mind()
	mind.feel("fear", 0.8, "voss", "ev:1", "", 0.0)
	mind.feel("grief", 0.8, "tess", "ev:2", "", 0.0)
	assert_true(is_equal_approx(mind.emotion("fear", 15.0), 0.4))
	assert_true(mind.emotion("grief", 15.0) > 0.79, "Grief lingers")
	var causes: Array[Dictionary] = mind.emotion_causes(60.0)
	assert_eq(causes.size(), 1, "Fear below the mild band is no longer felt")
	assert_eq(causes[0].emotion, "grief")
	assert_eq(causes[0].subject, "tess")
	assert_eq(causes[0].evidence_id, "ev:2")
	assert_eq(mind.emotion("anger", 60.0), 0.0)

func test_causes_are_strongest_first_and_bands_name_the_strongest() -> void:
	var mind := _mind()
	mind.feel("anger", 0.3, "voss", "ev:1", "", 0.0)
	mind.feel("fear", 0.7, "voss", "ev:2", "", 0.0)
	var causes: Array[Dictionary] = mind.emotion_causes(0.0)
	assert_eq(causes[0].emotion, "fear")
	assert_eq(causes[1].emotion, "anger")
	var band: Dictionary = mind.condition_band(0.0)
	assert_eq(band.emotion, "fear")
	assert_eq(band.emotion_band, "strong")
	assert_eq(band.emotions, {"fear": "strong", "anger": "mild", "grief": "none", "relief": "none"})

func test_the_weakest_cause_makes_room_at_the_cap() -> void:
	var mind := _mind()
	for index: int in range(NpcMindState.MAX_EMOTIONS):
		assert_true(mind.feel("grief", 0.5 + index * 0.01, "", "ev:%d" % index, "", 0.0))
	assert_true(mind.feel("grief", 0.2, "", "ev:new", "", 0.0))
	var causes: Array[Dictionary] = mind.emotion_causes(0.0)
	assert_eq(causes.size(), NpcMindState.MAX_EMOTIONS)
	assert_false(causes.any(func(cause: Dictionary) -> bool: return cause.evidence_id == "ev:0"))
	assert_true(causes.any(func(cause: Dictionary) -> bool: return cause.evidence_id == "ev:new"))

func test_condition_version_changes_with_bands_not_with_ticks() -> void:
	var mind := _mind()
	var tuning := NpcBehaviorTuning.new()
	var version: String = mind.condition_version(0.0)
	mind.advance_needs(1.0, false, 0.5, tuning)
	assert_eq(mind.condition_version(1.0), version, "A need tick inside its band is invisible")
	mind.feel("fear", 0.8, "voss", "ev:1", "", 1.0)
	var afraid: String = mind.condition_version(1.0)
	assert_ne(afraid, version)
	assert_eq(mind.condition_version(2.0), afraid, "Decay inside the band is invisible")
	assert_ne(mind.condition_version(20.0), afraid, "Fear easing to mild is a new read")
	var easing: String = mind.condition_version(20.0)
	mind.needs.hunger = 0.9
	var hungry: String = mind.condition_version(20.0)
	assert_ne(hungry, easing, "Pressing hunger is a new read")
	mind.add_bereavement("tess", "ev:2", 20.0)
	assert_ne(mind.condition_version(20.0), hungry, "A new concern is a new read")

func test_pain_is_read_from_real_health() -> void:
	var tuning := NpcBehaviorTuning.new()
	var body := Body.new()
	assert_eq(NpcMindState.pain_of(body), 0.0)
	body.health = 25.0
	assert_eq(NpcMindState.pain_of(body), 0.75)
	assert_eq(NpcMindState.pain_band(NpcMindState.pain_of(body), tuning), "pressing")
	body.health = 70.0
	assert_eq(NpcMindState.pain_band(NpcMindState.pain_of(body), tuning), "moderate")
	body.health = -10.0
	assert_eq(NpcMindState.pain_of(body), 1.0)
	body.max_health = 0.0
	assert_eq(NpcMindState.pain_of(body), 0.0)
	assert_eq(NpcMindState.pain_of(null), 0.0)
	assert_eq(NpcMindState.pain_of(RefCounted.new()), 0.0)

# Saves

func test_a_save_without_needs_or_emotions_loads_neutral() -> void:
	var mind := _mind()
	mind.feel("fear", 0.8, "voss", "ev:1", "", 0.0)
	mind.needs.hunger = 0.9
	var legacy: Dictionary = NpcMindState.new(NPC).to_data()
	legacy.erase("needs")
	legacy.erase("emotions")
	assert_true(mind.from_data(JSON.parse_string(JSON.stringify(legacy))))
	assert_eq(mind.needs, NpcMindState.neutral_needs(mind.tuning))
	assert_eq(mind.emotion_causes(0.0), [] as Array[Dictionary])

# Appraisal -> feeling

func test_an_appraisal_is_felt_about_the_right_people_once_per_incident() -> void:
	var mind := _mind()
	var observation := _observation([{"id": "voss", "role": "aggressor"},
		{"id": "tess", "role": "hurt_person"}], "incident:9")
	var appraisal := _appraisal({"fear": 0.7, "anger": 0.0, "grief": 0.6, "relief": 0.0})
	NpcEventProcessor.feel_appraisal(mind, observation, appraisal)
	var causes: Array[Dictionary] = mind.emotion_causes(30.0)
	assert_eq(causes.size(), 2)
	assert_eq(causes[0].emotion, "fear")
	assert_eq(causes[0].subject, "voss")
	assert_eq(causes[0].incident_id, "incident:9")
	assert_eq(causes[0].onset_minute, 30.0)
	assert_eq(causes[1].emotion, "grief")
	assert_eq(causes[1].subject, "tess")
	var heard := NpcObservation.from_perception(NPC, "event:2", 40.0, &"outdoors",
		{"text": "Voss struck Tess.", "sense": "sight", "participants": [{"id": "voss", "role": "aggressor"}]})
	heard.incident_id = "incident:9"
	NpcEventProcessor.feel_appraisal(mind, heard, appraisal)
	assert_eq(mind.emotion_causes(40.0).size(), 2, "A second view of one incident is no new impulse")

func test_the_observer_is_never_the_subject_of_its_own_feeling() -> void:
	var mind := _mind()
	var observation := _observation([{"id": NPC, "role": "aggressor"}])
	NpcEventProcessor.feel_appraisal(mind, observation, _appraisal({"anger": 0.6}))
	var causes: Array[Dictionary] = mind.emotion_causes(30.0)
	assert_eq(causes.size(), 1)
	assert_eq(causes[0].subject, "")
	assert_eq(causes[0].evidence_id, observation.observation_id, "No incident: the evidence is the cause")

func test_a_committed_appraisal_is_felt_through_the_processor() -> void:
	var rig := Rig.new()
	rig.backend.set_default("appraise", {"fear": 4.0})
	var profile := NpcProfile.new()
	profile.npc_id = StringName(NPC)
	var observation := _observation([{"id": "voss", "role": "aggressor"}])
	rig.processor.observe(profile, {}, observation)
	await rig.processor.flush(NPC)
	var mind: NpcMindState = rig.processor.store.minds.get_mind(NPC)
	assert_true(mind.emotion("fear", 30.0) > 0.5, "Committed fear is felt")
	assert_eq(mind.emotion_causes(30.0)[0].subject, "voss")
	await rig.dispose()

# Context

func test_context_carries_condition_bands_and_causes_only_with_a_minute() -> void:
	var mind := _mind()
	mind.feel("fear", 0.8, "voss", "ev:1", "incident:1", 0.0)
	var bare: Dictionary = NpcCognitiveContext.mind_context(mind)
	assert_false(bare.has("condition"))
	assert_false(bare.has("emotion_causes"))
	var body := Body.new()
	body.health = 50.0
	var context: Dictionary = NpcCognitiveContext.mind_context(mind, 0.0, body)
	assert_eq(context.condition.hunger, "low")
	assert_eq(context.condition.pain, "moderate")
	assert_eq(context.condition.emotion, "fear")
	assert_eq(context.emotion_causes, [{"emotion": "fear", "band": "strong", "subject": "voss",
		"evidence_id": "ev:1", "incident_id": "incident:1"}])
	assert_false(NpcCognitiveContext.mind_context(mind, 0.0).condition.has("pain"))
	assert_false(JSON.stringify(context).contains("0.8"), "Context carries bands, not raw numbers")

func test_strong_feelings_become_named_concerns_and_grief_for_a_known_loss_is_not_doubled() -> void:
	var mind := _mind()
	mind.feel("fear", 0.9, "voss", "ev:1", "", 0.0)
	mind.feel("grief", 0.8, "tess", "ev:2", "", 0.0)
	mind.feel("anger", 0.3, "voss", "ev:3", "", 0.0)
	var current: Dictionary = {"world_minute": 0.0,
		"known_townspeople": [{"id": "voss", "name": "Voss"}]}
	current.merge(NpcCognitiveContext.mind_context(mind, 0.0))
	var state: Dictionary = {"recent_events": [], "observations": []}
	var context: Dictionary = NpcCognitiveContext.build(state, current)
	assert_eq(context.current_concerns, [
		{"kind": "feeling", "emotion": "fear", "band": "strong", "subject": "Voss"},
		{"kind": "feeling", "emotion": "grief", "band": "strong", "subject": "tess"}])
	assert_false(context.has("emotion_causes"))
	assert_eq(context.condition.emotion, "fear")
	mind.add_bereavement("tess", "ev:2", 0.0)
	current.merge(NpcCognitiveContext.mind_context(mind, 0.0), true)
	context = NpcCognitiveContext.build(state, current)
	var kinds: Array = context.current_concerns.map(func(concern: Dictionary) -> String:
		return concern.kind)
	assert_eq(kinds, ["feeling", "bereavement"])

func test_an_observation_about_someone_felt_for_is_personal() -> void:
	var mind := _mind()
	mind.feel("fear", 0.9, "voss", "ev:1", "", 0.0)
	var current: Dictionary = {"world_minute": 10.0}
	current.merge(NpcCognitiveContext.mind_context(mind, 10.0))
	var record: Dictionary = {"text": "Voss walked by.", "sense": "sight", "player_involved": false,
		"status": "assessed", "created_at": Time.get_unix_time_from_system(), "world_minute": 9.0,
		"participants": [{"id": "voss"}]}
	var context: Dictionary = NpcCognitiveContext.build(
		{"recent_events": [], "observations": [record]}, current)
	assert_eq(context.current_concerns[0].kind, "observation")
