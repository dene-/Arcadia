import "dotenv/config";
import OpenAI from "openai";
import { TypeSafeClient } from "@typesafe-ai/sdk";
import { createApp } from "./src/app.js";
import { UPSTREAM_BUDGETS_MS } from "./src/upstream.js";

// Lazy clients let the server start without credentials.
const app = createApp({
  // Options come from the queued callers: { signal, timeout, maxRetries }.
  decide: async (request, options = {}) => {
    if (!process.env.TYPESAFE_API_KEY)
      throw new Error("TypeSafe is not configured");
    const client = new TypeSafeClient();
    return client.systemOne({
      ...request,
      model: process.env.TYPESAFE_MODEL || "jev-latest",
    }, {
      signal: options.signal,
      timeout: options.timeout ?? UPSTREAM_BUDGETS_MS.judgment,
      retry: { maxRetries: options.maxRetries ?? 0 },
    });
  },
  generate: async (request, options = {}) => {
    if (!process.env.OPENAI_API_KEY || !process.env.OPENAI_MODEL) {
      throw new Error("Dialogue model is not configured");
    }
    const client = new OpenAI({ maxRetries: 0 });
    return client.responses.create({
      ...request,
      model: process.env.OPENAI_MODEL,
    }, {
      signal: options.signal,
      timeout: options.timeout ?? UPSTREAM_BUDGETS_MS.dialogue,
    });
  },
});
app.listen(3536, "127.0.0.1", (error) => {
  if (error) {
    console.error(error.code === "EADDRINUSE"
      ? "Cannot start NPC chat server: port 3536 is already in use. Stop the existing server first."
      : `Cannot start NPC chat server: ${error.message}`);
    process.exitCode = 1;
    return;
  }
  console.log("NPC chat server: http://127.0.0.1:3536");
});
