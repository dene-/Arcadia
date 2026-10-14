extends "res://tests/test_case.gd"

const FALLBACK: String = "Garrin is dead. Please, come with me."

## Stands in for DialogBackendClient.request_v2: records each call and answers from `answer`,
## holding the call while `held`.
class FakeTransport extends DialogBackendClient:
	signal released
	var answer: Callable = func(_envelope: Dictionary) -> Dictionary: return {}
	var held: bool = false
	var calls: Array[Dictionary] = []

	func request_v2(path: String, envelope: Dictionary, _deadline_ms: int,
			_handle_id: String = "") -> Dictionary:
		calls.append({"path": path, "envelope": envelope.duplicate(true)})
		while held:
			await released
		return answer.call(envelope)

	func cancel(_handle_id: String) -> void:
		pass

	func release() -> void:
		held = false
		released.emit()

class AudibleSpeech extends NpcReportSpeech:
	var heard: bool = true
	func audible(_speaker: BaseNpc) -> bool:
		return heard

var _scene: Node2D
var _speaker: BaseNpc
var _listener: BaseNpc
var _transport: FakeTransport
var _speech: AudibleSpeech
var _spoken: Array[String] = []
var _results: Array[NpcReportSpeech.Result] = []

func before_each() -> void:
	_spoken.clear()
	_results.clear()
	_scene = Node2D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(_scene)
	_speaker = _resident("witness", "Ana Rowan")
	_listener = _resident("guard", "Vale")
	_transport = FakeTransport.new()
	_scene.add_child(_transport)
	var decisions := NpcDecisionService.new()
	decisions.transport = _transport
	_scene.add_child(decisions)
	_speech = AudibleSpeech.new()
	_speech.decisions = decisions
	_scene.get_node("/root/WorldEvents").occurred.connect(_on_event)

func after_each() -> void:
	_scene.get_node("/root/WorldEvents").occurred.disconnect(_on_event)
	_scene.free()

func _resident(id: String, profile_name: String) -> BaseNpc:
	var npc: BaseNpc = load("res://game/actors/npcs/base_npc.tscn").instantiate()
	npc.npc_data = npc.npc_data.duplicate(true)
	npc.npc_data.profile = npc.npc_data.profile.duplicate(true)
	npc.npc_data.profile.npc_id = StringName(id)
	npc.npc_data.profile.profile_name = profile_name
	npc.position = Vector2(5000, 5000) if id == "witness" else Vector2(5020, 5000)
	_scene.add_child(npc)
	return npc

func _on_event(event: WorldEvent) -> void:
	if event.kind == &"actor_spoke" and event.subject == _speaker:
		_spoken.append(event.facts.text)

static func _line(text: String) -> Callable:
	return func(envelope: Dictionary) -> Dictionary:
		return {"outcome": DialogBackendClient.OUTCOME_SUCCESS, "status": 200,
			"body": {"protocol_version": 2, "request_id": envelope.request_id, "response": text}}

static func _unavailable(_envelope: Dictionary) -> Dictionary:
	return {"outcome": DialogBackendClient.OUTCOME_UNAVAILABLE, "status": 503, "body": {}}

func _report(fallback: String = FALLBACK) -> NpcReportSpeech.Result:
	return await _speech.say(_speaker, "report", "I found Garrin Holt's body.", "sight", fallback,
		_listener)

func _start_report() -> void:
	_results.append(await _report())

func test_generated_line_is_requested_in_the_v2_contract_and_shown() -> void:
	_transport.answer = _line("Garrin has fallen. Come with me, quickly.")
	assert_eq(await _report(), NpcReportSpeech.Result.DISPLAYED)
	assert_eq(_spoken, ["Garrin has fallen. Come with me, quickly."] as Array[String])
	assert_eq(_transport.calls.size(), 1)
	var call: Dictionary = _transport.calls[0]
	assert_eq(call.path, "/v2/dialogue/say")
	var envelope: Dictionary = call.envelope
	assert_eq(envelope.protocol_version, 2)
	assert_eq(envelope.npc_id, "witness")
	assert_eq(envelope.intent, "report")
	assert_eq(envelope.npc.id, "witness")
	assert_eq(envelope.listener, {"id": "guard", "name": "Vale"})
	assert_eq(envelope.event, {"text": "I found Garrin Holt's body.", "sense": "sight", "player_involved": false})
	assert_true(envelope.context is Dictionary)

func test_failed_generation_shows_the_offline_fallback_instead() -> void:
	_transport.answer = _unavailable
	assert_eq(await _report(), NpcReportSpeech.Result.FALLBACK)
	assert_eq(_spoken, [FALLBACK] as Array[String])

func test_unusable_generated_text_is_never_spoken() -> void:
	_transport.answer = func(_envelope: Dictionary) -> Dictionary:
		return {"outcome": DialogBackendClient.OUTCOME_SUCCESS, "status": 200,
			"body": {"protocol_version": 2, "request_id": "req:other", "response": "Wrong ticket."}}
	assert_eq(await _report(), NpcReportSpeech.Result.FALLBACK)
	_transport.answer = _line("x".repeat(NpcReportSpeech.MAX_LENGTH + 1))
	assert_eq(await _report(), NpcReportSpeech.Result.FALLBACK)
	assert_eq(_spoken, [FALLBACK, FALLBACK] as Array[String])

func test_offscreen_report_requests_and_shows_nothing() -> void:
	_speech.heard = false
	_transport.answer = _line("Nobody hears this.")
	assert_eq(await _report(), NpcReportSpeech.Result.OFFSCREEN)
	assert_true(_transport.calls.is_empty())
	assert_true(_spoken.is_empty())

func test_without_a_player_in_range_nothing_is_requested() -> void:
	var speech := NpcReportSpeech.new()
	speech.decisions = _speech.decisions
	assert_false(speech.audible(_speaker))
	assert_eq(await speech.say(_speaker, "report", "I found a body.", "sight", FALLBACK),
		NpcReportSpeech.Result.OFFSCREEN)
	assert_true(_transport.calls.is_empty())

func test_failed_generation_of_an_optional_line_speaks_nothing() -> void:
	_transport.answer = _unavailable
	assert_eq(await _report(""), NpcReportSpeech.Result.UNSPOKEN)
	assert_true(_spoken.is_empty())

func test_a_speaker_who_died_during_generation_never_speaks() -> void:
	_transport.held = true
	_transport.answer = _line("Too late.")
	_start_report()
	assert_eq(_transport.calls.size(), 1)
	_speaker.health = 0
	_transport.release()
	assert_eq(_results, [NpcReportSpeech.Result.UNSPOKEN] as Array[NpcReportSpeech.Result])
	assert_true(_spoken.is_empty())

func test_a_player_who_left_during_generation_hears_nothing() -> void:
	_transport.held = true
	_transport.answer = _line("Come with me.")
	_start_report()
	_speech.heard = false
	_transport.release()
	assert_eq(_results, [NpcReportSpeech.Result.OFFSCREEN] as Array[NpcReportSpeech.Result])
	assert_true(_spoken.is_empty())

func test_a_blocked_bubble_is_not_recorded_as_speech() -> void:
	_transport.answer = _unavailable
	assert_true(_speaker.begin_speech("session", true))
	assert_eq(await _report(), NpcReportSpeech.Result.UNSPOKEN)
	assert_true(_spoken.is_empty())
