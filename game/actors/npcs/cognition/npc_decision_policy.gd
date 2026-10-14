class_name NpcDecisionPolicy
extends RefCounted

## The only mapping from validated v2 judgments (NpcDecisionResult) to domain decisions. Noul gates
## compare the probability with a NpcBehaviorTuning threshold; choice and score answers below
## `min_confidence` take their neutral fallback. A result that is not SUCCESS maps to the fully
## neutral record, so callers never need a separate failure branch for effects.
## Disposition deltas are per subject and dimension, at most NpcIncidentBudget.MAX_CHANGE in size;
## the owner still passes them through its NpcIncidentBudget.

const UNCHANGED: String = "UNCHANGED"
const _SIGNS: Dictionary[String, float] = {"NEGATIVE": -1.0, UNCHANGED: 0.0, "POSITIVE": 1.0}
const _MAX_SCORE: float = 4.0

class Appraisal extends RefCounted:
	var immediate_danger: bool = false
	var remember: bool = false
	## 0..1 retention weight.
	var importance: float = 0.0
	## Emotion name (fear, anger, grief, relief) -> intensity 0..1.
	var emotions: Dictionary[String, float] = {}
	## Subject id -> {dimension: signed delta}; only non-zero deltas are present.
	var dispositions: Dictionary[String, Dictionary] = {}

class GoalChoice extends RefCounted:
	## Empty when no candidate is suitable enough: keep the current goal.
	var candidate_id: String = ""
	## 0..4 suitability of the chosen candidate.
	var suitability: float = 0.0
	var duration_minutes: float = 0.0
	## True when the judgment itself rated the chosen candidate suitable; false when only the
	## resident's own priorities (a commitment or pressing need) made it eligible.
	var endorsed: bool = false
	## Candidate id -> {suitability, need, obligation, concern, commitment, personality,
	## switching, total, eligible}: every weighted term of the comparison, for traces.
	var scores: Dictionary = {}

## The resident's own reasons for each candidate, combined with the judgment by `goal_choice`.
class GoalFrame extends RefCounted:
	## Candidate id -> {need, obligation, concern, commitment: 0..1; personality: -1..1}.
	## Missing components count as zero.
	var components: Dictionary = {}
	## Candidate the resident is pursuing now (empty when none of the candidates).
	var incumbent: String = ""
	## Game minutes the incumbent has run.
	var incumbent_minutes: float = INF
	## Urgent danger: inertia (commitment minimum and switch advantage) does not apply.
	var urgent: bool = false
	## Seed of the tie-break between equally scored candidates (from the saved decision sequence).
	var tie_seed: int = 0

const COMPONENTS: Array[String] = ["need", "obligation", "concern", "commitment", "personality"]
## Totals closer than this are a tie, broken by the frame's seed.
const TIE_MARGIN: float = 0.005

class Social extends RefCounted:
	var engage: bool = false
	## SMALL_TALK when the topic answer is not confident.
	var topic: String = NpcDecisionService.SMALL_TALK
	var tone: String = ""

class Listening extends RefCounted:
	var believe: bool = false
	var remember: bool = false
	var importance: float = 0.0
	var dispositions: Dictionary[String, Dictionary] = {}

class Utterance extends RefCounted:
	var speak: bool = false
	## Empty unless `speak`.
	var intent: String = ""

static func appraisal(result: NpcDecisionResult, tuning: NpcBehaviorTuning) -> Appraisal:
	var appraised := Appraisal.new()
	if not _answered(result, NpcDecisionTicket.APPRAISE):
		return appraised
	appraised.immediate_danger = result.noul("immediate_danger") >= tuning.danger_threshold
	appraised.remember = result.noul("remember") >= tuning.remember_threshold
	appraised.importance = _importance(result)
	for emotion: String in NpcDecisionService.EMOTIONS:
		appraised.emotions[emotion] = _score(result, emotion, tuning) / _MAX_SCORE
	appraised.dispositions = _dispositions(result, _subjects(result), tuning)
	return appraised

