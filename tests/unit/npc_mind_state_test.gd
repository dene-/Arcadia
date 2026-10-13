extends "res://tests/test_case.gd"

func _round_trip(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))

func _checkpoint(task_id: String = "routine:1") -> Dictionary:
	return {"task_id": task_id, "kind": "routine", "phase": "travel", "status": "RUNNING",
		"started_minute": 480.0, "deadline_minute": -1.0, "generation": 2,
		"evidence_ids": ["obs:1"], "commitment_ids": [], "claims": ["locomotion"],
		"params": {"place": "market"}, "progress": {"steps": 3}, "suspended": {}}

func _commit(commitments: NpcCommitments, kind: String = "visit_grave") -> String:
	var others: Array[String] = ["mira"]
	var evidence: Array[String] = ["obs:9"]
	return commitments.create(kind, others, evidence, 100.0)

# Relationship graph

func test_delta_is_applied_once_per_receipt_and_clamped_per_change() -> void:
	var graph := NpcRelationshipGraph.new()
	assert_true(graph.apply_delta("player", {"trust": 0.5, "fear": -0.5}, "r1"))
	var after: Dictionary = graph.get_relationship("player")
	assert_eq(float(after.trust), 0.1)
	assert_eq(float(after.fear), 0.0)
	var version: int = graph.version
	assert_false(graph.apply_delta("player", {"trust": 0.1}, "r1"))
	assert_eq(graph.get_relationship("player"), after)
	assert_eq(graph.version, version)
	assert_true(graph.apply_delta("player", {"trust": 0.1}, "r2"))
	assert_true(absf(float(graph.get_relationship("player").trust) - 0.2) < 0.0001)

func test_unknown_subject_is_neutral_and_does_not_leak_a_mutable_reference() -> void:
	var graph := NpcRelationshipGraph.new()
	assert_eq(graph.get_relationship("ghost"), NpcRelationshipState.initial())
	assert_false(graph.has_subject("ghost"))
	graph.apply_delta("mira", {"trust": 0.05}, "r1")
	var copy: Dictionary = graph.get_relationship("mira")
	copy["trust"] = 1.0
	assert_true(float(graph.get_relationship("mira").trust) < 0.1)
	assert_eq(graph.subjects(), ["mira"] as Array[String])

func test_invalid_deltas_do_not_mutate_or_consume_the_receipt() -> void:
	var graph := NpcRelationshipGraph.new()
	assert_false(graph.apply_delta("", {"trust": 0.1}, "r1"))
	assert_false(graph.apply_delta("mira", {"trust": 0.1}, ""))
	assert_false(graph.apply_delta("mira", {"loyalty": 0.1}, "r1"))
	assert_false(graph.apply_delta("mira", {"trust": NAN}, "r1"))
	assert_false(graph.apply_delta("mira", {"trust": "high"}, "r1"))
	assert_eq(graph.version, 0)
	assert_false(graph.has_subject("mira"))
	assert_false(graph.has_receipt("r1"))
	assert_true(graph.apply_delta("mira", {"trust": 0.1}, "r1"))

func test_seed_only_fills_unknown_subjects_with_valid_values() -> void:
	var graph := NpcRelationshipGraph.new()
	assert_true(graph.seed_relationship("mira", {"trust": 0.4, "familiarity": 0.7}))
	var seeded: Dictionary = graph.get_relationship("mira")
	assert_eq(float(seeded.trust), 0.4)
	assert_eq(float(seeded.fear), 0.0)
	assert_false(graph.seed_relationship("mira", {"trust": -0.4}))
	assert_eq(graph.get_relationship("mira"), seeded)
	assert_false(graph.seed_relationship("", {}))
	assert_false(graph.seed_relationship("a", {"fear": -0.1}))
	assert_false(graph.seed_relationship("a", {"trust": 1.5}))
	assert_false(graph.seed_relationship("a", {"trust": INF}))
	assert_false(graph.seed_relationship("a", {"bravery": 0.1}))
	assert_false(graph.has_subject("a"))
	graph.apply_delta("b", {"trust": 0.1}, "r1")
	assert_false(graph.seed_relationship("b", {"trust": 0.0}))

