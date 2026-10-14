// v2 dialogue contract: request validation and output grounding for /v2/dialogue/say and
// /v2/dialogue/chat. The game decides whether and why an NPC speaks; the server words the line,
// rejects what the supplied context cannot support, and never computes relationship changes.
import {
  ContractError,
  PROMPT_VERSION,
  PROTOCOL_VERSION,
  invalid,
  isId,
  isObject,
} from "./cognition-contract.js";
import { SAY_LIMITS, SPEECH_INTENTS, parseDialogue, spokenText } from "./dialogue.js";
import { QUESTIONS, RELATIONSHIP_SCALES } from "./npc-decisions.js";

export const DIALOGUE_LIMITS = Object.freeze({
  context_bytes: 16 * 1024,
  message: 2000,
  turns: 12,
  turn_text: 6000,
  memories: 8,
  events: 8,
  event_text: 500,
  topic_text: 500,
  topic_bytes: 2048,
  name: 100,
});
export const SENSES = Object.freeze(["sight", "hearing", "touch"]);
// Intents that have nothing to say without the account they pass on or answer.
const NEEDS_TOPIC = new Set(["share", "reply"]);

const mismatch = () => new ContractError(409, "protocol_mismatch");
const invalidOutput = (code) => new ContractError(502, "invalid_provider_payload", code);
const text = (value, maximum) => typeof value === "string" && value.trim() !== "" && value.length <= maximum;

// Version checks come first so a caller on another schema is told so, not given a field error.
function header(body) {
  if (!isObject(body)) throw invalid("invalid_envelope");
  if (body.protocol_version !== PROTOCOL_VERSION || body.prompt_version !== PROMPT_VERSION) throw mismatch();
  if (!isId(body.request_id)) throw invalid("invalid_request_id");
  if (!isId(body.npc_id)) throw invalid("invalid_npc_id");
  if (!isObject(body.npc) || body.npc.id !== body.npc_id || !isObject(body.npc.profile)) throw invalid("invalid_npc");
  if (!isObject(body.context)) throw invalid("invalid_context");
  if (Buffer.byteLength(JSON.stringify(body.context)) > DIALOGUE_LIMITS.context_bytes) throw invalid("context_too_large");
  return {
    protocol_version: PROTOCOL_VERSION,
    prompt_version: PROMPT_VERSION,
    request_id: body.request_id,
    npc_id: body.npc_id,
    npc: { id: body.npc.id, profile: body.npc.profile },
    context: body.context,
  };
}

// Fresh perceived events live in the consumer context; they are the evidence for `observed_event` memories.
function recentEvents(context) {
  const events = context.recent_events ?? [];
  if (!Array.isArray(events) || events.length > DIALOGUE_LIMITS.events
    || !events.every((event) => text(event, DIALOGUE_LIMITS.event_text))) throw invalid("invalid_events");
  return events;
}

export function validateSay(body) {
  const request = header(body);
  if (!SPEECH_INTENTS.includes(body.intent)) throw invalid("invalid_intent");
  request.intent = body.intent;
  if (body.event !== undefined) {
    const event = body.event;
    if (!isObject(event) || !text(event.text, DIALOGUE_LIMITS.event_text) || !SENSES.includes(event.sense)
      || typeof event.player_involved !== "boolean") throw invalid("invalid_event");
    request.event = { text: event.text, sense: event.sense, player_involved: event.player_involved };
  }
  if (body.topic !== undefined) {
    const topic = body.topic;
    const valid = typeof topic === "string"
      ? text(topic, DIALOGUE_LIMITS.topic_text)
      : isObject(topic) && Buffer.byteLength(JSON.stringify(topic)) <= DIALOGUE_LIMITS.topic_bytes;
    if (!valid) throw invalid("invalid_topic");
    request.topic = topic;
  }
  if (NEEDS_TOPIC.has(request.intent) && request.topic === undefined) throw invalid("missing_topic");
  if (body.listener !== undefined) {
    if (!isObject(body.listener) || !isId(body.listener.id) || !text(body.listener.name, DIALOGUE_LIMITS.name))
      throw invalid("invalid_listener");
    request.listener = { id: body.listener.id, name: body.listener.name };
  }
  return request;
}

