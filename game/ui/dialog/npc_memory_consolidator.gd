class_name NpcMemoryConsolidator
extends RefCounted

## Conservative archive consolidation. Repetitive low-importance episodes of one incident that
## share their subject people, source, modality, event kind and hearsay chain become one memory
## resting on all of their evidence. Independent accounts never merge: spoken and hearsay
## memories also have to share their origin. A first-hand episode's origin is one perceived
## event, so first-hand episodes of one incident merge across origins and keep the common origin
## only. Deterministic: the result depends only on the archive order and the inputs.

## Episodes at least this important are consequential and kept as they are.
const PROTECTED_IMPORTANCE: float = 0.6
## Episodes younger than this still belong to the working window.
const MIN_AGE_MINUTES: float = 60.0
const DEATH_KINDS: Array[String] = ["actor_died", "body_found", "body_reported", "body_buried"]

## Merges eligible groups of `memories` in place and returns how many records were removed.
## `protected_refs` holds evidence and origin ids that open commitments, running duties or
## contested beliefs rest on; an episode citing any of them is never merged.
static func consolidate(memories: Array, protected_refs: Dictionary, minute: float) -> int:
	var groups: Dictionary = {}
	var order: Array[String] = []
	for memory: Dictionary in memories:
		if not _is_eligible(memory, protected_refs, minute):
			continue
		var key: String = _group_key(memory)
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		groups[key].append(memory)
	var replaced: Dictionary = {}
	var merged_ids: Dictionary = {}
	for key: String in order:
		for chunk: Array in _chunks(groups[key]):
			if chunk.size() < 2:
				continue
			var merged: Dictionary = _merge(chunk)
			replaced[(chunk[0] as Dictionary).id] = merged
			for memory: Dictionary in chunk.slice(1):
				merged_ids[memory.id] = true
	if merged_ids.is_empty():
		return 0
	var result: Array = []
	for memory: Dictionary in memories:
		if merged_ids.has(memory.id):
			continue
		result.append(replaced.get(memory.id, memory))
	var removed: int = memories.size() - result.size()
	memories.clear()
	memories.append_array(result)
	return removed

static func _is_eligible(memory: Dictionary, protected_refs: Dictionary, minute: float) -> bool:
	if memory.type != "episodic" or memory.source == "authored" or memory.get("completed", false) \
			or float(memory.importance) >= PROTECTED_IMPORTANCE \
			or String(memory.get("incident_id", "")).is_empty() \
			or String(memory.get("observation_kind", "")) in DEATH_KINDS \
			or memory.get("date_known") != true \
			or minute - float(memory.get("created_minute", minute)) < MIN_AGE_MINUTES:
		return false
	if protected_refs.has(memory.get("origin_id", "")):
		return false
	for evidence_id: Variant in memory.get("evidence_ids", []):
		if protected_refs.has(evidence_id):
			return false
	return true

static func _group_key(memory: Dictionary) -> String:
	var people: Array = (memory.people as Array).duplicate()
	people.sort()
	var source: String = memory.source
	var modality: String = memory.get("modality", "unknown")
	var account: bool = source == "hearsay" or modality == "speech"
	return JSON.stringify([source, modality, memory.get("observation_kind", ""),
		memory.incident_id, people, memory.get("chain", []),
		memory.get("origin_id", "") if account else ""])

# Splits a group so no merged memory exceeds the evidence id bound.
static func _chunks(group: Array) -> Array[Array]:
	var chunks: Array[Array] = []
	var current: Array = []
	var evidence: Dictionary = {}
	for memory: Dictionary in group:
		var added: Dictionary = evidence.duplicate()
		for evidence_id: Variant in memory.get("evidence_ids", []):
			added[evidence_id] = true
		if not current.is_empty() and added.size() > NpcMemory.MAX_EVIDENCE_IDS:
			chunks.append(current)
			current = []
			added.clear()
			for evidence_id: Variant in memory.get("evidence_ids", []):
				added[evidence_id] = true
		current.append(memory)
		evidence = added
	if not current.is_empty():
		chunks.append(current)
	return chunks

# The earliest episode keeps its id and wording; certainty is the weakest of the group.
static func _merge(chunk: Array) -> Dictionary:
	var merged: Dictionary = (chunk[0] as Dictionary).duplicate(true)
	var evidence_ids: Array = merged.get("evidence_ids", []).duplicate()
	for memory: Dictionary in chunk.slice(1):
		merged.confidence = minf(float(merged.confidence), float(memory.confidence))
		for key: String in ["importance", "emotional_intensity", "vividness"]:
			merged[key] = maxf(float(merged[key]), float(memory[key]))
		merged.recall_count = int(merged.recall_count) + int(memory.recall_count)
		merged.last_recalled_turn = maxi(int(merged.last_recalled_turn), int(memory.last_recalled_turn))
		if memory.has("last_recalled_minute"):
			merged.last_recalled_minute = maxf(float(merged.get("last_recalled_minute", 0.0)),
				float(memory.last_recalled_minute))
		merged.created_turn = mini(int(merged.created_turn), int(memory.created_turn))
		merged.created_minute = minf(float(merged.created_minute), float(memory.created_minute))
		if merged.has("observed_minute") or memory.has("observed_minute"):
			merged.observed_minute = _earliest_known(float(merged.get("observed_minute",
				NpcMemory.UNKNOWN_MINUTE)), float(memory.get("observed_minute", NpcMemory.UNKNOWN_MINUTE)))
		if merged.get("origin_id", "") != memory.get("origin_id", ""):
			merged.origin_id = ""
		for key: String in NpcMemory.TEXT_LISTS:
			for entry: Variant in memory[key]:
				if not entry in merged[key] and (merged[key] as Array).size() < 8:
					merged[key].append(entry)
		for evidence_id: Variant in memory.get("evidence_ids", []):
			if not evidence_id in evidence_ids:
				evidence_ids.append(evidence_id)
	if merged.has("evidence_ids") or not evidence_ids.is_empty():
		merged.evidence_ids = evidence_ids
	return merged

static func _earliest_known(left: float, right: float) -> float:
	if left < 0.0:
		return right
	if right < 0.0:
		return left
	return minf(left, right)
