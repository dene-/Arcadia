class_name NpcMemoryRetriever
extends RefCounted

## Selection and recall are separate. Never send the archive to an inference service.
const MAX_RECALLS: int = 6
const STOP_WORDS: Array[String] = ["the", "and", "you", "your", "that", "this", "with",
	"have", "what", "when", "were", "was", "for", "are", "about", "remember", "player"]

func retrieve(memories: Array, message: String, current: Dictionary,
		cognition: NpcCognitionProfile, minute: float) -> Array[Dictionary]:
	var words: PackedStringArray = _words(message + " " + str(current.get("location", "")))
	var sensory_words: PackedStringArray = _words(" ".join(current.get("sensory_cues", [])))
	var candidates: Array[Dictionary] = []
	for memory: Dictionary in memories:
		var text: String = memory.gist + " " + " ".join(memory.topics)
		var relevance: float = _overlap(words, text)
		var entities: float = _overlap(words, " ".join(memory.people + memory.places))
		# Presence is a recall cue even when the player only says hello.
		for participant: String in current.get("participants", []):
			if participant in memory.people or (participant == "player"
				and memory.source == "observed_event" and memory.gist.contains("the player")):
				entities = 1.0
		var sensory: float = _overlap(sensory_words, " ".join(memory.sensory_cues))
		var prospective: bool = memory.type == "prospective" and not memory.completed
		if relevance == 0.0 and entities == 0.0 and sensory == 0.0 and not prospective:
			continue
		var age: float = NpcMemory.retention_age(memory, minute)
		var recency: float = exp(-float(age) / 100.0)
		var rehearsal: float = minf(float(memory.recall_count) / 10.0, 1.0)
		var score: float = relevance * 0.4 + entities * 0.2 + memory.importance * 0.15 \
			+ memory.emotional_intensity * 0.1 + recency * 0.1 + rehearsal * 0.05 \
			+ sensory * cognition.sensory_association * 0.3
		if prospective:
			score += 0.1
		candidates.append({"memory": memory, "score": score, "sensory": sensory})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if is_equal_approx(a.score, b.score):
			return String(a.memory.id) < String(b.memory.id)
		return a.score > b.score)
	var result: Array[Dictionary] = []
	for index: int in range(mini(candidates.size(), MAX_RECALLS)):
		var candidate: Dictionary = candidates[index]
		result.append(recall(candidate.memory, cognition, minute, candidate.sensory))
	return result

func recall(memory: Dictionary, cognition: NpcCognitionProfile,
		minute: float, sensory_match: float = 0.0) -> Dictionary:
	var age: float = NpcMemory.retention_age(memory, minute)
	var retention: float = 40.0 + memory.importance * 800.0 \
		+ memory.emotional_intensity * cognition.emotional_retention * 500.0
	var skill: float = cognition.social_recall if memory.type == "social" else cognition.factual_recall
	var quality: float = clampf(memory.importance * 0.25 \
		+ memory.emotional_intensity * cognition.emotional_retention * 0.2 \
		+ skill * 0.15 + memory.vividness * 0.1 + exp(-float(age) / retention) * 0.2 \
		+ minf(float(memory.recall_count) / 10.0, 1.0) * 0.1 \
		+ sensory_match * cognition.sensory_association * 0.15, 0.0, 1.0)
	var tier: String = "familiarity"
	if quality >= 0.8:
		tier = "vivid"
	elif quality >= 0.6:
		tier = "clear"
	elif quality >= 0.4:
		tier = "fuzzy"
	elif quality >= 0.2:
		tier = "fragmentary"
	var view: Dictionary = {"id": memory.id, "type": memory.type, "source": memory.source,
		"confidence": memory.confidence, "recall_quality": quality, "recall_tier": tier,
		"completed": memory.completed, "topics": memory.topics.slice(0, 3)}
	if quality >= 0.4:
		view["gist"] = memory.gist
		view["known_gaps"] = memory.known_gaps.duplicate()
	if quality * cognition.name_recall >= 0.35:
		view["people"] = memory.people.duplicate()
	if quality >= 0.6:
		view["important_details"] = memory.important_details.duplicate()
		view["places"] = memory.places.duplicate()
	if quality >= 0.8:
		view["weak_details"] = memory.weak_details.duplicate()
	if quality >= 0.6 or sensory_match * cognition.sensory_association >= 0.4:
		view["sensory_cues"] = memory.sensory_cues.slice(0, 2)
	if quality * cognition.name_recall < 0.35:
		for key: String in view.keys():
			if key in ["id", "type", "source", "recall_tier"]:
				continue
			if view[key] is String:
				view[key] = _without_names(view[key], memory.people)
			elif view[key] is Array:
				var masked: Array[String] = []
				for text: String in view[key]:
					masked.append(_without_names(text, memory.people))
				view[key] = masked
	return view

func _without_names(text: String, people: Array) -> String:
	var result: String = text
	for person: String in people:
		if person.length() >= 3 and person.to_lower() != "player":
			result = result.replacen(person, "someone")
	return result

func _words(text: String) -> PackedStringArray:
	var expression := RegEx.new()
	expression.compile("[\\p{L}\\p{N}]{3,}")
	var words: PackedStringArray = []
	for found: RegExMatch in expression.search_all(text.to_lower()):
		var word: String = found.get_string()
		if not word in STOP_WORDS and not word in words:
			words.append(word)
	return words

func _overlap(words: PackedStringArray, text: String) -> float:
	if words.is_empty():
		return 0.0
	var candidates: PackedStringArray = _words(text)
	var count: int = 0
	for word: String in words:
		if word in candidates:
			count += 1
	return minf(float(count) / minf(float(words.size()), 3.0), 1.0)
