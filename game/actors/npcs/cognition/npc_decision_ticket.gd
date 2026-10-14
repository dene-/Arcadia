class_name NpcDecisionTicket
extends RefCounted

## Identifies one decision request: who asks, for which kind, and which state it read. The owner
## compares these fields with live state before applying the result.
const PROTOCOL_VERSION: int = 2
## Matches tests/fixtures/cognition_contract/manifest.json and the server PROMPT_VERSION.
const PROMPT_VERSION: String = "cognition-1"

const APPRAISE: StringName = &"appraise"
const SELECT_GOAL: StringName = &"select_goal"
const SOCIAL: StringName = &"social"
const LISTEN: StringName = &"listen"
const UTTERANCE: StringName = &"utterance"
const KINDS: Array[StringName] = [APPRAISE, SELECT_GOAL, SOCIAL, LISTEN, UTTERANCE]

## Scheduling class: lower runs first; waiting background work ages toward INTERACTIVE.
enum Urgency { INTERACTIVE, SAFETY, BACKGROUND }

static var _counter: int = 0

var request_id: String = ""
var npc_id: String = ""
var kind: StringName = &""
var urgency: Urgency = Urgency.BACKGROUND
var task_id: String = ""
var task_generation: int = 0
var created_minute: int = 0
## Monotonic Time.get_ticks_msec() after which the result is useless; 0 means no caller deadline.
var deadline_tick_msec: int = 0
## Versions of exactly the state parts the request read (knowledge, relationships, task, ...).
var read_versions: Dictionary = {}
var evidence_ids: Array[String] = []
var candidate_ids: Array[String] = []
var context_hash: String = ""
var protocol_version: int = PROTOCOL_VERSION
var prompt_version: String = PROMPT_VERSION

## A ticket with a process-unique request id.
static func create(for_npc: String, for_kind: StringName,
		with_urgency: Urgency = Urgency.BACKGROUND) -> NpcDecisionTicket:
	_counter += 1
	var ticket := NpcDecisionTicket.new()
	ticket.request_id = "req:%s:%d" % [for_kind, _counter]
	ticket.npc_id = for_npc
	ticket.kind = for_kind
	ticket.urgency = with_urgency
	return ticket

## The envelope `ticket` object of the v2 protocol.
func envelope_ticket() -> Dictionary:
	return {"task_id": task_id, "task_generation": task_generation,
		"created_minute": created_minute, "read_versions": read_versions.duplicate(true),
		"evidence_ids": evidence_ids.duplicate(), "candidate_ids": candidate_ids.duplicate(),
		"context_hash": context_hash}