## Without a frame: the most suitable confident candidate at or above `goal_min_suitability`;
## ties keep the ticket's candidate order.
## With a frame, every eligible candidate (confidently suitable, committed to, or relieving a
## pressing need) scores suitability / 4 plus the weighted components and the incumbent's switch
## advantage; an incumbent younger than the commitment minimum is kept. Urgent danger bypasses
## both. Near-ties are broken by the frame's seed. Duration falls back to ORDINARY when its
## answer is not confident.
static func goal_choice(result: NpcDecisionResult, tuning: NpcBehaviorTuning,
		frame: GoalFrame = null) -> GoalChoice:
	var choice := GoalChoice.new()
	if frame == null:
		if not _answered(result, NpcDecisionTicket.SELECT_GOAL):
			return choice
		for candidate: String in result.ticket.candidate_ids:
			var suitability: float = _score(result, "suitability:" + candidate, tuning)
			if suitability >= tuning.goal_min_suitability and suitability > choice.suitability:
				choice.candidate_id = candidate
				choice.suitability = suitability
				choice.endorsed = true
	else:
		_choose_in_frame(choice, result, tuning, frame)
	if not choice.candidate_id.is_empty():
		var duration: String = "ORDINARY"
		if _answered(result, NpcDecisionTicket.SELECT_GOAL):
			duration = _choice(result, "duration:" + choice.candidate_id, "ORDINARY", tuning)
		choice.duration_minutes = {"BRIEF": tuning.brief_goal_minutes,
			"ORDINARY": tuning.ordinary_goal_minutes,
			"EXTENDED": tuning.extended_goal_minutes}[duration]
	return choice

static func _choose_in_frame(choice: GoalChoice, result: NpcDecisionResult,
		tuning: NpcBehaviorTuning, frame: GoalFrame) -> void:
	var answered: bool = _answered(result, NpcDecisionTicket.SELECT_GOAL)
	var candidates: Array[String] = []
	if result != null and result.ticket != null and not result.ticket.candidate_ids.is_empty():
		candidates.assign(result.ticket.candidate_ids)
	else:
		candidates.assign(frame.components.keys())
	var weights: Dictionary = {"need": tuning.goal_need_weight,
		"obligation": tuning.goal_obligation_weight, "concern": tuning.goal_concern_weight,
		"commitment": tuning.goal_commitment_weight, "personality": tuning.goal_personality_weight}
	var best: float = -INF
	for candidate: String in candidates:
		var parts: Dictionary = frame.components.get(candidate, {})
		var suitability: float = _score(result, "suitability:" + candidate, tuning) if answered else 0.0
		var entry: Dictionary = {"suitability": suitability}
		var total: float = suitability / _MAX_SCORE
		for component: String in COMPONENTS:
			var value: float = float(parts.get(component, 0.0))
			entry[component] = value
			total += float(weights[component]) * value
		entry["switching"] = tuning.switch_advantage \
			if candidate == frame.incumbent and not frame.urgent else 0.0
		total += float(entry["switching"])
		entry["total"] = total
		entry["eligible"] = suitability >= tuning.goal_min_suitability \
			or float(entry["commitment"]) > 0.0 or float(entry["need"]) >= tuning.need_pressing
		choice.scores[candidate] = entry
		if entry["eligible"]:
			best = maxf(best, total)
	# Inertia: a goal younger than the commitment minimum is kept while it is still eligible.
	if not frame.urgent and choice.scores.has(frame.incumbent) \
			and choice.scores[frame.incumbent]["eligible"] \
			and frame.incumbent_minutes < tuning.commitment_minimum_minutes:
		choice.candidate_id = frame.incumbent
	else:
		var leaders: Array[String] = []
		for candidate: String in candidates:
			if choice.scores[candidate]["eligible"] \
					and float(choice.scores[candidate]["total"]) >= best - TIE_MARGIN:
				leaders.append(candidate)
		if leaders.is_empty():
			return
		var random := RandomNumberGenerator.new()
		random.seed = frame.tie_seed
		choice.candidate_id = leaders[0] if leaders.size() == 1 \
			else leaders[random.randi_range(0, leaders.size() - 1)]
	choice.suitability = float(choice.scores[choice.candidate_id]["suitability"])
	choice.endorsed = choice.suitability >= tuning.goal_min_suitability