func test_seed_replace_overwrites_dimensions_and_rejects_invalid_values() -> void:
	var graph := NpcRelationshipGraph.new()
	graph.seed_relationship("mira", {"trust": 0.4, "familiarity": 0.7, "fear": 0.2})
	var before: int = graph.version
	assert_true(graph.seed_relationship("mira", {"affection": 0.5}, true))
	var replaced: Dictionary = graph.get_relationship("mira")
	assert_eq(float(replaced.affection), 0.5)
	assert_eq(float(replaced.trust), 0.0)
	assert_eq(float(replaced.fear), 0.0)
	assert_true(graph.version > before)
	assert_true(graph.seed_relationship("new", {"trust": 0.1}, true))
	assert_eq(float(graph.get_relationship("new").trust), 0.1)
	assert_false(graph.seed_relationship("mira", {"trust": 1.5}, true))
	assert_eq(graph.get_relationship("mira"), replaced)

func test_receipts_survive_serialization_and_still_block_replays() -> void:
	var graph := NpcRelationshipGraph.new()
	graph.seed_relationship("player", {"respect": -0.3})
	graph.apply_delta("player", {"trust": 0.1}, "r1")
	var restored := NpcRelationshipGraph.new()
	assert_true(restored.from_data(_round_trip(graph.to_data())))
	assert_true(restored.has_receipt("r1"))
	assert_false(restored.apply_delta("player", {"trust": 0.1}, "r1"))
	assert_eq(restored.get_relationship("player"), graph.get_relationship("player"))
	assert_true(restored.version > 0)

func test_receipts_are_a_fifo_window() -> void:
	var graph := NpcRelationshipGraph.new()
	for index: int in NpcRelationshipGraph.MAX_RECEIPTS + 1:
		assert_true(graph.apply_delta("mira", {"familiarity": 0.01}, "r%d" % index))
	assert_false(graph.has_receipt("r0"))
	assert_true(graph.has_receipt("r1"))
	assert_true(graph.has_receipt("r%d" % NpcRelationshipGraph.MAX_RECEIPTS))
	assert_eq(graph.to_data().receipts.size(), NpcRelationshipGraph.MAX_RECEIPTS)
	assert_true(NpcRelationshipGraph.is_valid_data(graph.to_data()))

func test_malformed_graph_data_is_rejected_atomically() -> void:
	var graph := NpcRelationshipGraph.new()
	graph.apply_delta("mira", {"trust": 0.1}, "keep")
	var before: Dictionary = graph.to_data()
	var out_of_range: Dictionary = {"subjects": {"a": NpcRelationshipState.initial()}, "receipts": []}
	out_of_range.subjects.a.fear = -0.5
	var bad_cases: Array[Dictionary] = [
		out_of_range,
		{"subjects": {"": NpcRelationshipState.initial()}, "receipts": []},
		{"subjects": {}, "receipts": ["x", "x"]},
		{"subjects": {}, "receipts": [""]},
		{"subjects": {}, "receipts": ["y".repeat(501)]},
		{"subjects": {}, "receipts": [5]},
		{"subjects": {}},
		{"subjects": {}, "receipts": [], "extra": 1},
	]
	for bad: Dictionary in bad_cases:
		assert_false(NpcRelationshipGraph.is_valid_data(bad))
		assert_false(graph.from_data(bad))
	assert_false(graph.from_data("nope"))
	assert_eq(graph.to_data(), before)

# Commitments

func test_commitments_resolve_exactly_once() -> void:
	var commitments := NpcCommitments.new()
	commitments.owner_id = "vale"
	var id: String = _commit(commitments)
	assert_eq(id, "commitment:vale:1")
	assert_true(commitments.link_task(id, "visit:1"))
	assert_true(commitments.resolve(id, "completed", 130.0))
	var done: Dictionary = commitments.get_commitment(id)
	assert_eq(done.status, "completed")
	assert_eq(float(done.resolved_minute), 130.0)
	assert_eq(done.task_id, "visit:1")
	var version: int = commitments.version
	assert_false(commitments.resolve(id, "failed", 140.0))
	assert_false(commitments.resolve(id, "completed", 140.0))
	assert_false(commitments.link_task(id, "visit:2"))
	assert_eq(commitments.get_commitment(id), done)
	assert_eq(commitments.version, version)
	assert_true(commitments.open_commitments().is_empty())

