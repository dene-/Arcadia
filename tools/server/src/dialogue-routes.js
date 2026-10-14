import { Router } from "express";
import { ContractError, PROMPT_VERSION, PROTOCOL_VERSION, validateJudgments } from "./cognition-contract.js";
import {
  CHAT_QUESTIONS,
  chatJudgmentState,
  dialogueView,
  parseChat,
  parseSay,
  validateChat,
  validateSay,
} from "./dialogue-contract.js";
import {
  CHAT_GROUNDING_PROMPT,
  COGNITIVE_PROMPT,
  DIALOGUE_FORMAT,
  REACTION_FORMAT,
  SAY_PROMPT,
} from "./dialogue.js";
import { groundMemories } from "./memory-grounding.js";
import { RELATIONSHIP_SCALES, speechPolicy } from "./npc-decisions.js";
import { voiceInstructions } from "./npc-voice.js";
import { GAME_DEADLINES_MS, GAME_DEADLINE_MARGIN_MS, UPSTREAM_BUDGETS_MS, disconnectSignal } from "./upstream.js";

// Judgments run first, then generation and grounding. The whole route must finish before the game's
// deadline, so slow judgments shorten the generation budget instead of discarding its result.
const CHAT_DEADLINE_MS = GAME_DEADLINES_MS.dialogue - GAME_DEADLINE_MARGIN_MS;
const MIN_GENERATION_MS = 1000;

function reject(res, error) {
  return res.status(error.status).json(
    error.status === 409
      ? { ...error.body, protocol_version: PROTOCOL_VERSION, prompt_version: PROMPT_VERSION }
      : error.body,
  );
}

function complete(response) {
  if (response?.status && response.status !== "completed") throw new Error("Incomplete response");
  return response.output_text;
}

// `decide` is the queued judgment caller, `generate` the queued text caller and `withText` the text
// permit that nests a judgment (grounding) inside a generation.
export function dialogueRoutes({ decide, generate, withText }) {
  const router = Router();

  // Optional or NPC-to-NPC speech with a closed intent; the game already decided to speak.
  router.post("/say", async (req, res) => {
    const signal = disconnectSignal(res);
    let request;
    try {
      request = validateSay(req.body);
    } catch (error) {
      if (!(error instanceof ContractError)) throw error;
      return reject(res, error);
    }
    let output;
    try {
      output = complete(await generate({
        instructions: SAY_PROMPT + voiceInstructions(request.npc.profile),
        input: [{
          role: "user",
          content: JSON.stringify({
            npc: request.npc,
            intent: request.intent,
            topic: request.topic ?? null,
            event: request.event ?? null,
            listener: request.listener ?? null,
            context: request.context,
            relationship_scales: RELATIONSHIP_SCALES,
          }),
        }],
        text: { format: REACTION_FORMAT },
        store: false,
      }, { signal, timeout: UPSTREAM_BUDGETS_MS.ambient }));
    } catch (error) {
      if (signal.aborted) return;
      console.error(`Dialogue say unavailable: ${error?.name || "Unknown error"}`);
      return res.status(503).json({ error: "unavailable" });
    }
    if (signal.aborted) return;
    try {
      res.json({
        protocol_version: PROTOCOL_VERSION,
        request_id: request.request_id,
        ...parseSay(output, request),
      });
    } catch (error) {
      if (!(error instanceof ContractError)) throw error;
      console.error(`Dialogue say returned an invalid line (${error.body.code})`);
      reject(res, error);
    }
  });

  // Player dialogue: the player-speech judgments, then the grounded reply and memory proposals.
  router.post("/chat", async (req, res) => {
    const signal = disconnectSignal(res);
    const started = performance.now();
    let request;
    try {
      request = validateChat(req.body);
    } catch (error) {
      if (!(error instanceof ContractError)) throw error;
      return reject(res, error);
    }
    let answers;
    try {
      answers = (await decide(
        { state: chatJudgmentState(request), questions: CHAT_QUESTIONS },
        { signal, timeout: UPSTREAM_BUDGETS_MS.judgment, maxRetries: 0 },
      ))?.answers;
    } catch (error) {
      if (signal.aborted) return;
      console.error(`Dialogue chat judgments unavailable: ${error?.name || "Unknown error"}`);
      return res.status(503).json({ error: "unavailable" });
    }
    if (signal.aborted) return;
    let judgments, policy;
    try {
      judgments = validateJudgments(answers, CHAT_QUESTIONS);
      policy = speechPolicy(judgments);
    } catch (error) {
      if (!(error instanceof ContractError)) throw error;
      console.error("Dialogue chat returned invalid judgments");
      return reject(res, error);
    }

    // Only recalled memories reach the model: the retrieval gate decides.
    const view = dialogueView(request, policy.retrieve ? request.memories : []);
    let result;
    try {
      result = await withText(async ({ generate: upstream, decide: ground }) => {
        const timeout = Math.min(
          UPSTREAM_BUDGETS_MS.dialogue,
          Math.max(MIN_GENERATION_MS, CHAT_DEADLINE_MS - UPSTREAM_BUDGETS_MS.grounding - (performance.now() - started)),
        );
        const output = complete(await upstream({
          instructions: `${COGNITIVE_PROMPT}\n${CHAT_GROUNDING_PROMPT}${voiceInstructions(request.npc.profile)}`,
          input: [{
            role: "user",
            content: JSON.stringify({
              npc: view.npc,
              player: view.player,
              context: view.context,
              policy,
              relationship_scales: RELATIONSHIP_SCALES,
            }),
          }],
          text: { format: DIALOGUE_FORMAT },
          store: false,
        }, { timeout }));
        // A failure here is the provider's output, not its availability.
        const parsed = parseChat(output, request, view, policy);
        // Grounding runs under the dialogue's text permit; its judgment permit is a different pool.
        parsed.memory_writes = await groundMemories(parsed.memory_writes, view, parsed.response, ground);
        return parsed;
      }, { signal });
    } catch (error) {
      if (signal.aborted) return;
      if (error instanceof ContractError) {
        console.error(`Dialogue chat returned an invalid reply (${error.body.code})`);
        return reject(res, error);
      }
      console.error(`Dialogue chat unavailable: ${error?.name || "Unknown error"}`);
      return res.status(503).json({ error: "unavailable" });
    }
    if (signal.aborted) return;
    res.json({
      protocol_version: PROTOCOL_VERSION,
      request_id: request.request_id,
      judgments,
      response: result.response,
      memory_writes: result.memory_writes,
      recalled_memory_ids: result.recalled_memory_ids,
    });
  });
  return router;
}
