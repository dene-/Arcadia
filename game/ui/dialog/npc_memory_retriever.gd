class_name NpcMemoryRetriever
extends RefCounted

## Selection and recall are separate. Never send the archive to an inference service.
const MAX_RECALLS: int = 6
const STOP_WORDS: Array[String] = ["the", "and", "you", "your", "that", "this", "with",
	"have", "what", "when", "were", "was", "for", "are", "about", "remember", "player"]
## Word -> shared concept, so a paraphrase can match a memory that uses another word for it.
const TOPIC_ALIASES: Dictionary[String, String] = {
	"death": "death", "dead": "death", "die": "death", "died": "death", "dies": "death",
	"dying": "death", "kill": "death", "killed": "death", "body": "death", "corpse": "death",
	"funeral": "death", "burial": "death", "bury": "death", "grave": "death", "buried": "death",
	"fight": "fight", "fighting": "fight", "fought": "fight", "attack": "fight",
	"attacked": "fight", "hit": "fight", "assault": "fight", "assaulted": "fight", "hurt": "fight",
	"theft": "theft", "thief": "theft", "stole": "theft", "stolen": "theft", "steal": "theft",
}
## A memory this relevant to the cue pulls in the memories of the same incident.
const STRONG_MATCH: float = 0.5
## Fixed, non-cumulative boosts for associated memories; recall quality is unaffected.
const INCIDENT_LINK_BONUS: float = 0.15
const COMMITMENT_LINK_BONUS: float = 0.15

## Cues the caller derives from the resident's own context, never from a global registry.
class Links extends RefCounted:
	## Lower-case display name or unambiguous first name -> resident id.
	var entity_aliases: Dictionary[String, String] = {}
	## Evidence ids cited by the resident's open commitments.
	var commitment_evidence: Dictionary[String, bool] = {}

## Empty disables topic normalization (the lexical baseline).
var topic_aliases: Dictionary[String, String] = TOPIC_ALIASES
var _word_pattern: RegEx
var _separator_pattern: RegEx

## Links from the people the resident knows (`known_townspeople`, `family_members`: {id, name})
## and its `open_commitments` ({evidence_ids}) in a cognitive context.
static func links_for(current: Dictionary) -> Links:
	var links := Links.new()
	var people: Array = []
	for key: String in ["known_townspeople", "family_members"]:
		if current.get(key) is Array:
			people.append_array(current[key])
	links.entity_aliases = entity_aliases(people)
	var commitments: Variant = current.get("open_commitments", [])
	for item: Variant in commitments if commitments is Array else []:
		var evidence: Variant = item.get("evidence_ids") if item is Dictionary else null
		for id: Variant in evidence if evidence is Array else []:
			if id is String and not (id as String).is_empty():
				links.commitment_evidence[id] = true
	return links

## Display names and first names of `{id, name}` records. A name shared by two residents is
## dropped rather than guessed.
static func entity_aliases(people: Array) -> Dictionary[String, String]:
	var aliases: Dictionary[String, String] = {}
	var ambiguous: Dictionary[String, bool] = {}
	for person: Variant in people:
		if not person is Dictionary or not person.get("id") is String or not person.get("name") is String:
			continue
		var id: String = person["id"]
		var name: String = " ".join((person["name"] as String).to_lower().split(" ", false))
		if id.is_empty() or name.is_empty():
			continue
		for alias: String in [name, name.get_slice(" ", 0)]:
			if alias.length() < 3:
				continue
			if aliases.has(alias) and aliases[alias] != id:
				ambiguous[alias] = true
			aliases[alias] = id
	for alias: String in ambiguous:
		aliases.erase(alias)
	return aliases

