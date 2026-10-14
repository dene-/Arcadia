extends "res://tests/test_case.gd"

const Routine = preload("res://tests/unit/npc_routine_task_test.gd")
const Brain = preload("res://tests/unit/npc_brain_test.gd")
const Memory = preload("res://tests/unit/npc_memory_test.gd")
const NPC: String = "holt_partner"

class CountingStore extends NpcMemoryStore:
	var completions: Array[String] = []

	func complete_intention(npc_id: String, memory_id: String) -> bool:
		completions.append("%s/%s" % [npc_id, memory_id])
		return super.complete_intention(npc_id, memory_id)

func _store() -> CountingStore:
	var store := CountingStore.new()
	var memory_test: Object = Memory.new()
	store.ensure_npc(memory_test._profile(StringName(NPC)))
	assert_true(store.commit_exchange(NPC, "Tell the guard.", memory_test._result("prospective"),
		memory_test._policy(), [], [], Memory.SESSION))
	return store

func _rig(store: CountingStore) -> Routine.Rig:
	var rig := Routine.Rig.new()
	rig.brain.memory = store
	return rig

func _promise(rig: Routine.Rig, deadline: float = -1.0) -> String:
	var evidence: Array[String] = ["memory:mem:1"]
	var id: String = rig.mind.commitments.create("report_discovery", [] as Array[String], evidence,
		100.0, deadline)
	assert_ne(id, "")
	return id

func _errand(commitment_id: String) -> NpcDirectedTravelTask:
	var task := NpcDirectedTravelTask.create(Brain.directed_params("barracks", 0.6))
	task.commitment_ids = [commitment_id] as Array[String]
	return task

func _status(rig: Routine.Rig, commitment_id: String) -> String:
	return rig.mind.commitments.get_commitment(commitment_id)["status"] as String

func _intention_done(store: NpcMemoryStore) -> bool:
	return store.snapshot(NPC).memories[0].completed

func test_completed_task_resolves_its_commitment_and_intention_exactly_once() -> void:
	var store := _store()
	var rig := _rig(store)
	var promise := _promise(rig)
	assert_true(rig.start(_errand(promise), 100.0))
	rig.executor.arrive()
	rig.tick(110.0)
	assert_eq(rig.last_finished()["status"], "COMPLETED")
	assert_eq(_status(rig, promise), "completed")
	assert_eq(rig.mind.commitments.get_commitment(promise)["resolved_minute"], 110.0)
	assert_true(_intention_done(store))
	assert_eq(store.completions, ["%s/mem:1" % NPC] as Array[String])
	assert_true(rig.start(_errand(promise), 120.0), "a second task citing it may still run")
	rig.executor.arrive()
	rig.tick(130.0)
	assert_eq(rig.mind.commitments.get_commitment(promise)["resolved_minute"], 110.0)
	assert_eq(store.completions.size(), 1)
	rig.dispose()

func test_failure_resolves_without_completing_the_intention() -> void:
	var store := _store()
	var rig := _rig(store)
	var promise := _promise(rig)
	assert_true(rig.start(_errand(promise), 100.0))
	rig.executor.fail()
	rig.tick(105.0)
	assert_eq(rig.last_finished()["status"], "FAILED")
	assert_eq(_status(rig, promise), "failed")
	assert_false(_intention_done(store))
	assert_true(store.completions.is_empty())
	rig.dispose()

func test_cancellation_leaves_the_commitment_open_for_its_owner() -> void:
	var store := _store()
	var rig := _rig(store)
	var promise := _promise(rig)
	assert_true(rig.start(_errand(promise), 100.0))
	assert_true(rig.brain.end_task(rig.brain.current_activity()["task_id"] as String))
	assert_eq(_status(rig, promise), "open")
	assert_true(rig.start(_errand(promise), 110.0))
	rig.brain.interrupt(NpcTask.Interrupt.DANGER)
	assert_eq(rig.last_finished()["reason"], &"danger")
	assert_eq(_status(rig, promise), "open")
	assert_false(_intention_done(store))
	assert_true(rig.start(_errand(promise), 120.0), "the owner re-requests it")
	rig.executor.arrive()
	rig.tick(125.0)
	assert_eq(_status(rig, promise), "completed")
	assert_true(_intention_done(store))
	rig.dispose()

