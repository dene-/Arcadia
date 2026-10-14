import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { TypeSafeClient } from "@typesafe-ai/sdk";
import { QUESTIONS, decisionPolicy } from "../src/npc-decisions.js";
import { createApp } from "../src/app.js";
import { VOICE_DIRECTIONS, voiceInstructions } from "../src/npc-voice.js";

function answers(overrides = {}, questions = QUESTIONS) {
  return Object.fromEntries(
    Object.entries(questions).map(([id, q]) => {
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
function appraisal(questions) {
  return answers({
    immediate_danger: 0.1,
    remember: 0.9,
    importance: 3,
    fear: 2,
    "disposition:player:trust:direction": "NEGATIVE",
    "disposition:player:trust:magnitude": 2,
  }, questions);
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
    memory_writes: [proposal()],
    recalled_memory_ids: [],
    ...overrides,
  };
}
async function server(t, services = {}) {
  const app = createApp({
    decide: async ({ questions }) => ({ answers: answers(
      { supported_0: 0.95, supported_1: 0.95, supported_2: 0.95 }, questions) }),
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
    return { status: response.status, body: response.status === 404 ? null : await response.json() };
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

test("surrender needs a confident intent judgment", () => {
  const judgment = answers({ interaction_intent: "SURRENDER" });
  assert.equal(decisionPolicy(judgment).interaction_intent, "SURRENDER");
  judgment.interaction_intent.confidence = 0.1;
  assert.equal(decisionPolicy(judgment).interaction_intent, "OTHER");
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
  assert.equal(result.response_mode, "DEFENSIVE");
  assert.equal(result.remember, false);
});
test("farewell decisions require clear intent and can accompany other intents", () => {
  for (const probability of [0.1, 0.5, 0.79, 0.8, 0.99]) {
    const policy = decisionPolicy(answers({
      interaction_intent: "FAREWELL",
      should_end_conversation: probability,
    }));
    assert.equal(policy.end_conversation, probability >= 0.8);
  }
  const raw = threat();
  raw.should_end_conversation.noul = 0.95;
  assert.equal(decisionPolicy(raw).interaction_intent, "THREAT");
  assert.equal(decisionPolicy(raw).end_conversation, true);
  raw.should_end_conversation.noul = "yes";
  assert.throws(() => decisionPolicy(raw));
});
test("farewell assessment reaches generation as policy with full player context", async (t) => {
  for (const [message, probability] of [
    ["Bye", 0.99],
    ["See you tomorrow", 0.98],
    ["I have to go", 0.95],
    ["That is all, thanks", 0.9],
    ["How do you say goodbye in Rekala?", 0.02],
    ["Before I go, where is the inn?", 0.05],
    ["I am not leaving yet", 0.01],
  ]) {
    // These are labeled mock decisions, not an evaluation of live model accuracy.
    const post = await server(t, {
      decide: async ({ state, questions }) => {
        assert.equal(state.player.message, message);
        assert.equal(state.context.recent_dialogue[0].text, "Need anything else?");
        assert.equal(questions.should_end_conversation.type, "noul");
        return { answers: answers({ should_end_conversation: probability }) };
      },
      generate: async ({ input, instructions }) => {
        const data = JSON.parse(input[0].content);
        assert.equal(data.policy.end_conversation, probability >= 0.8);
        assert.match(instructions, /brief in-character farewell/);
        return { output_text: JSON.stringify(dialogue({ response: "Take care." })) };
      },
    });
    const body = request();
    body.player.message = message;
    body.context.recent_dialogue = [{ speaker: "npc", text: "Need anything else?" }];
    const judgment = await post("/decide", body);
    assert.equal(judgment.status, 200);
    body.answers = judgment.body.answers;
    const reply = await post("/chat", body);
    assert.equal(reply.status, 200);
    assert.equal(reply.body.response, "Take care.");
  }
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
test("decisions and dialogue receive only the supplied bounded recollections", async (t) => {
  let seenDecision, seenPrompt;
  const post = await server(t, {
    decide: async (input) => {
      if (input.questions.supported_0) return { answers: answers({ supported_0: 0.95 }, input.questions) };
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
  body.context.relationship = {
    familiarity: 0.7,
    trust: 0.2,
    respect: 0.4,
    affection: -0.5,
    fear: 0.8,
    suspicion: 0.6,
  };
  const decision = await post("/decide", body);
  assert.equal(decision.status, 200);
  assert.deepEqual(seenDecision.state.context.memories, body.context.memories);
  body.answers = decision.body.answers;
  body.context.relationship.trust =
    decision.body.policy.relationship_delta.trust;
  const response = await post("/chat", body);
  assert.equal(response.status, 200);
  assert.equal(response.body.memory_writes.length, 1);
  assert.equal(response.body.replies, undefined);
  assert.equal(seenPrompt.text.format.schema.properties.replies, undefined);
  assert.doesNotMatch(seenPrompt.text.format.schema.required.join(), /replies/);
  assert.doesNotMatch(seenPrompt.instructions, /player repl/i);
  assert.equal(seenPrompt.store, false);
  assert.equal(seenPrompt.text.format.strict, true);
  const prompt = JSON.parse(seenPrompt.input[0].content);
  assert.equal(prompt.policy.response_mode, "DEFENSIVE");
  assert.ok(prompt.context.relationship.trust < 0);
  assert.deepEqual(prompt.context.memories, body.context.memories);
  assert.deepEqual(prompt.context.relationship, body.context.relationship);
  assert.equal(seenDecision.state.context.relationship.affection, -0.5);
  assert.equal(seenDecision.state.context.relationship.fear, 0.8);
  for (const field of [
    "familiarity",
    "trust",
    "respect",
    "affection",
    "fear",
    "suspicion",
  ])
    assert.equal(typeof prompt.relationship_scales[field], "string");
});

test("dialogue and reactions preserve different voices under the same policy or intent", async (t) => {
  const calls = [];
  const post = await server(t, { generate: async (input) => {
    calls.push({ instructions: input.instructions, state: JSON.parse(input.input[0].content) });
    return { output_text: JSON.stringify(dialogue({ memory_writes: [] })) };
  } });
  for (const path of ["/chat", "/react"]) {
    for (const voice of [
      { cadence: "BRISK", directness: "BLUNT", verbosity: "SPARE" },
      { cadence: "MEASURED", directness: "TACTFUL", verbosity: "EXPANSIVE" },
    ]) {
      const body = request();
      body.npc.profile.voice = voice;
      body.event = { text: "I heard fighting nearby.", sense: "hearing", player_involved: false };
      if (path === "/chat") body.answers = answers();
      else body.intent = "remark";
      assert.equal((await post(path, body)).status, 200);
    }
  }
  assert.equal(calls.length, 4);
  for (const { instructions, state } of calls) {
    assert.ok(instructions.endsWith(voiceInstructions(state.npc.profile)));
    assert.ok(instructions.includes(VOICE_DIRECTIONS.cadence[state.npc.profile.voice.cadence]));
  }
  for (const offset of [0, 2]) {
    assert.notEqual(calls[offset].instructions, calls[offset + 1].instructions);
    assert.deepEqual(calls[offset].state.policy, calls[offset + 1].state.policy);
  }
});

test("reactions write only the requested intent from the supplied context", async (t) => {
  const generated = [];
  const post = await server(t, {
    decide: async () => assert.fail("a reaction must not call a judgment"),
    generate: async (input, options) => {
      generated.push({ input: JSON.parse(input.input[0].content), options, store: input.store });
      return { output_text: '{"response":"Keep away!”"}' };
    },
  });
  const body = request();
  body.event = {
    text: "I saw the player attack someone.",
    sense: "sight",
    player_involved: true,
    participants: [{ name: "Mirelle", role: "hurt_person", relationship: { affection: 0.8 } }],
  };
  body.context.current.recent_ambient = [{ speaker: "Elora", text: "Mirelle, are you hurt?" }];
  body.context.current.location = "Mirelle's home and shop";
  body.context.current.recently_awakened = true;
  for (const intent of ["remark", "warn", "call_for_help", "protest", "grieve"]) {
    const reaction = await post("/react", { ...body, intent });
    assert.equal(reaction.status, 200);
    assert.equal(reaction.body.response, 'Keep away!"');
  }
  assert.deepEqual(generated.map((call) => call.input.intent),
    ["remark", "warn", "call_for_help", "protest", "grieve"]);
  const [first] = generated;
  assert.deepEqual(first.input.event.participants, body.event.participants);
  assert.deepEqual(first.input.context.current, body.context.current);
  assert.equal(first.input.policy, undefined);
  assert.equal(first.input.answers, undefined);
  assert.equal(first.store, false);
  assert.equal(first.options.timeout, 10000);
  assert.ok(first.options.signal instanceof AbortSignal);
});

test("a reaction ignores v1 answers and speech flags the game no longer sends", async (t) => {
  let seen;
  const post = await server(t, { generate: async (input) => {
    seen = JSON.parse(input.input[0].content);
    return { output_text: '{"response":"Hey!"}' };
  } });
  const body = { ...request(), intent: "protest", answers: { should_speak: { type: "noul", noul: 0 } },
    observationPolicy: { speak: false },
    event: { text: "Something hit me.", sense: "touch", player_involved: true, speech_allowed: false } };
  const result = await post("/react", body);
  assert.equal(result.status, 200);
  assert.equal(result.body.response, "Hey!");
  assert.equal(seen.answers, undefined);
  assert.equal(seen.observationPolicy, undefined);
});

test("the v1 observation and town-life decision routes are gone", async (t) => {
  const post = await server(t, {
    decide: async () => assert.fail("removed routes must not call inference"),
    generate: async () => assert.fail("removed routes must not call inference"),
  });
  for (const path of ["/observe", "/life/routine", "/life/social", "/life/listen"])
    assert.equal((await post(path, request())).status, 404, path);
});

test("invalid events and intents, failed generation and oversized reactions fail cleanly", async (t) => {
  let calls = 0;
  const post = await server(t, {
    generate: async () => {
      calls++;
      throw new Error("secret provider error");
    },
  });
  const event = { text: "I was hurt.", sense: "touch", player_involved: true };
  const body = { ...request(), event, intent: "protest" };
  for (const change of [
    (b) => delete b.event,
    (b) => (b.event = { ...event, sense: "smell" }),
    (b) => (b.event = { ...event, text: "" }),
    (b) => (b.event = { ...event, player_involved: "yes" }),
    (b) => delete b.intent,
    (b) => (b.intent = "silence"),
    (b) => (b.intent = "REMARK"),
    (b) => (b.intent = ["remark"]),
    (b) => (b.protocol_version = 2),
  ]) {
    const bad = structuredClone(body);
    change(bad);
    assert.equal((await post("/react", bad)).status, 400);
  }
  assert.equal(calls, 0);
  const failed = await post("/react", body);
  assert.equal(failed.status, 503);
  assert.ok(!JSON.stringify(failed).includes("secret"));
  assert.equal(calls, 1);
  const oversized = await server(t, {
    generate: async () => ({ output_text: JSON.stringify({ response: "x".repeat(161) }) }),
  });
  assert.equal((await oversized("/react", body)).status, 503);
  const incomplete = await server(t, {
    generate: async () => ({ status: "incomplete", output_text: '{"response":"Hey!"}' }),
  });
  assert.equal((await incomplete("/react", body)).status, 503);
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
test("spoken punctuation is normalized without losing grounded NPC promises", async (t) => {
  const post = await server(t, {
    generate: async () => ({
      output_text: JSON.stringify(
        dialogue({
          response: "I promise—I’ll mend it.",
          memory_writes: [
            proposal({
              type: "prospective",
              source: "npc_statement",
              gist: "I promised to mend it.",
              evidence: "I promise—I’ll mend it.",
            }),
          ],
        }),
      ),
    }),
  });
  const body = request();
  body.answers = threat();
  const result = await post("/chat", body);
  assert.equal(result.status, 200);
  assert.equal(result.body.response, "I promise, I'll mend it.");
  assert.equal(result.body.memory_writes[0].type, "prospective");
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
      decide: async ({ questions, state }) => ({
        answers: questions.supported_0
          ? answers({ supported_0: 0.95 }, questions)
          : questions.immediate_danger
            ? appraisal(questions)
            : questions.speak
              ? answers({ speak: 0.9, intent: "protest" }, questions)
              : state.player.message === "See you tomorrow."
                ? answers({ interaction_intent: "FAREWELL", should_end_conversation: 0.99 })
                : threat(),
      }),
      generate: async (input) => {
        const data = JSON.parse(input.input[0].content);
        return {
          output_text: JSON.stringify(
            input.text.format.name === "npc_reaction"
              ? { response: data.intent === "protest" ? "Keep away!" : "Wrong intent." }
              : data.policy.end_conversation
                ? dialogue({ response: "Until tomorrow.", memory_writes: [] })
                : dialogue(),
          ),
        };
      },
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

test("a valid quote cannot launder unsupported memory details", async (t) => {
  let checks = 0;
  const post = await server(t, {
    generate: async () => ({ output_text: JSON.stringify(dialogue({ memory_writes: [
      proposal(),
      proposal({ gist: "The player burned the forge yesterday.", important_details: ["Three people died."] }),
      proposal({ type: "prospective", gist: "The player promised to pay for a new forge." }),
    ] })) }),
    decide: async ({ state, questions }) => {
      checks++;
      assert.equal(Object.keys(questions).length, 3);
      assert.equal(state.candidates[1].source_text, request().player.message);
      assert.equal(state.candidates[1].proposal.evidence, "burn down your forge");
      assert.deepEqual(state.candidates[1].proposal.important_details, ["Three people died."]);
      // Labeled mock judgments exercise admission, not actual Jev accuracy.
      return { answers: answers({ supported_0: 0.95, supported_1: 0.1, supported_2: 0.5 }, questions) };
    },
  });
  const result = await post("/chat", { ...request(), answers: threat() });
  assert.equal(result.status, 200);
  assert.equal(checks, 1);
  assert.equal(result.body.memory_writes.length, 1);
  assert.equal(result.body.memory_writes[0].gist, proposal().gist);
  assert.equal(result.body.memory_writes[0].evidence, proposal().evidence);
});

test("grounding failures discard proposals while preserving valid dialogue", async (t) => {
  for (const answer of [null, { type: "noul", noul: 1.1 }, { type: "noul", noul: "0.99" },
    { type: "choice", noul: 0.99 }, { type: "noul", noul: 0.84 }]) {
    const post = await server(t, { decide: async () => ({ answers: { supported_0: answer } }) });
    const result = await post("/chat", { ...request(), answers: threat() });
    assert.equal(result.status, 200);
    assert.equal(result.body.response, "Leave my forge.");
    assert.deepEqual(result.body.memory_writes, []);
  }
  const post = await server(t, { decide: async () => { throw Error("provider unavailable"); } });
  const result = await post("/chat", { ...request(), answers: threat() });
  assert.equal(result.status, 200);
  assert.deepEqual(result.body.memory_writes, []);
});

test("no grounding call is made when nothing merits memory", async (t) => {
  const post = await server(t, { decide: async () => { assert.fail("unnecessary inference"); } });
  const result = await post("/chat", { ...request(), answers: answers() });
  assert.equal(result.status, 200);
  assert.deepEqual(result.body.memory_writes, []);
});