export function validateChat(body) {
  const request = header(body);
  const { player } = body;
  if (!isObject(player) || !text(player.message, DIALOGUE_LIMITS.message) || !isObject(player.identity))
    throw invalid("invalid_player");
  request.player = { message: player.message, identity: player.identity };
  const turns = body.recent_dialogue;
  if (!Array.isArray(turns) || turns.length > DIALOGUE_LIMITS.turns
    || !turns.every((turn) => isObject(turn) && ["player", "npc"].includes(turn.speaker)
      && typeof turn.text === "string" && turn.text.length <= DIALOGUE_LIMITS.turn_text))
    throw invalid("invalid_history");
  request.recent_dialogue = turns.map(({ speaker, text: line }) => ({ speaker, text: line }));
  const memories = body.memories;
  if (!Array.isArray(memories) || memories.length > DIALOGUE_LIMITS.memories
    || !memories.every((memory) => isObject(memory) && text(memory.id, 100)))
    throw invalid("invalid_memories");
  if (new Set(memories.map((memory) => memory.id)).size !== memories.length) throw invalid("invalid_memories");
  request.memories = memories;
  recentEvents(request.context);
  return request;
}

// The shape the existing question set, dialogue prompt and memory validators were written for.
// `memories` is the candidate list for judgments and the recalled subset for generation.
export function dialogueView(request, memories = request.memories) {
  return {
    npc: request.npc,
    player: request.player,
    context: {
      current: { ...request.context, recent_events: recentEvents(request.context) },
      recent_dialogue: request.recent_dialogue,
      memories,
    },
  };
}

export function chatJudgmentState(request) {
  return { ...dialogueView(request), relationship_scales: RELATIONSHIP_SCALES };
}

// The eight gates and five disposition directions, as typed judgments.
export const CHAT_QUESTIONS = QUESTIONS;

// ---- grounding ----

