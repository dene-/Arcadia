import express from "express";
import { cognitionRoutes } from "./cognition-routes.js";
import { dialogueRoutes } from "./dialogue-routes.js";
import { createProviders } from "./provider-queue.js";

export function createApp({ decide: rawDecide, generate: rawGenerate, queue }) {
  const providers = createProviders({ decide: rawDecide, generate: rawGenerate, queue });
  const { decide, generate } = providers;
  const app = express();
  app.use("/v2", express.json({ limit: "96kb" }));
  app.use("/v2/cognition", cognitionRoutes({ decide }));
  app.use("/v2/dialogue", dialogueRoutes({ decide, generate, withText: providers.withText }));
  app.use((error, _req, res, _next) => {
    if (error.status === 413) return res.status(413).json({ error: "invalid_request", code: "payload_too_large" });
    if (error.type === "entity.parse.failed") return res.status(400).json({ error: "invalid_request", code: "invalid_json" });
    if (!(error.status >= 400 && error.status < 500)) {
      console.error(`Cognition route failed: ${error?.name || "Unknown error"}`);
      return res.status(500).json({ error: "internal_error" });
    }
    res.status(400).json({ error: "invalid_request", code: "invalid_envelope" });
  });
  return app;
}
