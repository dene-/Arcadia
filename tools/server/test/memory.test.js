import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { TypeSafeClient } from "@typesafe-ai/sdk";
import { QUESTIONS, decisionPolicy } from "../src/npc-decisions.js";
import { createApp } from "../src/app.js";

function answers(overrides = {}) {
  return Object.fromEntries(
    Object.entries(QUESTIONS).map(([id, q]) => {
      const value =
        overrides[id] ??
        (q.type === "noul"
          ? 0.1
          : q.type === "score"
            ? 0
            : Object.keys(q.criteria).includes("UNCHANGED")
              ? "UNCHANGED"
              : Object.keys(q.criteria)[0]);
      if (q.type === "noul") return [id, { type: q.type, noul: value }];
      const keys =
        q.type === "choice"
          ? Object.keys(q.criteria)
          : q.criteria.map((_, i) => String(i));
      return [
        id,
        {
          type: q.type,
          [q.type]: value,
          confidence: 0.95,
          probabilities: Object.fromEntries(
            keys.map((key) => [key, key === String(value) ? 1 : 0]),
          ),
        },
      ];
    }),
  );
}
function request() {
  return {
    protocol_version: 1,
    npc: { id: "garrin_holt", profile: { name: "Garrin", job: "Blacksmith" } },
    player: { message: "I will burn down your forge." },
    context: {
      recent_dialogue: [],
      relationship: { trust: 0 },
      memories: [],
      current: { recent_events: [] },
    },
  };
}
function proposal(overrides = {}) {
  return {
    type: "episodic",
    gist: "The player threatened the forge.",
    source: "player_claim",
    evidence: "burn down your forge",
    topics: ["forge"],
    people: ["player"],
    places: [],
    sensory_cues: [],
    important_details: [],
    weak_details: [],
    known_gaps: [],
    ...overrides,
  };
}
function dialogue(overrides = {}) {
  return {
    response: "Leave my forge.",
    replies: ["I am sorry.", "I meant it.", "Goodbye."],
    memory_writes: [proposal()],
    recalled_memory_ids: [],
    ...overrides,
  };
}
async function server(t, services = {}) {
  const app = createApp({
    decide: async () => ({ answers: answers() }),
    generate: async () => ({ output_text: JSON.stringify(dialogue()) }),
    ...services,
  });
  const listener = app.listen(0, "127.0.0.1");
  await once(listener, "listening");
  t.after(() => {
    listener.closeAllConnections();
    listener.close();
  });
  return async (path, body) => {
    const response = await fetch(
      `http://127.0.0.1:${listener.address().port}${path}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      },
    );
    return { status: response.status, body: await response.json() };
  };
}
const threat = () =>
  answers({
    should_remember: 0.93,
    memory_importance: 3,
    emotional_intensity: 3,
    interaction_intent: "THREAT",
    trust_change: "NEGATIVE",
    fear_change: "POSITIVE",
    should_retrieve_memories: 0.81,
    response_mode: "DEFENSIVE",
  });

test("greetings stay short term; threat decisions produce bounded state changes", () => {
  assert.equal(decisionPolicy(answers()).remember, false);
  const result = decisionPolicy(threat());
  assert.equal(result.remember, true);
  assert.equal(result.retrieve, true);
  assert.equal(result.importance, 0.75);
  assert.equal(result.response_mode, "DEFENSIVE");
  assert.ok(
    result.relationship_delta.trust < 0 &&
      result.relationship_delta.trust >= -0.1,
  );
  assert.ok(result.relationship_delta.fear > 0);
  assert.equal(result.update_belief, false);
});
test("uncertain choices cannot alter trust and probability 0.5 is not intensity", () => {
  const raw = threat();
  raw.trust_change.confidence = 0.2;
  raw.response_mode.confidence = 0.1;
  raw.should_remember.noul = 0.5;
  const result = decisionPolicy(raw);
  assert.equal(result.relationship_delta.trust, 0);
  assert.equal(result.response_mode, "UNCERTAIN");
  assert.equal(result.remember, false);
});
test("malformed Jev outputs are rejected before policy application", () => {
  for (const change of [
    (a) => delete a.trust_change,
    (a) => (a.should_remember.noul = NaN),
    (a) => (a.memory_importance.score = 5),
    (a) => (a.trust_change.choice = "ERASE_SAVE"),
    (a) => (a.trust_change.probabilities.NEGATIVE = 5),
  ]) {
    const raw = threat();
    change(raw);
    assert.throws(() => decisionPolicy(raw));
  }
});
test("official SDK contract uses named questions and the systemone endpoint (mock fetch)", async () => {
  let sent;
  const client = new TypeSafeClient({
    apiKey: "test-only",
    retry: { maxRetries: 0 },
    fetch: async (url, init) => {
      sent = { url: String(url), body: JSON.parse(init.body) };
      return new Response(
        JSON.stringify({
          model: "jev-test",
          answers: threat(),
          usage: { input_tokens: 1, output_tokens: 1 },
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    },
  });
  const result = await client.systemOne({
    state: request(),
    questions: QUESTIONS,
  });
  assert.equal(sent.url, "https://api.typesafe.ai/v1/systemone");
  assert.equal(sent.body.questions.should_remember.type, "noul");
  assert.equal(decisionPolicy(result.answers).remember, true);
});
test("decision stage excludes archive; dialogue receives updated state and recall only", async (t) => {
  let seenDecision, seenPrompt;
  const post = await server(t, {
    decide: async (input) => {
      seenDecision = input;
      return { answers: threat() };
    },
    generate: async (input) => {
      seenPrompt = input;
      return { status: "completed", output_text: JSON.stringify(dialogue()) };
    },
  });
  const body = request();
  body.context.memories = [{ id: "core:one", gist: "visible gist" }];
  const decision = await post("/decide", body);
  assert.equal(decision.status, 200);
  assert.deepEqual(seenDecision.state.context.memories, []);
  body.answers = decision.body.answers;
  body.context.relationship.trust =
    decision.body.policy.relationship_delta.trust;
  const response = await post("/chat", body);
  assert.equal(response.status, 200);
  assert.equal(response.body.memory_writes.length, 1);
  assert.equal(seenPrompt.store, false);
  assert.equal(seenPrompt.text.format.strict, true);
  const prompt = JSON.parse(seenPrompt.input[0].content);
  assert.equal(prompt.policy.response_mode, "DEFENSIVE");
  assert.ok(prompt.context.relationship.trust < 0);
  assert.deepEqual(prompt.context.memories, body.context.memories);
});
test("unsupported observations, ungated beliefs and hidden recall IDs are dropped", async (t) => {
  const post = await server(t, {
    generate: async () => ({
      output_text: JSON.stringify(
        dialogue({
          memory_writes: [
            proposal({ source: "observed_event" }),
            proposal({ type: "semantic" }),
            proposal({ evidence: "I handed you gold" }),
          ],
          recalled_memory_ids: ["visible", "hidden", "visible"],
        }),
      ),
    }),
  });
  const body = request();
  body.answers = threat();
  body.context.memories = [{ id: "visible" }];
  const result = await post("/chat", body);
  assert.deepEqual(result.body.memory_writes, []);
  assert.deepEqual(result.body.recalled_memory_ids, ["visible"]);
});
test("gated beliefs retain source; model relationship changes have no authority", async (t) => {
  const post = await server(t, {
    generate: async () => ({
      output_text: JSON.stringify(
        dialogue({
          memory_writes: [proposal({ type: "semantic" })],
          relationship_delta: { trust: 100 },
        }),
      ),
    }),
  });
  const body = request();
  body.answers = threat();
  body.answers.should_update_belief.noul = 0.95;
  const result = await post("/chat", body);
  assert.equal(result.body.memory_writes[0].source, "player_claim");
  assert.equal(result.body.relationship_delta, undefined);
});
test("service errors, refusals and incomplete or invalid model output fail cleanly", async (t) => {
  for (const output of [
    null,
    "{",
    JSON.stringify(dialogue({ replies: ["Only one"] })),
    JSON.stringify(dialogue({ memory_writes: null })),
  ]) {
    const post = await server(t, {
      generate: async () => ({ output_text: output }),
    });
    const body = request();
    body.answers = threat();
    assert.equal((await post("/chat", body)).status, 503);
  }
  const post = await server(t, {
    decide: async () => {
      throw new Error("secret credential");
    },
    generate: async () => ({
      status: "incomplete",
      output_text: JSON.stringify(dialogue()),
    }),
  });
  const decision = await post("/decide", request());
  assert.equal(decision.status, 503);
  assert.ok(!JSON.stringify(decision).includes("secret"));
  const body = request();
  body.answers = threat();
  assert.equal((await post("/chat", body)).status, 503);
});
test("invalid version, events, identity and oversized player input never reach inference", async (t) => {
  const post = await server(t, {
    decide: async () => {
      assert.fail("must not call inference");
    },
  });
  for (const change of [
    (b) => (b.protocol_version = 2),
    (b) => (b.npc.id = ""),
    (b) => (b.context.current.recent_events = [null]),
    (b) => (b.player.message = "x".repeat(2001)),
  ]) {
    const body = request();
    change(body);
    assert.equal((await post("/decide", body)).status, 400);
  }
});

test(
  "real Godot HTTP client completes a mocked Jev and dialogue exchange",
  { skip: !process.env.GODOT },
  async (t) => {
    const { execFile } = await import("node:child_process");
    const { promisify } = await import("node:util");
    const { mkdtemp, rm } = await import("node:fs/promises");
    const { tmpdir } = await import("node:os");
    const { fileURLToPath } = await import("node:url");
    const path = await mkdtemp(`${tmpdir()}/arcadia-http-test-`);
    t.after(() => rm(path, { recursive: true, force: true }));
    const listener = createApp({
      decide: async () => ({ answers: threat() }),
      generate: async () => ({ output_text: JSON.stringify(dialogue()) }),
    }).listen(0, "127.0.0.1");
    await once(listener, "listening");
    t.after(() => {
      listener.closeAllConnections();
      listener.close();
    });
    const { stdout, stderr } = await promisify(execFile)(
      process.env.GODOT,
      [
        "--headless",
        "--path",
        fileURLToPath(new URL("../../../", import.meta.url)),
        "--script",
        "res://tests/integration/npc_memory_http_test.gd",
        "--log-file",
        `${path}/godot.log`,
      ],
      {
        timeout: 15000,
        env: {
          ...process.env,
          ARCADIA_TEST_SERVER_URL: `http://127.0.0.1:${listener.address().port}`,
        },
      },
    );
    assert.match(stdout, /Godot HTTP memory integration passed/);
    assert.doesNotMatch(stderr, /SCRIPT ERROR/);
  },
);
