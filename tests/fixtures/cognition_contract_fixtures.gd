extends RefCounted

## Reads the shared v2 cognition fixtures in tests/fixtures/cognition_contract/ (the server tests
## read the same files) and turns their requests into tickets and payloads for NpcDecisionService.
const DIRECTORY: String = "res://tests/fixtures/cognition_contract/"

static func manifest() -> Dictionary:
	return _json("manifest.json")

static func kinds() -> Array[String]:
	var names: Array[String] = []
	names.assign(manifest().kinds.keys())
	return names

static func route(kind: String) -> String:
	return manifest().kinds[kind].route

static func request(kind: String) -> Dictionary:
	return _json(manifest().kinds[kind].request)

static func response(kind: String) -> Dictionary:
	return _json(manifest().kinds[kind].response)

## Each invalid case as {"file", "kind", "response"}.
static func invalid_cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	for entry: Dictionary in manifest().invalid:
		cases.append({"file": entry.file, "kind": entry.kind,
			"response": _json(entry.file).response})
	return cases

## The ticket a caller would have built for `envelope` (a fixture request).
static func ticket(envelope: Dictionary) -> NpcDecisionTicket:
	var source: Dictionary = envelope.ticket
	var built := NpcDecisionTicket.new()
	built.request_id = envelope.request_id
	built.npc_id = envelope.npc_id
	built.kind = StringName(envelope.kind)
	built.task_id = source.task_id
	built.task_generation = int(source.task_generation)
	built.created_minute = int(source.created_minute)
	for key: String in source.read_versions:
		var value: Variant = source.read_versions[key]
		built.read_versions[key] = int(value) if value is float else value
	built.evidence_ids.assign(source.evidence_ids)
	built.candidate_ids.assign(source.candidate_ids)
	built.context_hash = source.context_hash
	return built

## The `evaluate` payload of a fixture request: everything outside the envelope header and ticket.
static func payload(envelope: Dictionary) -> Dictionary:
	var built: Dictionary = envelope.duplicate(true)
	for key: String in ["protocol_version", "prompt_version", "request_id", "npc_id", "kind", "ticket"]:
		built.erase(key)
	return built

static func _json(file: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(DIRECTORY + file)
	var parsed: Variant = JSON.parse_string(text)
	assert(parsed is Dictionary, "Unreadable cognition fixture %s" % file)
	return parsed
