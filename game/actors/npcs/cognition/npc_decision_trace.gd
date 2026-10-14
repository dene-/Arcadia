class_name NpcDecisionTrace
extends RefCounted

## One resident's recent reasoning for the inspector: the last CAPACITY entries of what it chose
## and why. Reasons are policy codes (`reason`, `outcome`), never model text. Not saved.
##
## Every entry has `minute` (world minute) and `kind`; per kind it carries:
## - goal: reason (selection service code), outcome, request_id, selected (candidate id),
##   duration, scores (NpcDecisionPolicy.GoalChoice.scores: candidate id -> score components;
##   every id other than `selected` was rejected), commitment_id.
## - transition: task_id, task_kind, from, to, reason (NpcTaskController transition).
## - request: request_id, request_kind, read_versions, latency_ms, outcome.
## - effect: reason, plus the receipts it applied (commitment_id, task_id, evidence ids, ...).
## - save_failure: reason (save error code).

const CAPACITY: int = 64
const GOAL: String = "goal"
const TRANSITION: String = "transition"
const REQUEST: String = "request"
const EFFECT: String = "effect"
const SAVE_FAILURE: String = "save_failure"
const KINDS: Array[String] = [GOAL, TRANSITION, REQUEST, EFFECT, SAVE_FAILURE]
## Fields that must hold a code when present.
const CODE_FIELDS: Array[String] = ["reason", "outcome"]
const MAX_CODE_LENGTH: int = 120

static var _code_pattern: RegEx

## Bumped by every recorded entry, so readers can cache derived views.
var version: int = 0
var _entries: Array[Dictionary] = []

## True for a policy code: lower-case letters, digits and `_ : . -`, at most MAX_CODE_LENGTH.
static func is_code(value: Variant) -> bool:
	if _code_pattern == null:
		_code_pattern = RegEx.create_from_string("^[a-z0-9_:.\\-]+$")
	return (value is String or value is StringName) and String(value).length() <= MAX_CODE_LENGTH \
		and _code_pattern.search(String(value)) != null

## `text` as a code: lower-cased, with spaces as underscores.
static func code(text: String) -> String:
	return text.strip_edges().to_lower().replace(" ", "_")

## Appends an entry of `kind` at `minute`; nothing is recorded (false) for an unknown kind, a
## non-finite minute, a `minute`/`kind` field or a reason/outcome that is not a code.
func record(minute: float, kind: String, fields: Dictionary) -> bool:
	if not kind in KINDS or not is_finite(minute) or fields.has("minute") or fields.has("kind"):
		return false
	for key: String in CODE_FIELDS:
		if fields.has(key) and not is_code(fields[key]):
			return false
	var entry: Dictionary = fields.duplicate(true)
	entry.minute = minute
	entry.kind = kind
	_entries.append(entry)
	while _entries.size() > CAPACITY:
		_entries.pop_front()
	version += 1
	return true

## Oldest first.
func entries() -> Array[Dictionary]:
	return _entries.duplicate(true)

## The newest entry of `kind`, or {}.
func latest(kind: String) -> Dictionary:
	for index: int in range(_entries.size() - 1, -1, -1):
		if _entries[index].kind == kind:
			return _entries[index].duplicate(true)
	return {}
