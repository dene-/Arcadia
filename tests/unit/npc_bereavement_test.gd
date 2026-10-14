extends "res://tests/test_case.gd"

const CognitionScript = preload("res://game/actors/npcs/npc_cognition.gd")

const DECEASED: String = "garrin_holt"

var _serial: int = 0

## A mind whose public knowledge lists `kin` (id -> family role), as TownLife bootstraps it.
func _mind(id: String, kin: Dictionary = {}) -> NpcMindState:
	var mind := NpcMindState.new(id)
	var people: Dictionary = {
		id: {"name": id.capitalize(), "job": "farmer", "household": "holt", "kin": kin},
		DECEASED: {"name": "Garrin Holt", "job": "farmer", "household": "holt", "kin": {}},
		"voss": {"name": "Voss", "job": "guard", "household": "voss", "kin": {}}}
	mind.knowledge.bootstrap_public(id, people, {}, [] as Array[String])
	return mind

func _observation(observer: String, kind: String, sense: String, participants: Array,
		minute: float = 500.0) -> NpcObservation:
	_serial += 1
	return NpcObservation.from_perception(observer, "event:%d" % _serial, minute, &"outdoors",
		{"kind": kind, "sense": sense, "text": "Something about Garrin.", "player_involved": false,
		"participants": participants})

func _found(observer: String, minute: float = 500.0) -> NpcObservation:
	return _observation(observer, "body_found", "sight",
		[{"id": DECEASED, "name": "Garrin Holt", "role": "deceased"}], minute)

func _reported(observer: String, minute: float = 510.0) -> NpcObservation:
	return _observation(observer, "body_reported", "hearing",
		[{"id": DECEASED, "name": "Garrin Holt", "role": "deceased"},
		{"id": "voss", "name": "Voss", "role": "reporter"}], minute)

func _concerns(mind: NpcMindState) -> Array:
	return mind.condition.get("concerns", [])

func test_an_informed_relative_gets_one_bereavement_concern() -> void:
	var mind: NpcMindState = _mind("holt_partner", {DECEASED: "spouse"})
	var found: NpcObservation = _found("holt_partner")
	CognitionScript.perceive(mind, found, {DECEASED: Vector2(10, 20)})
	var concerns: Array = _concerns(mind)
	assert_eq(concerns.size(), 1)
	assert_eq(concerns[0].kind, "bereavement")
	assert_eq(concerns[0].subject, DECEASED)
	assert_eq(concerns[0].evidence_id, found.observation_id)
	assert_eq(float(concerns[0].minute), 500.0)

func test_a_reported_death_also_bereaves_a_relative() -> void:
	var mind: NpcMindState = _mind("holt_child_a", {DECEASED: "father"})
	CognitionScript.perceive(mind, _reported("holt_child_a"), {})
	assert_eq(_concerns(mind).size(), 1)

func test_a_non_relative_learns_the_death_without_grief() -> void:
	var mind: NpcMindState = _mind("neighbor")
	CognitionScript.perceive(mind, _found("neighbor"), {DECEASED: Vector2(10, 20)})
	assert_true(mind.knowledge.knows(DECEASED, "status"))
	assert_true(_concerns(mind).is_empty())

func test_learning_the_death_again_adds_no_second_concern() -> void:
	var mind: NpcMindState = _mind("holt_partner", {DECEASED: "spouse"})
	CognitionScript.perceive(mind, _reported("holt_partner", 490.0), {})
	var first: Array = _concerns(mind).duplicate(true)
	var version: int = int(mind.versions().condition)
	CognitionScript.perceive(mind, _found("holt_partner", 520.0), {DECEASED: Vector2(10, 20)})
	CognitionScript.perceive(mind, _reported("holt_partner", 530.0), {})
	assert_eq(_concerns(mind), first)
	assert_eq(int(mind.versions().condition), version)

func test_an_uninformed_relative_has_no_concern() -> void:
	var mind: NpcMindState = _mind("holt_child_b", {DECEASED: "father"})
	var noise: NpcObservation = _observation("holt_child_b", "combat_noise", "hearing",
		[{"id": DECEASED, "name": "Garrin Holt", "role": "hurt_person"}])
	CognitionScript.perceive(mind, noise, {})
	var heard_death: NpcObservation = _observation("holt_child_b", "actor_died", "hearing",
		[{"id": DECEASED, "name": "Garrin Holt", "role": "hurt_person"}])
	CognitionScript.perceive(mind, heard_death, {})
	assert_false(mind.knowledge.knows(DECEASED, "status"))
	assert_true(_concerns(mind).is_empty())

func test_bereavement_survives_a_save_round_trip() -> void:
	var mind: NpcMindState = _mind("holt_partner", {DECEASED: "spouse"})
	CognitionScript.perceive(mind, _found("holt_partner"), {DECEASED: Vector2(10, 20)})
	var restored := NpcMindState.new("holt_partner")
	assert_true(restored.from_data(JSON.parse_string(JSON.stringify(mind.to_data()))))
	assert_eq(_concerns(restored).size(), 1)
	assert_eq(_concerns(restored)[0].subject, DECEASED)

func test_a_grave_teaches_the_burial_and_never_the_killer() -> void:
	var mind: NpcMindState = _mind("neighbor")
	var grave: NpcObservation = CognitionScript.grave_observation("neighbor", DECEASED, "Garrin Holt",
		700.0, Vector2(-280, 248))
	assert_not_null(grave)
	CognitionScript.perceive(mind, grave, {})
	var burial: Array[Dictionary] = mind.knowledge.current(DECEASED, "burial")
	assert_eq(burial.size(), 1)
	assert_eq(burial[0].value, "buried")
	assert_eq(burial[0].status, "OBSERVED")
	assert_true("grave:" + DECEASED in burial[0].origin_ids)
	assert_false(mind.knowledge.knows(DECEASED, "location"), "A grave is not a sighting of the person")
	var personal: Array = mind.knowledge.to_data().facts
	assert_eq(personal.size(), 1, "A grave teaches only the burial: %s" % [personal])
	var again: NpcObservation = CognitionScript.grave_observation("neighbor", DECEASED, "Garrin Holt",
		760.0, Vector2(-280, 248))
	var version: int = mind.knowledge.version
	CognitionScript.perceive(mind, again, {})
	assert_eq(mind.knowledge.version, version, "Seeing the same grave again adds nothing")
