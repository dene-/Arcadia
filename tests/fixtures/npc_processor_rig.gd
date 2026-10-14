extends RefCounted

## An NpcEventProcessor wired to the scripted v2 fake: processor -> NpcDecisionService -> fake
## transport. The processor's retry-ladder clock is `now_msec`, so tests step it explicitly.
## Call `dispose()` (awaited) when done.

const FakeService = preload("res://tests/fixtures/npc_fake_decision_service.gd")

var backend: FakeService
var decisions: NpcDecisionService
var processor: NpcEventProcessor
var now_msec: int = 1000

func _init(store: NpcMemoryStore = NpcMemoryStore.new()) -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	backend = FakeService.new()
	root.add_child(backend)
	decisions = NpcDecisionService.new()
	decisions.transport = backend
	root.add_child(decisions)
	processor = NpcEventProcessor.new()
	processor.persist = false
	processor.store = store
	processor.decisions = decisions
	processor.clock = func() -> int: return now_msec
	root.add_child(processor)

func dispose() -> void:
	backend.release_all()
	processor.queue_free()
	decisions.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame
	backend.free()

## appraise overrides: `subject` becomes less trusted by `magnitude` (0..4) quarters of 0.1.
static func distrust(subject: String, magnitude: float = 4.0) -> Dictionary:
	return {"disposition:%s:trust:direction" % subject: "NEGATIVE",
		"disposition:%s:trust:magnitude" % subject: magnitude}