func test_cancellation_after_the_deadline_fails_the_commitment() -> void:
	var store := _store()
	var rig := _rig(store)
	var early := _promise(rig, 300.0)
	assert_true(rig.start(_errand(early), 100.0))
	rig.tick(200.0)
	assert_true(rig.brain.end_task(rig.brain.current_activity()["task_id"] as String))
	assert_eq(_status(rig, early), "open", "cancelled before its deadline")
	assert_true(rig.start(_errand(early), 250.0))
	rig.tick(301.0)
	assert_true(rig.brain.end_task(rig.brain.current_activity()["task_id"] as String))
	assert_eq(_status(rig, early), "failed")
	assert_eq(rig.mind.commitments.get_commitment(early)["resolved_minute"], 301.0)
	assert_false(_intention_done(store))
	rig.dispose()

func _reloaded(source: Routine.Rig, store: CountingStore) -> Routine.Rig:
	assert_true(source.brain.save_checkpoint())
	var loaded := _rig(store)
	assert_true(loaded.mind.from_data(JSON.parse_string(JSON.stringify(source.mind.to_data()))))
	return loaded

func test_restored_task_resolves_its_commitment_once() -> void:
	var store := _store()
	var rig := _rig(store)
	var promise := _promise(rig)
	var errand := _errand(promise)
	assert_true(rig.start(errand, 100.0))
	var loaded := _reloaded(rig, store)
	rig.dispose()
	assert_eq(_status(loaded, promise), "open", "commitments live in the mind")
	assert_true(loaded.brain.restore_checkpoint(140.0))
	assert_eq(loaded.brain.task_state(errand.task_id), "RUNNING")
	loaded.executor.arrive()
	loaded.tick(150.0)
	assert_eq(_status(loaded, promise), "completed")
	assert_eq(store.completions.size(), 1)
	var again := _reloaded(loaded, store)
	assert_true(again.brain.restore_checkpoint(160.0))
	again.tick(170.0)
	assert_eq(_status(again, promise), "completed")
	assert_eq(store.completions.size(), 1)
	loaded.dispose()
	again.dispose()

func test_unrestorable_task_cancels_its_commitment() -> void:
	var store := _store()
	var rig := _rig(store)
	var promise := _promise(rig)
	var routine := NpcRoutineTask.create(Routine.routine_params("work", "bakery", 200.0), rig.tuning)
	routine.commitment_ids = [promise] as Array[String]
	assert_true(rig.start(routine, 100.0))
	var late := _reloaded(rig, store)
	assert_false(late.brain.restore_checkpoint(500.0))
	assert_eq(late.last_finished()["reason"], &"restore_invalid")
	assert_eq(_status(late, promise), "cancelled")
	late.dispose()
	rig.dispose()
	assert_false(_intention_done(store))

func test_commitment_whose_task_was_not_saved_stays_open_after_reload() -> void:
	var store := _store()
	var rig := _rig(store)
	var promise := _promise(rig)
	assert_true(rig.brain.save_checkpoint(), "saved while idle")
	assert_true(rig.start(_errand(promise), 100.0))
	var data: Variant = JSON.parse_string(JSON.stringify(rig.mind.to_data()))
	rig.dispose()
	var loaded := _rig(store)
	assert_true(loaded.mind.from_data(data))
	assert_true(loaded.brain.restore_checkpoint(110.0))
	assert_true(loaded.brain.current_activity().is_empty())
	assert_true(loaded.finished.is_empty())
	assert_eq(_status(loaded, promise), "open")
	assert_true(loaded.start(_errand(promise), 120.0), "its owner re-requests the task")
	loaded.executor.arrive()
	loaded.tick(130.0)
	assert_eq(_status(loaded, promise), "completed")
	assert_true(_intention_done(store))
	loaded.dispose()
