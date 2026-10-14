class_name NpcReportSpeech
extends RefCounted

## Optional spoken lines for town reports and guard warnings. The structured meaning of the
## event (observation, alert, justice report) is committed by the caller before `say`; this only
## adds words. A line is requested from `/v2/dialogue/say` for an audible speaker and shown if it
## arrives in time. When a line is necessary the caller supplies a short offline `fallback`, shown
## if generation failed. Words are published (WorldEvent.speech) only when the bubble actually
## displayed them, so a failed or discarded generation never counts as spoken.

enum Result {
	## The generated line was shown.
	DISPLAYED,
	## Generation failed and the offline fallback was shown.
	FALLBACK,
	## No player could hear the speaker: nothing was requested or shown.
	OFFSCREEN,
	## Nothing was shown: the speaker is gone, busy, or no line existed.
	UNSPOKEN,
	## The request was cancelled (owner left the world).
	CANCELLED,
}

const PATH: String = "/v2/dialogue/say"
const INTENTS: Array[String] = ["remark", "warn", "call_for_help", "protest", "grieve", "share",
	"reply", "small_talk", "report", "acknowledge", "request_help", "decline", "farewell"]
## A generated line arriving later than this is dropped: the moment has passed.
const WAIT_MSEC: int = 4000
const MAX_LENGTH: int = 160
## Longest `event.text` the say route accepts.
const MAX_EVENT_TEXT: int = 500

var decisions: NpcDecisionService

## Speaks one line in `intent`. `event_text` states what the speaker perceived (never a completed
## action it has not done). An empty `fallback` makes the line purely optional.
func say(speaker: BaseNpc, intent: String, event_text: String, sense: String,
		fallback: String = "", listener: BaseNpc = null, player_involved: bool = false) -> Result:
	if not intent in INTENTS or not _present(speaker):
		return Result.UNSPOKEN
	if not audible(speaker):
		return Result.OFFSCREEN
	var space: StringName = speaker.world_space
	var line: String = ""
	var profile: NpcProfile = speaker.get_npc_profile()
	if decisions != null and profile != null and not String(profile.npc_id).is_empty():
		var ticket := NpcDecisionTicket.create(String(profile.npc_id), NpcDecisionTicket.UTTERANCE,
			NpcDecisionTicket.Urgency.SAFETY)
		ticket.created_minute = int(speaker.life_context.get("world_minute", 0))
		ticket.deadline_tick_msec = int(decisions.clock.call()) + WAIT_MSEC
		var result: NpcDecisionResult = await decisions.run_text(ticket, PATH,
			_payload(speaker, ticket, intent, event_text, sense, listener, player_involved))
		if result.outcome == NpcDecisionResult.Outcome.CANCELLED:
			return Result.CANCELLED
		line = spoken_line(result)
	if not _present(speaker) or speaker.world_space != space:
		return Result.UNSPOKEN
	if not audible(speaker):
		return Result.OFFSCREEN
	var text: String = line if not line.is_empty() else fallback
	if text.is_empty() or not speaker.show_spoken_reaction(text):
		return Result.UNSPOKEN
	return Result.DISPLAYED if not line.is_empty() else Result.FALLBACK

## True while a player in the speaker's space is within the speaker's audible range.
func audible(speaker: BaseNpc) -> bool:
	for player: Node in speaker.get_tree().get_nodes_in_group(&"players"):
		if player is BasePlayer and player.world_space == speaker.world_space \
				and speaker.global_position.distance_to(player.global_position) \
					<= speaker.npc_data.hearing_radius:
			return true
	return false

static func _present(speaker: BaseNpc) -> bool:
	return is_instance_valid(speaker) and speaker.is_inside_tree() and speaker.health > 0

## The validated line of a settled `/v2/dialogue/say` request, or "" when it failed or is unusable.
static func spoken_line(result: NpcDecisionResult) -> String:
	if not result.is_success() or int(result.body.get("protocol_version", 0)) != 2 \
			or result.body.get("request_id") != result.ticket.request_id \
			or not result.body.get("response") is String:
		return ""
	var text: String = (result.body.response as String).strip_edges()
	return text if text.length() <= MAX_LENGTH else ""

static func _payload(speaker: BaseNpc, ticket: NpcDecisionTicket, intent: String,
		event_text: String, sense: String, listener: BaseNpc, player_involved: bool) -> Dictionary:
	var id: String = ticket.npc_id
	var payload: Dictionary = {"protocol_version": ticket.protocol_version,
		"prompt_version": ticket.prompt_version, "request_id": ticket.request_id, "npc_id": id,
		"npc": {"id": id, "profile": speaker.get_backend_profile()},
		"intent": intent, "event": {"text": event_text, "sense": sense, "player_involved": player_involved}}
	var heard: NpcProfile = listener.get_npc_profile() if is_instance_valid(listener) else null
	var participants: Array[String] = []
	if heard != null:
		payload["listener"] = {"id": String(heard.npc_id), "name": heard.profile_name}
		participants.append(String(heard.npc_id))
	payload["context"] = speaker.get_cognitive_context(NpcCognitiveContext.SOCIAL, participants)
	return payload
