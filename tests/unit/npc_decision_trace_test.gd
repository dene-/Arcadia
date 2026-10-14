extends "res://tests/test_case.gd"

func test_trace_keeps_the_newest_capacity_entries_oldest_first() -> void:
	var trace := NpcDecisionTrace.new()
	for index: int in NpcDecisionTrace.CAPACITY + 6:
		assert_true(trace.record(float(index), NpcDecisionTrace.TRANSITION, {"task_id": "task:%d" % index,
			"task_kind": "routine", "from": "CREATED", "to": "RUNNING", "reason": "started"}))
	var entries: Array[Dictionary] = trace.entries()
	assert_eq(NpcDecisionTrace.CAPACITY, 64)
	assert_eq(entries.size(), 64)
	assert_eq(entries[0].task_id, "task:6")
	assert_eq(entries[-1].task_id, "task:69")
	assert_eq(trace.version, 70)

func test_entries_carry_minute_kind_and_their_fields() -> void:
	var trace := NpcDecisionTrace.new()
	var scores: Dictionary = {"work": {"total": 0.7, "need": 0.1}, "rest": {"total": 0.2}}
	assert_true(trace.record(480.0, NpcDecisionTrace.GOAL, {"reason": "plan_kept", "outcome": "applied",
		"request_id": "r1", "selected": "work", "duration": 60.0, "scores": scores,
		"incident_id": "assault:1"}))
	assert_true(trace.record(481.0, NpcDecisionTrace.REQUEST, {"request_id": "r1",
		"request_kind": "goal", "read_versions": {"knowledge": 3}, "latency_ms": 40,
		"outcome": "applied"}))
	assert_true(trace.record(482.0, NpcDecisionTrace.EFFECT, {"reason": "commitment_completed",
		"commitment_id": "c:1", "task_id": "task:1"}))
	assert_true(trace.record(483.0, NpcDecisionTrace.SAVE_FAILURE, {"reason": "save_error:7"}))
	var entries: Array[Dictionary] = trace.entries()
	assert_eq(entries.size(), 4)
	assert_eq(entries[0], {"minute": 480.0, "kind": "goal", "reason": "plan_kept",
		"outcome": "applied", "request_id": "r1", "selected": "work", "duration": 60.0,
		"scores": scores, "incident_id": "assault:1"})
	assert_eq(entries[1].read_versions, {"knowledge": 3})
	assert_eq(entries[2].kind, NpcDecisionTrace.EFFECT)
	assert_eq(trace.latest(NpcDecisionTrace.GOAL).selected, "work")
	assert_eq(trace.latest(NpcDecisionTrace.SAVE_FAILURE).reason, "save_error:7")
	assert_eq(trace.latest(NpcDecisionTrace.TRANSITION), {})

func test_reasons_and_outcomes_must_be_codes_not_prose() -> void:
	var trace := NpcDecisionTrace.new()
	assert_false(trace.record(480.0, NpcDecisionTrace.GOAL,
		{"reason": "I felt hungry, so I decided to eat."}))
	assert_false(trace.record(480.0, NpcDecisionTrace.REQUEST, {"outcome": "Applied"}))
	assert_false(trace.record(480.0, NpcDecisionTrace.EFFECT, {"reason": 3}))
	assert_false(trace.record(480.0, NpcDecisionTrace.EFFECT,
		{"reason": "a".repeat(NpcDecisionTrace.MAX_CODE_LENGTH + 1)}))
	assert_true(trace.record(480.0, NpcDecisionTrace.GOAL, {"reason": "jev:need.hunger-1"}))
	assert_eq(NpcDecisionTrace.code(" Restore Invalid "), "restore_invalid")
	assert_true(NpcDecisionTrace.is_code(NpcDecisionTrace.code("Interrupt danger")))
	assert_eq(trace.entries().size(), 1)

func test_rejects_unknown_kinds_bad_minutes_and_reserved_fields() -> void:
	var trace := NpcDecisionTrace.new()
	assert_false(trace.record(480.0, "thought", {}))
	assert_false(trace.record(INF, NpcDecisionTrace.GOAL, {}))
	assert_false(trace.record(NAN, NpcDecisionTrace.GOAL, {}))
	assert_false(trace.record(480.0, NpcDecisionTrace.GOAL, {"minute": 1.0}))
	assert_false(trace.record(480.0, NpcDecisionTrace.GOAL, {"kind": "request"}))
	assert_eq(trace.entries(), [])
	assert_eq(trace.version, 0)

func test_entries_are_copies() -> void:
	var trace := NpcDecisionTrace.new()
	var fields: Dictionary = {"reason": "plan_kept", "scores": {"work": {"total": 0.5}}}
	assert_true(trace.record(480.0, NpcDecisionTrace.GOAL, fields))
	fields.scores.work.total = 9.0
	var copied: Array[Dictionary] = trace.entries()
	copied[0].scores.work.total = 8.0
	var latest: Dictionary = trace.latest(NpcDecisionTrace.GOAL)
	latest.scores.work.total = 7.0
	assert_eq(trace.latest(NpcDecisionTrace.GOAL).scores.work.total, 0.5)

func test_brain_traces_task_transitions_with_code_reasons() -> void:
	var brain := NpcBrain.new()
	var mind := NpcMindState.new("trace_npc")
	var actor := Node.new()
	brain.setup("trace_npc", mind, actor, null, NpcBehaviorTuning.new(), 1)
	brain.controller.transitioned.emit({"minute": 500.0, "task_id": "task:1", "kind": "routine",
		"from": "RUNNING", "to": "SUSPENDED", "reason": "Interrupt Danger"})
	var entry: Dictionary = brain.trace.latest(NpcDecisionTrace.TRANSITION)
	assert_eq(entry, {"minute": 500.0, "kind": "transition", "task_id": "task:1",
		"task_kind": "routine", "from": "RUNNING", "to": "SUSPENDED", "reason": "interrupt_danger"})
	brain.free()
	actor.free()
