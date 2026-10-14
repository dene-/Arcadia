extends "res://tests/test_case.gd"

const ID: String = "context_builder_npc"
const CONSUMERS: Array[StringName] = [NpcCognitiveContext.DIALOGUE, NpcCognitiveContext.REACTION,
	NpcCognitiveContext.SOCIAL, NpcCognitiveContext.DECISION]
## Private runtime diagnostics no consumer may ever see.
const PRIVATE_KEYS: Array[String] = ["decision", "routine_decision", "diagnostic", "diagnostics",
	"daily_plan", "plan", "ties", "relationship"]

var _scene: Node2D
var _npc: BaseNpc
var _minds: NpcMindStore
var _saved_minds: Dictionary

func before_each() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	_minds = tree.root.get_node("NpcCognition").save_game.minds
	_saved_minds = _minds.to_data()
	_scene = Node2D.new()
	tree.root.add_child(_scene)
	_npc = load("res://game/actors/npcs/base_npc.tscn").instantiate()
	_npc.npc_data = _npc.npc_data.duplicate(true)
	_npc.npc_data.profile = _npc.npc_data.profile.duplicate(true)
	_npc.npc_data.profile.npc_id = StringName(ID)
	_npc.position = Vector2(6000, 6000)
	_scene.add_child(_npc)

func after_each() -> void:
	_scene.free()
	_minds.from_data(_saved_minds)

# Everything a resident's runtime could hold, including diagnostics that must never leak.
func _full_facts() -> Dictionary:
	return {"world_time": "09:00", "world_minute": 540.0, "world_space": "outdoors",
		"location": "Square", "activity": "work", "interrupted_activity": "", "destination": "Forge",
		"traveling": false,
		"sleeping": false, "recently_awakened": false, "wake_reason": "", "alert_phase": "",
		"physical_state": "well", "sensory_cues": [], "personality": {"warmth": 0.5},
		"current_task": {"task_id": "task:1", "kind": "routine", "phase": "working",
			"activity": "work", "label": "Forge", "params": {"secret": true}, "status": "RUNNING"},
		"safety_response": {}, "condition": {"hunger": "low"}, "emotion_causes": [],
		"personal_concerns": [], "open_commitments": [], "family_members": [],
		"known_townspeople": [{"id": "other", "name": "Other", "relationship": {"trust": 0.9}}],
		"relationships": {"player": {"trust": 0.1}}, "player_identity": {"id": "player"},
		"household": {"id": "h1"}, "household_economy": {"coins": 3}, "town_rumors": [],
		"known_deaths": [], "enforcement": {}, "recent_social": [], "recent_ambient": [],
		"decision": {"reason": "plan_kept"}, "routine_decision": {"selected": "work"},
		"diagnostic": {"latency_ms": 4}, "diagnostics": [{"code": "x"}],
		"daily_plan": [{"kind": "work"}], "plan": [{"kind": "work"}], "ties": {"other": {}},
		"relationship": {"trust": 0.2}, "unknown_world_fact": "the killer is Bram"}

func test_each_consumer_gets_only_its_whitelist() -> void:
	var facts: Dictionary = _full_facts()
	for consumer: StringName in CONSUMERS:
		var allowed: Array = NpcCognitiveContext.SHARED_KEYS + NpcCognitiveContext.CONSUMER_KEYS[consumer]
		var context: Dictionary = NpcCognitiveContext.for_consumer(consumer, facts)
		for key: String in allowed:
			assert_true(context.has(key), "%s should see %s" % [consumer, key])
		for key: Variant in context:
			assert_true(key in allowed, "%s must not see %s" % [consumer, key])
		for key: String in PRIVATE_KEYS + ["unknown_world_fact"]:
			assert_false(context.has(key), "%s leaked %s" % [consumer, key])
		assert_eq(context.current_task, {"kind": "routine", "phase": "working", "activity": "work",
			"label": "Forge"})
		assert_false(context.known_townspeople[0].has("relationship"))
	assert_false(NpcCognitiveContext.for_consumer(NpcCognitiveContext.DECISION, facts).has("player_identity"))
	assert_false(NpcCognitiveContext.for_consumer(NpcCognitiveContext.REACTION, facts).has("town_rumors"))
	assert_false(NpcCognitiveContext.for_consumer(NpcCognitiveContext.SOCIAL, facts).has("player_identity"))
	assert_eq(NpcCognitiveContext.for_consumer(&"model_debug", facts), {})

func test_projection_copies_and_never_mutates_the_facts() -> void:
	var facts: Dictionary = _full_facts()
	var before: Dictionary = facts.duplicate(true)
	var context: Dictionary = NpcCognitiveContext.for_consumer(NpcCognitiveContext.DIALOGUE, facts)
	context.relationships.player.trust = -1.0
	context.known_townspeople.clear()
	assert_eq(facts, before)

func test_live_resident_contexts_strip_saved_diagnostics() -> void:
	_npc.life_context = {"world_time": "09:00", "world_minute": 540.0,
		"decision": {"reason": "plan_kept"}, "routine_decision": {"selected": "work"},
		"diagnostics": [{"code": "x"}], "daily_plan": [{"kind": "work"}]}
	for consumer: StringName in CONSUMERS:
		var context: Dictionary = _npc.get_cognitive_context(consumer)
		var allowed: Array = NpcCognitiveContext.SHARED_KEYS + NpcCognitiveContext.CONSUMER_KEYS[consumer]
		for key: Variant in context:
			assert_true(key in allowed, "%s must not see %s" % [consumer, key])
		assert_eq(context.world_minute, 540.0)
		assert_eq(context.world_time, "09:00")

func test_a_2100_context_does_not_report_a_morning_wake() -> void:
	_npc.life_context = {"world_time": "07:00", "world_minute": 420.0}
	_npc.state_machine.transition_to(&"sleep", {}, true)
	_npc.wake_from_noise("noise")
	assert_false(_npc.is_sleeping())
	_npc.life_context.world_minute = 422.0
	var morning: Dictionary = _npc.get_cognitive_context()
	assert_true(morning.recently_awakened)
	assert_eq(morning.wake_reason, "noise")
	_npc.life_context = {"world_time": "21:00", "world_minute": 1260.0}
	for consumer: StringName in CONSUMERS:
		var evening: Dictionary = _npc.get_cognitive_context(consumer)
		assert_eq(evening.world_time, "21:00")
		assert_eq(evening.world_minute, 1260.0)
		assert_false(evening.recently_awakened, "%s reused the morning wake" % consumer)
		assert_eq(evening.wake_reason, "")

func test_relationship_equals_the_graph_value() -> void:
	var mind: NpcMindState = _minds.get_mind(ID)
	assert_true(mind.relationships.seed_relationship("player", {"trust": 0.25, "fear": 0.4}))
	assert_true(mind.relationships.seed_relationship("other_resident", {"affection": 0.6}))
	_npc.life_context = {"world_time": "09:00", "world_minute": 540.0}
	for consumer: StringName in CONSUMERS:
		var context: Dictionary = _npc.get_cognitive_context(consumer, ["player", "other_resident"])
		assert_eq(context.relationships, {"player": mind.relationships.get_relationship("player"),
			"other_resident": mind.relationships.get_relationship("other_resident")})
	assert_eq(_npc.get_cognitive_context().relationships, {},
		"Only the consumer's participants are included")
	assert_true(mind.relationships.apply_delta("player", {"trust": -0.1}, "receipt:1"))
	assert_eq(_npc.get_cognitive_context(NpcCognitiveContext.DECISION, ["player"]).relationships.player,
		mind.relationships.get_relationship("player"))