func test_commitments_reject_bad_inputs() -> void:
	var commitments := NpcCommitments.new()
	var none: Array[String] = []
	assert_eq(commitments.create("visit_grave", none, none, 1.0), "", "owner is empty")
	commitments.owner_id = "vale"
	assert_eq(commitments.create("gossip", none, none, 1.0), "")
	assert_eq(commitments.create("visit_grave", none, none, NAN), "")
	assert_eq(commitments.create("visit_grave", none, none, 1.0, INF), "")
	assert_eq(commitments.create("visit_grave", none, none, 1.0, -1.0, 1.5), "")
	assert_eq(commitments.create("visit_grave", none, none, 1.0, -1.0, -0.1), "")
	assert_eq(commitments.version, 0)
	var id: String = _commit(commitments)
	assert_false(commitments.resolve(id, "open", 5.0))
	assert_false(commitments.resolve(id, "done", 5.0))
	assert_false(commitments.resolve(id, "failed", NAN))
	assert_false(commitments.resolve("commitment:vale:99", "failed", 5.0))
	assert_false(commitments.link_task(id, ""))
	assert_eq(commitments.get_commitment(id).status, "open")
	assert_eq(commitments.get_commitment("missing"), {})

func test_open_commitments_keep_creation_order_and_ids_never_repeat() -> void:
	var commitments := NpcCommitments.new()
	commitments.owner_id = "vale"
	var first: String = _commit(commitments, "visit_grave")
	var second: String = _commit(commitments, "check_relative")
	commitments.resolve(first, "cancelled", 5.0)
	var third: String = _commit(commitments, "report_discovery")
	var open: Array[Dictionary] = commitments.open_commitments()
	assert_eq(open.size(), 2)
	assert_eq(open[0].id, second)
	assert_eq(open[1].id, third)
	assert_ne(third, first)
	open[0]["status"] = "failed"
	assert_eq(commitments.get_commitment(second).status, "open")

func test_commitments_are_capped_including_closed_items() -> void:
	var commitments := NpcCommitments.new()
	commitments.owner_id = "vale"
	for index: int in NpcCommitments.MAX_ITEMS:
		var id: String = _commit(commitments)
		assert_ne(id, "")
		commitments.resolve(id, "completed", 1.0)
	assert_eq(_commit(commitments), "")
	assert_true(NpcCommitments.is_valid_data(commitments.to_data(), "vale"))

func test_commitments_survive_json_and_keep_numbering() -> void:
	var commitments := NpcCommitments.new()
	commitments.owner_id = "vale"
	var first: String = _commit(commitments)
	var second: String = _commit(commitments, "attend_obligation")
	commitments.link_task(second, "task:2")
	commitments.resolve(first, "failed", 12.0)
	var restored := NpcCommitments.new()
	restored.owner_id = "vale"
	assert_true(restored.from_data(_round_trip(commitments.to_data())))
	assert_eq(restored.get_commitment(first).status, "failed")
	assert_eq(restored.get_commitment(second).task_id, "task:2")
	assert_eq(restored.open_commitments().size(), 1)
	assert_eq(_commit(restored), "commitment:vale:3")
	assert_eq(typeof(restored.to_data().next_id), TYPE_INT)

func test_commitment_data_for_another_owner_or_tampered_is_rejected_atomically() -> void:
	var commitments := NpcCommitments.new()
	commitments.owner_id = "vale"
	_commit(commitments)
	var data: Dictionary = commitments.to_data()
	assert_false(NpcCommitments.is_valid_data(data, "holt"))
	var stranger := NpcCommitments.new()
	stranger.owner_id = "holt"
	assert_false(stranger.from_data(data))
	assert_eq(stranger.version, 0)
	var tampered: Dictionary = commitments.to_data()
	tampered.items[0].kind = "gossip"
	assert_false(NpcCommitments.is_valid_data(tampered, "vale"))
	tampered = commitments.to_data()
	tampered.next_id = 1
	assert_false(NpcCommitments.is_valid_data(tampered, "vale"), "next_id must exceed used ids")
	tampered = commitments.to_data()
	tampered.items[0].erase("priority")
	assert_false(NpcCommitments.is_valid_data(tampered, "vale"))
	tampered = commitments.to_data()
	tampered.items.append(tampered.items[0].duplicate(true))
	assert_false(NpcCommitments.is_valid_data(tampered, "vale"), "duplicate id")
	assert_false(commitments.from_data(tampered))
	assert_eq(commitments.open_commitments().size(), 1)

