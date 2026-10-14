class_name NpcDecisionResult
extends RefCounted

## The settled outcome of one ticket. `judgments` is non-empty only for a SUCCESS judgment
## request and holds validated answers keyed by question id:
## {"type": "noul", "noul": p} | {"type": "choice", "choice", "confidence", "probabilities"}
## | {"type": "score", "score": 0..4, "confidence", "probabilities"}.
enum Outcome { SUCCESS, UNAVAILABLE, TIMEOUT, INVALID, CANCELLED, STALE }

var outcome: Outcome
var ticket: NpcDecisionTicket
var judgments: Dictionary = {}
## Parsed text-route response of a SUCCESS `run_text`; empty otherwise.
var body: Dictionary = {}

func _init(settled: Outcome, for_ticket: NpcDecisionTicket, validated: Dictionary = {},
		response: Dictionary = {}) -> void:
	outcome = settled
	ticket = for_ticket
	judgments = validated
	body = response

func is_success() -> bool:
	return outcome == Outcome.SUCCESS

# Accessors fail closed: a missing or differently typed answer reads as 0 / "".
func noul(question_id: String) -> float:
	return float(_answer(question_id, "noul").get("noul", 0.0))

func choice(question_id: String) -> String:
	return str(_answer(question_id, "choice").get("choice", ""))

func score(question_id: String) -> float:
	return float(_answer(question_id, "score").get("score", 0.0))

func confidence(question_id: String) -> float:
	var answer: Dictionary = judgments.get(question_id, {})
	return float(answer.get("confidence", 0.0))

func _answer(question_id: String, type: String) -> Dictionary:
	var answer: Dictionary = judgments.get(question_id, {})
	return answer if answer.get("type") == type else {}