const WORD = /\p{L}[\p{L}\p{M}'-]*/gu;
const parts = (word) => word.split("'")[0].split("-").filter(Boolean);

function* strings(value) {
  if (typeof value === "string") yield value;
  else if (Array.isArray(value)) for (const item of value) yield* strings(item);
  else if (isObject(value)) for (const item of Object.values(value)) yield* strings(item);
}

// Every word of the supplied data, lowercase. A name the NPC may say has to appear here.
export function vocabulary(...sources) {
  const words = new Set();
  for (const source of sources)
    for (const value of strings(source))
      for (const [word] of value.matchAll(WORD)) {
        words.add(word.toLowerCase());
        for (const part of parts(word)) words.add(part.toLowerCase());
      }
  return words;
}

// Capitalized words that are not names of residents.
const NOT_NAMES = new Set([
  "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
  "january", "february", "march", "april", "may", "june", "july", "august", "september",
  "october", "november", "december", "god", "gods", "sir", "madam", "ma", "miss", "mister",
  "mr", "mrs", "ms", "dr", "lord", "lady", "master", "mistress",
]);
// Words that open a spoken sentence and may be followed by a comma or an exclamation mark.
const OPENERS = new Set([
  "a", "ah", "alas", "all", "alright", "always", "and", "any", "anyone", "are", "aye", "back", "be", "behind",
  "better", "but", "careful", "come", "dammit", "damn", "did", "do", "does", "don", "down", "easy", "enough",
  "even", "everyone", "fine", "fire", "first", "for", "get", "give", "go", "good", "gods", "great", "hang",
  "has", "have", "he", "hello", "help", "here", "hey", "hold", "hush", "if", "in", "is", "it", "just", "keep",
  "let", "listen", "look", "mind", "maybe", "move", "my", "never", "no", "nobody", "none", "nope", "not",
  "nothing", "now", "oh", "ok", "okay", "once", "one", "oof", "ouch", "out", "perhaps", "please", "put", "quick",
  "afternoon", "bye", "blast", "bother", "coward", "drop", "evening", "excuse", "farewell", "friend", "ha",
  "hah", "hands", "greetings", "goodbye", "guard", "guards", "hm", "hmm", "huh", "hurry", "leave", "mercy",
  "morning", "murder", "murderer", "night", "oi", "ow", "pardon", "peace", "phew", "safe", "shame", "shush",
  "stranger", "thief", "tsk", "uh", "um", "villain", "weapons", "welcome", "wow",
  "quiet", "right", "run", "she", "so", "somebody", "someone", "sorry", "stand", "stay", "steady", "still",
  "stop", "that", "the", "then", "there", "they", "this", "stand", "thanks", "thank", "think", "wait", "we",
  "well", "what", "when", "where", "who", "why", "whoa", "yes", "yeah", "yet", "you", "your",
]);

const isName = (part) => part.length >= 2 && /^\p{Lu}/u.test(part) && part !== part.toUpperCase();

function startsSentence(line, index) {
  let at = index - 1;
  while (at >= 0 && /[\s"'([{*_-]/u.test(line[at])) at--;
  return at < 0 || /[.!?\u2026]/u.test(line[at]);
}

// A capitalized sentence opener followed by one of these reads as the subject of an accusation or
// report ("Thorne paid me"), so it is checked like a name even without a vocative comma.
const DEED_VERBS = new Set([
  "did", "paid", "said", "told", "saw", "took", "stole", "killed", "hit", "struck", "started", "set", "sent",
  "made", "asked", "came", "went", "ran", "tried", "wanted", "knows", "knew", "wants", "lied", "burned",
  "attacked", "threatened", "robbed", "begged", "warned", "promised", "swore", "shouted", "hired", "owes",
]);

// Names that the line uses but the supplied data does not contain. Mid-sentence capitalized words
// are checked always; a sentence opener only when it reads as a shouted or addressed name
// ("Brannoch, run!"), as the subject of a deed ("Thorne paid me"), and is not an ordinary opener.
export function unsuppliedNames(line, supplied) {
  const known = supplied instanceof Set ? supplied : vocabulary(supplied);
  const names = [];
  for (const { 0: word, index } of line.matchAll(WORD)) {
    const opener = startsSentence(line, index);
    const rest = line.slice(index + word.length);
    const next = rest[0];
    const deed = DEED_VERBS.has(rest.match(/^\s+(\p{L}+)/u)?.[1]?.toLowerCase());
    for (const part of parts(word)) {
      const lower = part.toLowerCase();
      if (!isName(part) || NOT_NAMES.has(lower) || known.has(lower)) continue;
      if (opener && (part.length < 3 || OPENERS.has(lower) || !(",!?".includes(next ?? "") || deed))) continue;
      names.push(part);
    }
  }
  return names;
}

function assertGrounded(line, supplied) {
  if (unsuppliedNames(line, supplied).length) throw invalidOutput("unsupplied_name");
}

function parseJson(output) {
  try {
    return JSON.parse(output);
  } catch {
    throw invalidOutput("invalid_json");
  }
}

// One short spoken line for /v2/dialogue/say.
export function parseSay(output, request) {
  const result = parseJson(output);
  if (!isObject(result) || typeof result.response !== "string") throw invalidOutput("invalid_line");
  const response = spokenText(result.response);
  if (!response || response.length > SAY_LIMITS.characters || response.split(/\s+/u).length > SAY_LIMITS.words)
    throw invalidOutput("line_too_long");
  assertGrounded(response, vocabulary(request.npc, request.context, request.event, request.topic, request.listener));
  return { response };
}

// The generated chat reply plus its memory proposals, before grounding of the proposals.
export function parseChat(output, request, view, policy) {
  let parsed;
  try {
    parsed = parseDialogue(output, view, policy);
  } catch {
    throw invalidOutput("invalid_dialogue");
  }
  assertGrounded(parsed.response, vocabulary(request.npc, request.context, request.player,
    request.recent_dialogue, request.memories));
  return parsed;
}
