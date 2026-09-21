import "dotenv/config";
import OpenAI from "openai";
import { TypeSafeClient } from "@typesafe-ai/sdk";
import { createApp } from "./src/app.js";

// Lazy clients let the server start without credentials.
const app = createApp({
  decide: async (request, options = {}) => {
    if (!process.env.TYPESAFE_API_KEY)
      throw new Error("TypeSafe is not configured");
    const client = new TypeSafeClient({
      timeout: options.timeout ?? 10000,
      retry: { maxRetries: options.maxRetries ?? 1 },
    });
    return client.systemOne({
      ...request,
      model: process.env.TYPESAFE_MODEL || "jev-latest",
    });
  },
  generate: async (request) => {
    if (!process.env.OPENAI_API_KEY || !process.env.OPENAI_MODEL) {
      throw new Error("Dialogue model is not configured");
    }
    const client = new OpenAI({ timeout: 30000, maxRetries: 0 });
    return client.responses.create({
      ...request,
      model: process.env.OPENAI_MODEL,
    });
  },
});
app.listen(3536, "127.0.0.1", () =>
  console.log("NPC chat server: http://127.0.0.1:3536"),
);