# Task checkpoint

func test_checkpoint_validation_rejects_missing_extra_and_wrong_values() -> void:
	assert_true(NpcMindState.is_valid_task_checkpoint(_checkpoint()))
	var mutations: Array[Callable] = [
		func(c: Dictionary) -> void: c.erase("claims"),
		func(c: Dictionary) -> void: c["owner"] = "x",
		func(c: Dictionary) -> void: c.status = "PAUSED",
		func(c: Dictionary) -> void: c.status = "running",
		func(c: Dictionary) -> void: c.task_id = "",
		func(c: Dictionary) -> void: c.task_id = "t".repeat(201),
		func(c: Dictionary) -> void: c.kind = "",
		func(c: Dictionary) -> void: c.phase = "p".repeat(65),
		func(c: Dictionary) -> void: c.started_minute = -1.0,
		func(c: Dictionary) -> void: c.started_minute = NAN,
		func(c: Dictionary) -> void: c.deadline_minute = 100.0,
		func(c: Dictionary) -> void: c.deadline_minute = -2.0,
		func(c: Dictionary) -> void: c.generation = -1,
		func(c: Dictionary) -> void: c.generation = 1.5,
		func(c: Dictionary) -> void: c.evidence_ids = [""],
		func(c: Dictionary) -> void: c.claims = [3],
		func(c: Dictionary) -> void: c.commitment_ids = range(65).map(func(i: int) -> String: return "c%d" % i),
		func(c: Dictionary) -> void: c.params = [],
		func(c: Dictionary) -> void: c.progress = {"node": Node.new()},
		func(c: Dictionary) -> void: c.params = {"x": NAN},
		func(c: Dictionary) -> void: c.params = {1: "int key"},
		func(c: Dictionary) -> void: c.suspended = "none",
	]
	for index: int in mutations.size():
		var candidate: Dictionary = _checkpoint()
		mutations[index].call(candidate)
		var valid: bool = NpcMindState.is_valid_task_checkpoint(candidate)
		for value: Variant in candidate.values():
			if value is Dictionary and value.has("node"):
				value.node.free()
		assert_false(valid, "mutation %d must be invalid" % index)

func test_checkpoint_allows_one_suspended_level_only() -> void:
	var one_level: Dictionary = _checkpoint("safety:1")
	one_level.suspended = _checkpoint("routine:1")
	assert_true(NpcMindState.is_valid_task_checkpoint(one_level))
	var two_levels: Dictionary = _checkpoint("safety:1")
	var middle: Dictionary = _checkpoint("social:1")
	middle.suspended = _checkpoint("routine:1")
	two_levels.suspended = middle
	assert_false(NpcMindState.is_valid_task_checkpoint(two_levels))
	assert_false(NpcMindState.is_valid_task_checkpoint(one_level, false))
	var broken: Dictionary = _checkpoint("safety:1")
	broken.suspended = _checkpoint("routine:1")
	broken.suspended.status = "BOGUS"
	assert_false(NpcMindState.is_valid_task_checkpoint(broken))

func test_set_checkpoint_stores_a_copy_and_empty_clears() -> void:
	var mind := NpcMindState.new("vale")
	assert_true(mind.task_checkpoint().is_empty())
	var input: Dictionary = _checkpoint()
	assert_true(mind.set_task_checkpoint(input))
	input.params.place = "changed"
	assert_eq(mind.task_checkpoint().params.place, "market")
	var output: Dictionary = mind.task_checkpoint()
	output.params.place = "mutated"
	assert_eq(mind.task_checkpoint().params.place, "market")
	var task_version: int = int(mind.versions().task)
	var invalid: Dictionary = _checkpoint()
	invalid.status = "NOPE"
	assert_false(mind.set_task_checkpoint(invalid))
	assert_eq(mind.task_checkpoint().task_id, "routine:1")
	assert_eq(int(mind.versions().task), task_version)
	assert_true(mind.set_task_checkpoint({}))
	assert_true(mind.task_checkpoint().is_empty())
	assert_eq(int(mind.versions().task), task_version + 1)