## `default_tone` is used when the tone answer is not confident.
static func social(result: NpcDecisionResult, default_tone: String,
		tuning: NpcBehaviorTuning) -> Social:
	var decided := Social.new()
	decided.tone = default_tone
	if not _answered(result, NpcDecisionTicket.SOCIAL):
		return decided
	decided.engage = result.noul("engage") >= tuning.engage_threshold
	decided.topic = _choice(result, "topic", NpcDecisionService.SMALL_TALK, tuning)
	decided.tone = _choice(result, "tone", default_tone, tuning)
	return decided

## Dispositions toward the account's subjects apply only when it is believed. The messenger
## (`messenger_id`, the speaker who passed the account on) is never blamed for its content: they
## change only through the answers about the messenger themself, believed or not.
static func listening(result: NpcDecisionResult, messenger_id: String,
		tuning: NpcBehaviorTuning) -> Listening:
	var heard := Listening.new()
	if not _answered(result, NpcDecisionTicket.LISTEN):
		return heard
	heard.believe = result.noul("believe_account") >= tuning.belief_threshold
	heard.remember = result.noul("remember") >= tuning.remember_threshold
	heard.importance = _importance(result)
	var subjects: Array[String] = []
	for subject: String in _subjects(result):
		if subject == messenger_id or heard.believe:
			subjects.append(subject)
	heard.dispositions = _dispositions(result, subjects, tuning)
	return heard

## Speaks only with a confident intent the caller still permits.
static func utterance(result: NpcDecisionResult, permitted_intents: Array[String],
		tuning: NpcBehaviorTuning) -> Utterance:
	var decided := Utterance.new()
	if not _answered(result, NpcDecisionTicket.UTTERANCE) \
			or result.noul("speak") < tuning.speak_threshold:
		return decided
	var intent: String = _choice(result, "intent", "", tuning)
	if intent in permitted_intents:
		decided.speak = true
		decided.intent = intent
	return decided

static func _answered(result: NpcDecisionResult, kind: StringName) -> bool:
	return result != null and result.is_success() and result.ticket.kind == kind

# Importance only orders retention, so it uses the expected score without a confidence gate.
static func _importance(result: NpcDecisionResult) -> float:
	return clampf(result.score("importance") / _MAX_SCORE, 0.0, 1.0)

static func _score(result: NpcDecisionResult, id: String, tuning: NpcBehaviorTuning) -> float:
	return result.score(id) if result.confidence(id) >= tuning.min_confidence else 0.0

static func _choice(result: NpcDecisionResult, id: String, fallback: String,
		tuning: NpcBehaviorTuning) -> String:
	return result.choice(id) if result.confidence(id) >= tuning.min_confidence else fallback

# Subjects as answered: question ids are disposition:<subject>:<dimension>:direction.
static func _subjects(result: NpcDecisionResult) -> Array[String]:
	var subjects: Array[String] = []
	for id: String in result.judgments:
		var parts: PackedStringArray = id.split(":")
		if parts.size() == 4 and parts[0] == "disposition" and parts[3] == "direction" \
				and not parts[1] in subjects:
			subjects.append(parts[1])
	return subjects

static func _dispositions(result: NpcDecisionResult, subjects: Array[String],
		tuning: NpcBehaviorTuning) -> Dictionary[String, Dictionary]:
	var deltas: Dictionary[String, Dictionary] = {}
	for subject: String in subjects:
		var changes: Dictionary = {}
		for dimension: String in NpcDecisionService.DIMENSIONS:
			var prefix: String = "disposition:%s:%s:" % [subject, dimension]
			var sign: float = _SIGNS[_choice(result, prefix + "direction", UNCHANGED, tuning)]
			var delta: float = sign * _score(result, prefix + "magnitude", tuning) / _MAX_SCORE \
				* NpcIncidentBudget.MAX_CHANGE
			if delta != 0.0:
				changes[dimension] = delta
		if not changes.is_empty():
			deltas[subject] = changes
	return deltas
