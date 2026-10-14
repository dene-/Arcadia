extends "res://tests/test_case.gd"

const FIXTURE: String = "res://tests/fixtures/memory_paraphrase.json"
## A paraphrase hits when the expected memory is among this many recalls.
const HIT_RANK: int = 3

func _memory(id: String, gist: String, people: Array = [], incident: String = "",
		evidence: Array = []) -> Dictionary:
	var memory: Dictionary = NpcMemory.create(id, "episodic", gist, "observed_event", 0)
	memory.created_minute = 0.0
	memory.people = people.duplicate()
	if not incident.is_empty():
		memory.incident_id = incident
	if not evidence.is_empty():
		memory.evidence_ids = evidence.duplicate()
	return memory

# Legacy memories omit the incident and evidence fields.
func _fixture_memories(data: Dictionary, legacy: bool) -> Array:
	var memories: Array = []
	for entry: Dictionary in data.memories:
		var memory: Dictionary = _memory(entry.id, entry.gist, entry.people,
			"" if legacy else String(entry.get("incident_id", "")),
			[] if legacy else entry.get("evidence_ids", []))
		memory.source = entry.source
		memory.topics = entry.topics.duplicate()
		memory.importance = float(entry.importance)
		memories.append(memory)
	return memories

func _hit_rate(retriever: NpcMemoryRetriever, memories: Array, queries: Array,
		links: NpcMemoryRetriever.Links) -> float:
	var hits: int = 0
	for query: Dictionary in queries:
		var recalled: Array[Dictionary] = retriever.retrieve(memories, query.query, {},
			NpcCognitionProfile.new(), 0.0, links)
		for index: int in range(mini(recalled.size(), HIT_RANK)):
			if recalled[index].id == query.expected:
				hits += 1
				break
	return float(hits) / float(queries.size())