# Mind state

func test_sections_require_json_safe_values_and_bump_only_their_version() -> void:
	var mind := NpcMindState.new("vale")
	var before: Dictionary = mind.versions()
	assert_true(mind.set_condition({"energy": 0.5, "tags": ["tired"]}))
	assert_eq(int(mind.versions().condition), int(before.condition) + 1)
	assert_eq(int(mind.versions().knowledge), int(before.knowledge))
	assert_eq(int(mind.versions().evidence), int(before.evidence))
	var wide: Dictionary = {}
	for index: int in 257:
		wide["k%d" % index] = index
	assert_false(mind.set_condition(wide))
	assert_eq(mind.condition, {"energy": 0.5, "tags": ["tired"]})
	assert_eq(mind.versions(), {"relationships": 0, "commitments": 0, "task": 0,
		"condition": 1, "knowledge": 0, "evidence": 0})

func test_decision_sequence_increments_and_persists() -> void:
	var mind := NpcMindState.new("vale")
	assert_eq(mind.next_decision(), 1)
	assert_eq(mind.next_decision(), 2)
	var restored := NpcMindState.new("vale")
	assert_true(restored.from_data(_round_trip(mind.to_data())))
	assert_eq(restored.next_decision(), 3)

func test_mind_state_survives_json_round_trip_with_canonical_types() -> void:
	var mind := NpcMindState.new("vale")
	mind.relationships.apply_delta("player", {"suspicion": 0.1}, "r1")
	var first: String = _commit(mind.commitments)
	mind.commitments.link_task(first, "visit:1")
	var checkpoint: Dictionary = _checkpoint("safety:1")
	checkpoint.suspended = _checkpoint("routine:1")
	mind.set_task_checkpoint(checkpoint)
	mind.set_condition({"energy": 0.25})
	mind.knowledge.record_sighting("tess", "market", Vector2(4, 5), 12.0, "ev:1")
	mind.next_decision()
	var restored := NpcMindState.new("vale")
	assert_true(restored.from_data(_round_trip(mind.to_data())))
	assert_false(restored.relationships.apply_delta("player", {"suspicion": 0.1}, "r1"))
	assert_eq(restored.relationships.get_relationship("player"), mind.relationships.get_relationship("player"))
	assert_eq(restored.commitments.get_commitment(first).task_id, "visit:1")
	var task: Dictionary = restored.task_checkpoint()
	assert_eq(typeof(task.generation), TYPE_INT)
	assert_eq(typeof(task.suspended.generation), TYPE_INT)
	assert_eq(task.suspended.task_id, "routine:1")
	assert_eq(restored.condition.energy, 0.25)
	assert_eq(restored.decision_sequence, 1)
	assert_eq(typeof(restored.decision_sequence), TYPE_INT)
	assert_eq(restored.knowledge.to_data(), mind.knowledge.to_data())
	assert_eq(restored.knowledge.known_locations("tess").size(), 1)
	assert_true(NpcMindState.is_valid_data(restored.to_data(), "vale"))
	assert_false(NpcMindState.is_valid_data(restored.to_data(), "holt"))

func test_malformed_mind_data_changes_nothing() -> void:
	var mind := NpcMindState.new("vale")
	mind.relationships.apply_delta("player", {"trust": 0.1}, "keep")
	mind.set_condition({"energy": 1.0})
	var before: Dictionary = mind.to_data()
	var good: Dictionary = NpcMindState.new("vale").to_data()
	var bad_cases: Array[Dictionary] = []
	for mutate: Callable in [
		func(d: Dictionary) -> void: d.version = 1,
		func(d: Dictionary) -> void: d.erase("knowledge"),
		func(d: Dictionary) -> void: d.erase("evidence"),
		func(d: Dictionary) -> void: d.knowledge = {"next_id": 1, "facts": [5]},
		func(d: Dictionary) -> void: d.evidence = {"items": []},
		func(d: Dictionary) -> void: d.erase("task"),
		func(d: Dictionary) -> void: d["extra"] = 1,
		func(d: Dictionary) -> void: d.decision_sequence = -1,
		func(d: Dictionary) -> void: d.decision_sequence = 1.5,
		func(d: Dictionary) -> void: d.condition = {"o": RefCounted.new()},
		func(d: Dictionary) -> void: d.task = {"task_id": "x"},
		func(d: Dictionary) -> void: d.relationships = {"subjects": {}, "receipts": [""]},
	]:
		var candidate: Dictionary = good.duplicate(true)
		mutate.call(candidate)
		bad_cases.append(candidate)
	for bad: Dictionary in bad_cases:
		assert_false(NpcMindState.is_valid_data(bad, "vale"))
		assert_false(mind.from_data(bad))
	assert_eq(mind.to_data(), before)
	assert_eq(mind.versions().relationships, 1)

