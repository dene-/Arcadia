extends "res://tests/test_case.gd"

const Appraisals = preload("res://tests/fixtures/npc_appraisal_fixture.gd")
const FIXTURE: String = "res://tests/fixtures/memory_paraphrase.json"
const NPC: String = "elder"

var _serial: int = 0

func _profile() -> NpcProfile:
	var profile := NpcProfile.new()
	profile.npc_id = StringName(NPC)
	return profile

# A store whose only archive is the paraphrase fixture, loaded through from_save_data.
func _fixture_store(data: Dictionary) -> NpcMemoryStore:
	var memories: Array = []
	for entry: Dictionary in data.memories:
		var memory: Dictionary = NpcMemory.create(entry.id, "episodic", entry.gist, entry.source, 0)
		memory.created_minute = 0.0
		memory.people = entry.people.duplicate()
		memory.topics = entry.topics.duplicate()
		memory.importance = float(entry.importance)
		if entry.has("incident_id"):
			memory.incident_id = entry.incident_id
		if entry.has("evidence_ids"):
			memory.evidence_ids = entry.evidence_ids.duplicate()
		memories.append(memory)
	var smell: Dictionary = NpcMemory.create("mem:smoke", "episodic", "A fire long ago.", "authored", 0)
	smell.sensory_cues = ["burning lamp oil"]
	memories.append(smell)
	var plan: Dictionary = NpcMemory.create("mem:plan", "prospective", "Mend the fence.", "npc_statement", 0)
	memories.append(plan)
	var store := NpcMemoryStore.new()
	assert_true(store.from_save_data({"version": NpcMemoryStore.SAVE_VERSION, "turn": 0,
		"world_minute": 600.0, "next_memory_id": 1, "npcs": {NPC: {"recent_dialogue": [],
		"memories": memories, "recent_events": [], "observations": [], "next_observation_id": 1,
		"heard_origins": {}}}}))
	return store

func _full(store: NpcMemoryStore, retriever: NpcMemoryRetriever, message: String,
		current: Dictionary, links: NpcMemoryRetriever.Links) -> Array[Dictionary]:
	return retriever.retrieve(store.snapshot(NPC).memories, message, current,
		NpcCognitionProfile.new(), store.world_minute, links)

func _candidates(store: NpcMemoryStore, message: String, current: Dictionary = {},
		links: NpcMemoryRetriever.Links = null) -> Array[String]:
	return store.recall_candidates(NPC, NpcMemoryRetriever.new().cue_keys(message, current, links))

func test_recall_over_index_candidates_ranks_exactly_like_the_full_archive() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var store: NpcMemoryStore = _fixture_store(data)
	var links: NpcMemoryRetriever.Links = NpcMemoryRetriever.links_for(
		{"known_townspeople": data.people, "open_commitments": data.open_commitments})
	var lexical := NpcMemoryRetriever.new()
	var no_aliases: Dictionary[String, String] = {}
	lexical.topic_aliases = no_aliases
	var contexts: Array[Dictionary] = [{}, {"participants": ["player"]},
		{"participants": ["garrin_holt"], "location": "forge"},
		{"sensory_cues": ["burning lamp oil"]}]
	var messages: Array = data.queries.map(func(query: Dictionary) -> String: return query.query)
	messages.append_array(["Good morning.", "Hello", "Ada Holt", "corin"])
	var compared: int = 0
	for retriever: NpcMemoryRetriever in [NpcMemoryRetriever.new(), lexical]:
		for link: NpcMemoryRetriever.Links in [null, links]:
			for current: Dictionary in contexts:
				for message: String in messages:
					var expected: Array[Dictionary] = _full(store, retriever, message, current, link)
					assert_eq(store.recall(NPC, retriever, message, current, NpcCognitionProfile.new(),
						link), expected, "%s %s" % [message, current])
					compared += 1
	assert_eq(compared, 2 * 2 * contexts.size() * messages.size())

