import express from "express";
import { townLifeRoutes } from "./town-life.js";
import { cognitionRoutes } from "./cognition-routes.js";
import { createProviders } from "./provider-queue.js";
import { UPSTREAM_BUDGETS_MS, disconnectSignal } from "./upstream.js";
import { QUESTIONS, RELATIONSHIP_SCALES, decisionPolicy } from "./npc-decisions.js";
import {
  COGNITIVE_PROMPT,
  DIALOGUE_FORMAT,
  parseDialogue,
  REACTION_INTENTS,
  REACTION_PROMPT,
  REACTION_FORMAT,
  parseReaction,
} from "./dialogue.js";
import { groundMemories } from "./memory-grounding.js";
import { voiceInstructions } from "./npc-voice.js";
function reportProviderFailure(service, error) {
  const status = Number.isInteger(error?.status) ? ` (HTTP ${error.status})` : "";
  console.error(`${service} failed${status}: ${error?.name || "Unknown error"}`);
}
function validateRequest(body) {
  if (
    body?.protocol_version !== 1 ||
    typeof body.npc?.id !== "string" ||
    !/^[a-z0-9_:-]{1,100}$/.test(body.npc.id)
  )
    throw new Error("Invalid NPC identity");
  if (
    !body.npc.profile ||
    typeof body.npc.profile !== "object" ||
    Array.isArray(body.npc.profile)
  )
    throw new Error("Invalid profile");
  if (
    typeof body.player?.message !== "string" ||
    body.player.message.length > 2000
  )
    throw new Error("Invalid message");
  const context = body.context;
  if (
    !context ||
    !Array.isArray(context.recent_dialogue) ||
    context.recent_dialogue.length > 12 ||
    !Array.isArray(context.memories) ||
    context.memories.length > 8 ||
    !context.relationship ||
    !context.current
  )
    throw new Error("Invalid context");
  for (const turn of context.recent_dialogue) {
    if (
      !["player", "npc"].includes(turn?.speaker) ||
      typeof turn.text !== "string" ||
      turn.text.length > 6000
    )
      throw new Error("Invalid history");
  }
  const events = context.current.recent_events;
  if (
    !Array.isArray(events) ||
    events.length > 8 ||
    events.some((e) => typeof e !== "string" || e.length > 500)
  )
    throw new Error("Invalid events");
  return body;
}
function validateReaction(body) {
  const request = validateRequest(body);
  const event = request.event;
  if (
    !event ||
    typeof event.text !== "string" ||
    !event.text.trim() ||
    event.text.length > 500 ||
    !["sight", "hearing", "touch"].includes(event.sense) ||
    typeof event.player_involved !== "boolean" ||
    !REACTION_INTENTS.includes(request.intent)
  )
    throw new Error("Invalid reaction");
  return request;
}
export function createApp({ decide: rawDecide, generate: rawGenerate, queue }) {
  const providers = createProviders({ decide: rawDecide, generate: rawGenerate, queue });
  const { decide, generate } = providers;
  const app = express();
  app.use(express.json({ limit: "96kb" }));
  app.use("/life", townLifeRoutes({ generate }));
  app.use("/v2/cognition", cognitionRoutes({ decide }));
  app.post("/decide", async (req, res) => {
    const signal = disconnectSignal(res);
    let request;
    try {
      request = validateRequest(req.body);
    } catch {
      return res.status(400).json({ error: "Invalid decision request." });
    }
    try {
      const state = {
        ...request,
        relationship_scales: RELATIONSHIP_SCALES,
      };
      const result = await decide({ state, questions: QUESTIONS }, { signal });
      res.json({
        answers: result.answers,
        policy: decisionPolicy(result.answers),
      });
    } catch (error) {
      if (signal.aborted) return;
      reportProviderFailure("NPC decision service", error);
      res.status(503).json({ error: "NPC decision service unavailable." });
    }
  });
  // The game decides whether to speak and with which intent (v2 utterance judgment); this route
  // only writes the line, in the NPC's saved voice.
  app.post("/react", async (req, res) => {
    const signal = disconnectSignal(res);
    let request;
    try {
      request = validateReaction(req.body);
    } catch {
      return res.status(400).json({ error: "Invalid reaction request." });
    }
    try {
      const response = await generate({
        instructions: REACTION_PROMPT + voiceInstructions(request.npc.profile),
        input: [
          {
            role: "user",
            content: JSON.stringify({
              npc: request.npc,
              event: request.event,
              intent: request.intent,
              context: request.context,
              relationship_scales: RELATIONSHIP_SCALES,
            }),
          },
        ],
        text: { format: REACTION_FORMAT },
        store: false,
      }, { signal, timeout: UPSTREAM_BUDGETS_MS.ambient });
      if (response.status && response.status !== "completed")
        throw new Error("Incomplete reaction");
      res.json(parseReaction(response.output_text));
    } catch (error) {
      if (signal.aborted) return;
      reportProviderFailure("NPC reaction service", error);
      res.status(503).json({ error: "NPC reaction service unavailable." });
    }
  });
  app.post("/chat", async (req, res) => {
    const signal = disconnectSignal(res);
    let request, policy;
    try {
      request = validateRequest(req.body);
      policy = decisionPolicy(request.answers);
    } catch {
      return res.status(400).json({ error: "Invalid dialogue request." });
    }
    try {
      const result = await providers.withText(async ({ generate: upstream, decide: ground }) => {
        const response = await upstream({
          instructions: COGNITIVE_PROMPT + voiceInstructions(request.npc.profile),
          input: [
            {
              role: "user",
              content: JSON.stringify({
                npc: request.npc,
                player: request.player,
                context: request.context,
                policy,
                relationship_scales: RELATIONSHIP_SCALES,
              }),
            },
          ],
          text: { format: DIALOGUE_FORMAT },
          store: false,
        }, { timeout: UPSTREAM_BUDGETS_MS.dialogue });
        if (response.status && response.status !== "completed")
          throw new Error("Incomplete response");
        const parsed = parseDialogue(response.output_text, request, policy);
        // Grounding runs under the dialogue's text permit; its judgment permit is a different pool.
        parsed.memory_writes = await groundMemories(parsed.memory_writes, request, parsed.response, ground);
        return parsed;
      }, { signal });
      res.json(result);
    } catch (error) {
      if (signal.aborted) return;
      reportProviderFailure("NPC dialogue service", error);
      res.status(503).json({ error: "NPC dialogue service unavailable." });
    }
  });
  app.use((error, req, res, _next) => {
    if (req.originalUrl.startsWith("/v2/")) {
      if (error.status === 413) return res.status(413).json({ error: "invalid_request", code: "payload_too_large" });
      if (error.type === "entity.parse.failed") return res.status(400).json({ error: "invalid_request", code: "invalid_json" });
      if (!(error.status >= 400 && error.status < 500)) {
        console.error(`Cognition route failed: ${error?.name || "Unknown error"}`);
        return res.status(500).json({ error: "internal_error" });
      }
      return res.status(400).json({ error: "invalid_request", code: "invalid_envelope" });
    }
    res
      .status(error.status === 413 ? 413 : 400)
      .json({ error: "Invalid request body." });
  });
  return app;
}