# Store

func test_store_creates_minds_on_demand_and_lists_sorted_ids() -> void:
	var store := NpcMindStore.new()
	assert_null(store.get_mind(""))
	assert_false(store.has_mind("vale"))
	var vale: NpcMindState = store.get_mind("vale")
	assert_eq(vale.npc_id, "vale")
	assert_eq(vale.commitments.owner_id, "vale")
	assert_true(store.get_mind("vale") == vale)
	store.get_mind("brin")
	assert_eq(store.ids(), ["brin", "vale"] as Array[String])

func test_store_round_trips_through_json() -> void:
	var store := NpcMindStore.new()
	store.get_mind("vale").relationships.apply_delta("player", {"trust": 0.1}, "r1")
	_commit(store.get_mind("brin").commitments)
	store.get_mind("brin").set_task_checkpoint(_checkpoint())
	var restored := NpcMindStore.new()
	assert_true(restored.from_data(_round_trip(store.to_data())))
	assert_eq(restored.ids(), ["brin", "vale"] as Array[String])
	assert_false(restored.get_mind("vale").relationships.apply_delta("player", {"trust": 0.1}, "r1"))
	assert_eq(restored.get_mind("brin").commitments.open_commitments().size(), 1)
	assert_eq(restored.get_mind("brin").task_checkpoint().task_id, "routine:1")

func test_store_with_one_malformed_mind_leaves_existing_minds_untouched() -> void:
	var store := NpcMindStore.new()
	var vale: NpcMindState = store.get_mind("vale")
	vale.relationships.apply_delta("player", {"trust": 0.1}, "keep")
	var before: Dictionary = store.to_data()
	var source := NpcMindStore.new()
	source.get_mind("vale").relationships.apply_delta("player", {"fear": 0.1}, "other")
	source.get_mind("brin")
	var data: Dictionary = source.to_data()
	data.minds.brin.decision_sequence = -5
	assert_false(NpcMindStore.is_valid_data(data))
	assert_false(store.from_data(data))
	assert_eq(store.to_data(), before)
	assert_false(store.has_mind("brin"))
	assert_true(store.get_mind("vale") == vale)
	var foreign: Dictionary = source.to_data()
	foreign.minds.brin.commitments = {"next_id": 2, "items": [{"id": "commitment:holt:1"}]}
	assert_false(store.from_data(foreign))
	assert_eq(store.to_data(), before)

func test_store_restore_keeps_instances_and_drops_absent_ids() -> void:
	var store := NpcMindStore.new()
	var vale: NpcMindState = store.get_mind("vale")
	store.get_mind("gone")
	var source := NpcMindStore.new()
	source.get_mind("vale").relationships.apply_delta("player", {"trust": 0.1}, "r1")
	assert_true(store.from_data(source.to_data()))
	assert_true(store.get_mind("vale") == vale)
	assert_true(vale.relationships.has_receipt("r1"))
	assert_false(store.has_mind("gone"))

func test_store_rejects_bad_roots() -> void:
	assert_false(NpcMindStore.is_valid_data({"version": 2, "minds": {}}))
	assert_false(NpcMindStore.is_valid_data({"version": 1, "minds": []}))
	assert_false(NpcMindStore.is_valid_data({"version": 1, "minds": {"": NpcMindState.new("").to_data()}}))
	assert_false(NpcMindStore.is_valid_data({"version": 1}))
	assert_true(NpcMindStore.is_valid_data({"version": 1.0, "minds": {}}))