func test_candidates_stay_bounded_by_the_cue() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var store: NpcMemoryStore = _fixture_store(data)
	var links: NpcMemoryRetriever.Links = NpcMemoryRetriever.links_for(
		{"known_townspeople": data.people, "open_commitments": data.open_commitments})
	assert_eq(_candidates(store, "Good morning."), ["mem:plan"] as Array[String],
		"Only the open intention answers a greeting")
	assert_eq(_candidates(store, "Good morning.", {}, links),
		["mem:death", "mem:fight", "mem:noise", "mem:report", "mem:plan"] as Array[String],
		"Commitment evidence reaches its memories and their incident")
	assert_eq(_candidates(store, "Is the well water safe?"), ["mem:well", "mem:plan"] as Array[String])
	assert_eq(_candidates(store, "How is Ada?", {},
		NpcMemoryRetriever.links_for({"known_townspeople": data.people})),
		["mem:funeral", "mem:ada", "mem:plan"] as Array[String], "A name reaches only its resident")

func _hurt(text: String) -> NpcObservation:
	_serial += 1
	var observation: NpcObservation = NpcObservation.from_perception(NPC, "event:%d" % _serial,
		500.0, &"outdoors", {"kind": "actor_hurt", "sense": "sight", "text": text,
		"player_involved": false,
		"participants": [{"id": "mira", "name": "Mira", "role": "hurt_person"}]})
	observation.incident_id = "incident:brawl"
	return observation

func _commit(store: NpcMemoryStore, observation: NpcObservation) -> void:
	var inbox: NpcEvidenceInbox = store.minds.get_mind(NPC).evidence
	assert_true(inbox.enqueue(observation))
	assert_not_null(inbox.claim(observation.observation_id, 500.0))
	assert_eq(store.commit_evidence(NPC, observation, Appraisals.make(true, 0.3, 0.2)), "")

func _archive_ids(store: NpcMemoryStore) -> Array[String]:
	var ids: Array[String] = []
	for memory: Dictionary in store.snapshot(NPC).memories:
		ids.append(memory.id)
	return ids

func test_index_follows_admission_repetition_consolidation_and_load() -> void:
	var store := NpcMemoryStore.new()
	store.ensure_npc(_profile())
	store.set_world_minute(500.0)
	assert_true(_candidates(store, "Was Mira struck?").is_empty())
	var first: NpcObservation = _hurt("Mira was struck, blow 0.")
	_commit(store, first)
	assert_eq(_candidates(store, "Was Mira struck?"), _archive_ids(store), "Admission is indexed")
	# The same episode seen again only adds its evidence id, which the index then reaches.
	var again: NpcObservation = _hurt("Mira was struck, blow 0.")
	_commit(store, again)
	assert_eq(_archive_ids(store).size(), 1)
	var links := NpcMemoryRetriever.Links.new()
	links.commitment_evidence[again.observation_id] = true
	assert_eq(_candidates(store, "Good morning.", {}, links), _archive_ids(store))
	for index: int in range(1, 4):
		_commit(store, _hurt("Mira was struck, blow %d." % index))
	assert_eq(_candidates(store, "Was Mira struck?").size(), 4)
	assert_eq(store.maintain({}, 1000.0).memories_merged, 3)
	assert_eq(_candidates(store, "Was Mira struck?"), _archive_ids(store),
		"Consolidation drops merged-away memories from the index")
	var restored := NpcMemoryStore.new()
	assert_true(restored.from_save_data(JSON.parse_string(JSON.stringify(store.to_save_data()))))
	assert_eq(_candidates(restored, "Was Mira struck?"), _archive_ids(store), "Loading rebuilds the index")
	var retriever := NpcMemoryRetriever.new()
	assert_eq(restored.recall(NPC, retriever, "Was Mira struck?", {}, NpcCognitionProfile.new()),
		_full(restored, retriever, "Was Mira struck?", {}, null))
	assert_false(restored.recall(NPC, retriever, "Was Mira struck?", {}, NpcCognitionProfile.new()).is_empty())

func test_working_memory_copies_only_the_bounded_windows() -> void:
	var store := NpcMemoryStore.new()
	assert_eq(store.working_memory(NPC), {})
	store.ensure_npc(_profile())
	store.record_event(_profile(), "The bell rang.")
	var state: Dictionary = store.working_memory(NPC)
	assert_eq(state.keys(), ["recent_dialogue", "recent_events", "observations"])
	state.recent_events.append("Tampered.")
	assert_eq(store.working_memory(NPC).recent_events, ["The bell rang."])