func retrieve(memories: Array, message: String, current: Dictionary,
		cognition: NpcCognitionProfile, minute: float, links: Links = null) -> Array[Dictionary]:
	if links == null:
		links = Links.new()
	var cue: String = message + " " + str(current.get("location", ""))
	var words: PackedStringArray = _words(cue)
	var concepts: PackedStringArray = _concepts(words)
	var named: Array[String] = _named_entities(cue, links.entity_aliases)
	var sensory_words: PackedStringArray = _words(" ".join(current.get("sensory_cues", [])))
	var cues: Array[Dictionary] = []
	var strong_incidents: Dictionary[String, int] = {}
	for memory: Dictionary in memories:
		var relevance: float = _concept_overlap(concepts, memory.gist + " " + " ".join(memory.topics))
		var entities: float = _overlap(words, " ".join(memory.people + memory.places))
		var named_match: float = _entity_overlap(named, _memory_entities(memory, links.entity_aliases))
		entities = maxf(entities, named_match)
		var incident: String = _incident(memory)
		var strong: bool = not incident.is_empty() and (relevance >= STRONG_MATCH or named_match >= 1.0)
		if strong:
			strong_incidents[incident] = strong_incidents.get(incident, 0) + 1
		cues.append({"memory": memory, "relevance": relevance, "entities": entities,
			"incident": incident, "strong": strong})
	var candidates: Array[Dictionary] = []
	for entry: Dictionary in cues:
		var memory: Dictionary = entry.memory
		var relevance: float = entry.relevance
		var entities: float = entry.entities
		# Presence is a recall cue even when the player only says hello.
		for participant: String in current.get("participants", []):
			if participant in memory.people or (participant == "player"
				and memory.source == "observed_event" and memory.gist.contains("the player")):
				entities = 1.0
		var sensory: float = _overlap(sensory_words, " ".join(memory.sensory_cues))
		var prospective: bool = memory.type == "prospective" and not memory.completed
		var incident_linked: bool = not String(entry.incident).is_empty() \
			and strong_incidents.get(entry.incident, 0) > (1 if entry.strong else 0)
		var commitment_linked: bool = _cited(memory, links.commitment_evidence)
		if relevance == 0.0 and entities == 0.0 and sensory == 0.0 and not prospective \
				and not incident_linked and not commitment_linked:
			continue
		var age: float = NpcMemory.retention_age(memory, minute)
		var recency: float = exp(-float(age) / 100.0)
		var rehearsal: float = minf(float(memory.recall_count) / 10.0, 1.0)
		var score: float = relevance * 0.4 + entities * 0.2 + memory.importance * 0.15 \
			+ memory.emotional_intensity * 0.1 + recency * 0.1 + rehearsal * 0.05 \
			+ sensory * cognition.sensory_association * 0.3
		if prospective:
			score += 0.1
		if incident_linked:
			score += INCIDENT_LINK_BONUS
		if commitment_linked:
			score += COMMITMENT_LINK_BONUS
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
	if _word_pattern == null:
		_word_pattern = RegEx.create_from_string("[\\p{L}\\p{N}]{3,}")
	var words: PackedStringArray = []
	for found: RegExMatch in _word_pattern.search_all(text.to_lower()):
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

func _concepts(words: PackedStringArray) -> PackedStringArray:
	var concepts: PackedStringArray = []
	for word: String in words:
		var concept: String = topic_aliases.get(word, word)
		if not concept in concepts:
			concepts.append(concept)
	return concepts

func _concept_overlap(concepts: PackedStringArray, text: String) -> float:
	if concepts.is_empty():
		return 0.0
	var candidates: PackedStringArray = _concepts(_words(text))
	var count: int = 0
	for concept: String in concepts:
		if concept in candidates:
			count += 1
	return minf(float(count) / minf(float(concepts.size()), 3.0), 1.0)

## Resident ids named in `text`, matching whole words only.
func _named_entities(text: String, aliases: Dictionary[String, String]) -> Array[String]:
	var ids: Array[String] = []
	if aliases.is_empty():
		return ids
	if _separator_pattern == null:
		_separator_pattern = RegEx.create_from_string("[^\\p{L}\\p{N}]+")
	var padded: String = " " + _separator_pattern.sub(text.to_lower(), " ", true) + " "
	for alias: String in aliases:
		if padded.contains(" " + alias + " ") and not aliases[alias] in ids:
			ids.append(aliases[alias])
	return ids

## The memory's people as resident ids (names map through the aliases), plus residents its
## gist names.
func _memory_entities(memory: Dictionary, aliases: Dictionary[String, String]) -> Array[String]:
	var ids: Array[String] = []
	if aliases.is_empty():
		return ids
	for person: String in memory.people:
		var id: String = aliases.get(person.to_lower(), person)
		if not id in ids:
			ids.append(id)
	for id: String in _named_entities(memory.gist, aliases):
		if not id in ids:
			ids.append(id)
	return ids

static func _entity_overlap(named: Array[String], entities: Array[String]) -> float:
	if named.is_empty():
		return 0.0
	var count: int = 0
	for id: String in named:
		if id in entities:
			count += 1
	return minf(float(count) / minf(float(named.size()), 3.0), 1.0)

# Legacy memories carry no incident or evidence fields.
static func _incident(memory: Dictionary) -> String:
	var incident: Variant = memory.get("incident_id", "")
	return incident if incident is String else ""

static func _cited(memory: Dictionary, evidence: Dictionary[String, bool]) -> bool:
	if evidence.is_empty():
		return false
	var ids: Variant = memory.get("evidence_ids", [])
	for id: Variant in ids if ids is Array else []:
		if id is String and evidence.has(id):
			return true
	return false