func _ids(recalled: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for view: Dictionary in recalled:
		ids.append(view.id)
	return ids

func test_paraphrases_recall_more_than_the_lexical_baseline() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_true(data.queries.size() >= 12)
	var lexical := NpcMemoryRetriever.new()
	var no_aliases: Dictionary[String, String] = {}
	lexical.topic_aliases = no_aliases
	var baseline: float = _hit_rate(lexical, _fixture_memories(data, true), data.queries, null)
	var links: NpcMemoryRetriever.Links = NpcMemoryRetriever.links_for(
		{"known_townspeople": data.people, "open_commitments": data.open_commitments})
	var linked: float = _hit_rate(NpcMemoryRetriever.new(), _fixture_memories(data, false),
		data.queries, links)
	print("memory paraphrase hit rate (top %d of %d queries): lexical %.2f, linked %.2f"
		% [HIT_RANK, data.queries.size(), baseline, linked])
	assert_true(linked > baseline)
	assert_true(linked >= 0.75)

func test_display_and_first_names_resolve_to_resident_ids() -> void:
	var people: Array = [{"id": "resident_1", "name": "Garrin Holt"},
		{"id": "resident_2", "name": "Garrin Reed"}, {"id": "resident_3", "name": "Ada Holt"}]
	var memories: Array = [_memory("ada", "The cooper's wife brought me a pie.", ["resident_3"]),
		_memory("reed", "Someone mended my roof.", ["resident_2"])]
	var retriever := NpcMemoryRetriever.new()
	var links: NpcMemoryRetriever.Links = NpcMemoryRetriever.links_for({"family_members": people})
	var cognition := NpcCognitionProfile.new()
	assert_eq(_ids(retriever.retrieve(memories, "How is Ada?", {}, cognition, 0.0)), [])
	assert_eq(_ids(retriever.retrieve(memories, "How is Ada?", {}, cognition, 0.0, links)), ["ada"])
	assert_eq(_ids(retriever.retrieve(memories, "Did Garrin Reed help?", {}, cognition, 0.0, links)),
		["reed"])
	# A first name two residents share names neither of them.
	assert_eq(_ids(retriever.retrieve(memories, "How is Garrin?", {}, cognition, 0.0, links)), [])

func test_strong_match_recalls_the_rest_of_its_incident_and_legacy_memories_load() -> void:
	var memories: Array = [_memory("death", "Garrin died behind the forge.", [], "inc:forge"),
		_memory("noise", "I heard shouting late at night.", [], "inc:forge"),
		_memory("legacy", "I heard shouting from the mill."),
		_memory("other", "I heard shouting at the market.", [], "inc:market")]
	var links: NpcMemoryRetriever.Links = NpcMemoryRetriever.links_for(
		{"open_commitments": [{"kind": "report_discovery", "evidence_ids": ["obs:1"]}]})
	var recalled: Array[Dictionary] = NpcMemoryRetriever.new().retrieve(memories,
		"Was someone killed?", {}, NpcCognitionProfile.new(), 0.0, links)
	assert_eq(_ids(recalled), ["death", "noise"])
	assert_true(recalled[0].recall_quality < 1.0)

func test_commitment_evidence_recalls_the_memory_it_rests_on() -> void:
	var memories: Array = [_memory("found", "Something lay behind the forge.", [], "", ["obs:1"]),
		_memory("unrelated", "Something lay by the well.", [], "", ["obs:2"])]
	var retriever := NpcMemoryRetriever.new()
	var cognition := NpcCognitionProfile.new()
	var mind := NpcMindState.new("holt_partner")
	var others: Array[String] = ["garrin_holt"]
	var evidence: Array[String] = ["obs:1"]
	assert_false(mind.commitments.create("report_discovery", others, evidence, 400.0).is_empty())
	var links: NpcMemoryRetriever.Links = NpcMemoryRetriever.links_for(
		NpcCognitiveContext.mind_context(mind))
	assert_eq(_ids(retriever.retrieve(memories, "Good morning.", {}, cognition, 0.0)), [])
	assert_eq(_ids(retriever.retrieve(memories, "Good morning.", {}, cognition, 0.0, links)), ["found"])

func test_concerns_include_grief_duty_and_commitments_without_the_player() -> void:
	var mind := NpcMindState.new("holt_partner")
	assert_true(mind.add_bereavement("garrin_holt", "obs:1", 400.0))
	var others: Array[String] = ["garrin_holt"]
	var evidence: Array[String] = ["obs:1"]
	assert_false(mind.commitments.create("report_discovery", others, evidence, 400.0, -1.0, 0.8).is_empty())
	var current: Dictionary = NpcCognitiveContext.mind_context(mind)
	current.world_minute = 460.0
	current.family_members = [{"id": "garrin_holt", "name": "Garrin Holt", "relationship": "spouse"}]
	current.current_task = {"kind": "guard", "phase": "watching", "activity": "guard_post", "label": "Guard"}
	var state: Dictionary = {"recent_events": [], "observations": []}
	var context: Dictionary = NpcCognitiveContext.build(state, current)
	var kinds: Array[String] = []
	for concern: Dictionary in context.current_concerns:
		kinds.append(concern.kind)
	assert_eq(kinds, ["bereavement", "duty", "commitment"])
	assert_eq(context.current_concerns[0].name, "Garrin Holt")
	assert_eq(context.current_concerns[0].relationship, "spouse")
	assert_eq(context.current_concerns[0].age_game_minutes, 60.0)
	assert_eq(context.current_concerns[2].subjects, ["Garrin Holt"])
	assert_false(context.has("personal_concerns"))
	assert_false(context.has("open_commitments"))

func test_observations_about_a_lost_relative_lead_and_the_cap_holds() -> void:
	var current: Dictionary = {"world_minute": 460.0,
		"personal_concerns": [{"kind": "bereavement", "subject": "garrin_holt", "minute": 400.0}],
		"current_task": {"kind": "recovery", "phase": "resting"},
		"open_commitments": [{"kind": "visit_grave", "other_ids": ["garrin_holt"], "priority": 0.5}]}
	var about: Dictionary = {"text": "Ada saw Garrin carried to the hill.", "sense": "sight",
		"player_involved": false, "status": "assessed", "created_at": 0.0, "world_minute": 450.0,
		"participants": [{"id": "garrin_holt"}]}
	var stranger: Dictionary = about.duplicate(true)
	stranger.text = "A stranger walked past."
	stranger.participants = [{"id": "tovan_reed"}]
	var context: Dictionary = NpcCognitiveContext.build(
		{"recent_events": [], "observations": [stranger, about]}, current)
	assert_eq(context.past_observations.size(), 2)
	assert_eq(context.current_concerns.size(), NpcCognitiveContext.MAX_CONCERNS)
	assert_eq(context.current_concerns[0].kind, "observation")
	assert_eq(context.current_concerns[0].text, about.text)
	assert_eq(context.current_concerns[1].kind, "bereavement")
	assert_eq(context.current_concerns[2].kind, "duty")
