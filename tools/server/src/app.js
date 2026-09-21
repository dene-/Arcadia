import express from "express";
import { townLifeRoutes } from "./town-life.js";
import {
  QUESTIONS,
  EVENT_QUESTIONS,
  RELATIONSHIP_SCALES,
  decisionPolicy,
  observationPolicy,
} from "./npc-decisions.js";
import {
  COGNITIVE_PROMPT,
  DIALOGUE_FORMAT,
  parseDialogue,
  REACTION_PROMPT,
  REACTION_FORMAT,
  parseReaction,
} from "./dialogue.js";
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
function validateObservation(body) {
  const request = validateRequest(body);
  const event = request.event;
  if (
    !event ||
    typeof event.text !== "string" ||
    !event.text.trim() ||
    event.text.length > 500 ||
    !["sight", "hearing", "touch"].includes(event.sense) ||
    typeof event.player_involved !== "boolean" ||
    typeof event.speech_allowed !== "boolean"
  )
    throw new Error("Invalid observation");
  return request;
}
export function createApp({ decide, generate }) {
  const app = express();
  app.use(express.json({ limit: "96kb" }));
  app.use("/life", townLifeRoutes({ decide, generate }));
  app.post("/decide", async (req, res) => {
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
        context: { ...request.context, memories: [] },
      };
      const result = await decide({ state, questions: QUESTIONS });
      res.json({
        answers: result.answers,
        policy: decisionPolicy(result.answers),
      });
    } catch {
      res.status(503).json({ error: "NPC decision service unavailable." });
    }
  });
  app.post("/observe", async (req, res) => {
    let request;
    try {
      request = validateObservation(req.body);
    } catch {
      return res.status(400).json({ error: "Invalid observation request." });
    }
    try {
      const state = {
        ...request,
        relationship_scales: RELATIONSHIP_SCALES,
        context: { ...request.context, memories: [] },
      };
      const result = await decide({ state, questions: EVENT_QUESTIONS });
      res.json({
        answers: result.answers,
        policy: observationPolicy(
          result.answers,
          request.event,
          request.npc.profile.cognition,
        ),
      });
    } catch {
      res.status(503).json({ error: "NPC observation service unavailable." });
    }
  });
  app.post("/react", async (req, res) => {
    let request, policy;
    try {
      request = validateObservation(req.body);
      policy = observationPolicy(
        request.answers,
        request.event,
        request.npc.profile.cognition,
      );
    } catch {
      return res.status(400).json({ error: "Invalid reaction request." });
    }
    if (!policy.speak) return res.json({ response: "" });
    try {
      const response = await generate({
        instructions: REACTION_PROMPT,
        input: [
          {
            role: "user",
            content: JSON.stringify({
              npc: request.npc,
              event: request.event,
              context: request.context,
              policy,
              relationship_scales: RELATIONSHIP_SCALES,
            }),
          },
        ],
        text: { format: REACTION_FORMAT },
        store: false,
      });
      if (response.status && response.status !== "completed")
        throw new Error("Incomplete reaction");
      res.json(parseReaction(response.output_text));
    } catch {
      res.status(503).json({ error: "NPC reaction service unavailable." });
    }
  });
  app.post("/chat", async (req, res) => {
    let request, policy;
    try {
      request = validateRequest(req.body);
      policy = decisionPolicy(request.answers);
    } catch {
      return res.status(400).json({ error: "Invalid dialogue request." });
    }
    try {
      const response = await generate({
        instructions: COGNITIVE_PROMPT,
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
      });
      if (response.status && response.status !== "completed")
        throw new Error("Incomplete response");
      res.json(parseDialogue(response.output_text, request, policy));
    } catch {
      res.status(503).json({ error: "NPC dialogue service unavailable." });
    }
  });
  app.use((error, _req, res, _next) =>
    res
      .status(error.status === 413 ? 413 : 400)
      .json({ error: "Invalid request body." }),
  );
  return app;
}
