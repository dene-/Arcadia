import { Router } from "express";
import {
  COGNITION_KINDS,
  ContractError,
  PROMPT_VERSION,
  PROTOCOL_VERSION,
  buildQuestions,
  providerState,
  validateEnvelope,
  validateJudgments,
} from "./cognition-contract.js";
import { UPSTREAM_BUDGETS_MS, disconnectSignal } from "./upstream.js";

export const COGNITION_ROUTES = Object.freeze(Object.fromEntries(
  COGNITION_KINDS.map((kind) => [kind, `/${kind.replaceAll("_", "-")}`]),
));

// `decide` must be the queued judgment caller. Routes return typed judgments only.
export function cognitionRoutes({ decide }) {
  const router = Router();
  for (const kind of COGNITION_KINDS) {
    router.post(COGNITION_ROUTES[kind], async (req, res) => {
      const signal = disconnectSignal(res);
      let envelope, questions;
      try {
        envelope = validateEnvelope(req.body, kind);
        questions = buildQuestions(envelope);
      } catch (error) {
        if (!(error instanceof ContractError)) throw error;
        return res.status(error.status).json(
          error.status === 409
            ? { ...error.body, protocol_version: PROTOCOL_VERSION, prompt_version: PROMPT_VERSION }
            : error.body,
        );
      }
      let result;
      try {
        result = await decide(
          { state: providerState(envelope), questions },
          { signal, timeout: UPSTREAM_BUDGETS_MS.judgment, maxRetries: 0 },
        );
      } catch (error) {
        if (signal.aborted) return;
        console.error(`Cognition ${kind} unavailable: ${error?.name || "Unknown error"}`);
        return res.status(503).json({ error: "unavailable" });
      }
      if (signal.aborted) return;
      try {
        const judgments = validateJudgments(result?.answers, questions);
        res.json({
          protocol_version: PROTOCOL_VERSION,
          prompt_version: PROMPT_VERSION,
          request_id: envelope.request_id,
          kind,
          model: typeof result.model === "string" ? result.model.slice(0, 100) : "",
          judgments,
        });
      } catch (error) {
        if (!(error instanceof ContractError)) throw error;
        console.error(`Cognition ${kind} returned an invalid provider payload`);
        res.status(error.status).json(error.body);
      }
    });
  }
  return router;
}
