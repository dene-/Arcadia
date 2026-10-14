import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { existsSync, readFileSync } from "node:fs";
import { createApp } from "../src/app.js";
import { createProviderQueue } from "../src/provider-queue.js";
import { PROMPT_VERSION, PROTOCOL_VERSION } from "../src/cognition-contract.js";
import { unsuppliedNames } from "../src/dialogue-contract.js";
import { SPEECH_INTENTS as SAY_INTENTS } from "../src/dialogue.js";
import { UPSTREAM_BUDGETS_MS } from "../src/upstream.js";

const FIXTURES = new URL("../../../tests/fixtures/cognition_contract/", import.meta.url);
const fixture = (name) => JSON.parse(readFileSync(new URL(name, FIXTURES), "utf8"));
const manifest = fixture("manifest.json");
const clone = (value) => JSON.parse(JSON.stringify(value));

function deferred() {
  let resolve, reject;
  const promise = new Promise((res, rej) => { resolve = res; reject = rej; });
  return { promise, resolve, reject };
}
async function waitFor(predicate, message = "condition") {
  for (let attempt = 0; attempt < 400; attempt++) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  assert.fail(`Timed out waiting for ${message}`);
}
const untilAborted = (signal) => new Promise((_resolve, reject) => {
  signal.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")), { once: true });
});

async function server(t, services = {}) {
  const app = createApp({
    decide: async () => assert.fail("unexpected judgment call"),
    generate: async () => assert.fail("unexpected text call"),
    ...services,
  });
  const listener = app.listen(0, "127.0.0.1");
  await once(listener, "listening");
  t.after(() => { listener.closeAllConnections(); listener.close(); });
  const url = (path) => `http://127.0.0.1:${listener.address().port}${path}`;
  const send = (path, body, init = {}) => fetch(url(path), {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: typeof body === "string" ? body : JSON.stringify(body), ...init,
  });
  const post = async (path, body) => {
    const response = await send(path, body);
    return { status: response.status, body: await response.json() };
  };
  return { post, send };
}

const SAY = manifest.dialogue.say.route;
const CHAT = manifest.dialogue.chat.route;
const sayRequest = () => fixture(manifest.dialogue.say.request);
const sayResponse = () => fixture(manifest.dialogue.say.response);
const chatRequest = () => fixture(manifest.dialogue.chat.request);
const chatResponse = () => fixture(manifest.dialogue.chat.response);

// The provider's chat generation: the fixture reply and the memory proposal it is grounded against.
const generation = (overrides = {}) => ({
  response: chatResponse().response,
  memory_writes: chatResponse().memory_writes,
  recalled_memory_ids: chatResponse().recalled_memory_ids,
  ...overrides,
});
const supported = (questions) => Object.fromEntries(Object.entries(questions).map(([id]) => [id,
  { type: "noul", noul: 0.95 }]));

function chatServices({ output = generation(), judgments = chatResponse().judgments, ...rest } = {}) {
  const decisions = [], texts = [];
  return { decisions, texts, services: {
    decide: async (input, options) => {
      decisions.push({ input, options });
      return { answers: input.questions.supported_0 ? supported(input.questions) : clone(judgments) };
    },
    generate: async (input, options) => {
      texts.push({ input, options });
      return { output_text: JSON.stringify(output) };
    },
    ...rest,
  } };
}

test("the dialogue fixtures are listed in the manifest next to the cognition kinds", () => {
  assert.equal(manifest.protocol_version, PROTOCOL_VERSION);
  assert.equal(manifest.prompt_version, PROMPT_VERSION);
  assert.equal(Object.keys(manifest.kinds).length, 5);
  assert.deepEqual(Object.keys(manifest.dialogue), ["say", "chat"]);
  assert.equal(SAY, "/v2/dialogue/say");
  assert.equal(CHAT, "/v2/dialogue/chat");
  for (const entry of Object.values(manifest.dialogue)) {
    assert.ok(existsSync(new URL(entry.request, FIXTURES)), entry.request);
    assert.ok(existsSync(new URL(entry.response, FIXTURES)), entry.response);
  }
});

// ---- say ----

test("say returns one grounded line in the v2 envelope", async (t) => {
  const calls = [];
  const { post } = await server(t, { generate: async (input, options) => {
    calls.push({ input, options });
    return { output_text: JSON.stringify({ response: sayResponse().response }) };
  } });
  const result = await post(SAY, sayRequest());
  assert.equal(result.status, 200);
  assert.deepEqual(result.body, sayResponse());
  assert.equal(calls.length, 1);
  assert.equal(calls[0].options.timeout, UPSTREAM_BUDGETS_MS.ambient);
  assert.ok(calls[0].options.signal instanceof AbortSignal);
  assert.equal(calls[0].input.text.format.name, "npc_reaction");
  assert.match(calls[0].input.instructions, /warn/);
  const sent = JSON.parse(calls[0].input.input[0].content);
  assert.deepEqual(Object.keys(sent).sort(), ["context", "event", "intent", "listener", "npc", "relationship_scales", "topic"]);
  assert.equal(sent.intent, "warn");
  assert.equal(sent.listener.name, "Mirelle");
});

test("say accepts every intent of the closed set and rejects others", async (t) => {
  const { post } = await server(t, { generate: async () => ({ output_text: JSON.stringify({ response: "Hm." }) }) });
  assert.deepEqual([...SAY_INTENTS], ["remark", "warn", "call_for_help", "protest", "grieve", "share", "reply",
    "small_talk", "report", "acknowledge", "request_help", "decline", "farewell"]);
  for (const intent of SAY_INTENTS) {
    const request = sayRequest();
    request.intent = intent;
    if (intent === "share" || intent === "reply") request.topic = "The smith was struck outside the forge.";
    assert.equal((await post(SAY, request)).status, 200, intent);
  }
  const bad = sayRequest();
  bad.intent = "gossip";
  const result = await post(SAY, bad);
  assert.equal(result.status, 400);
  assert.equal(result.body.error, "invalid_request");
  const bare = sayRequest();
  bare.intent = "share";
  assert.equal((await post(SAY, bare)).status, 400);
});

test("say normalizes quotes, strips em dashes and enforces the length caps with a 502", async (t) => {
  let output = "He said \u201chold\u201d \u2014 stay back, friend.";
  const { post } = await server(t, { generate: async () => ({ output_text: JSON.stringify({ response: output }) }) });
  const clean = await post(SAY, sayRequest());
  assert.equal(clean.status, 200);
  assert.equal(clean.body.response.includes("\u2014"), false);
  assert.equal(/[\u201c\u201d\u2018\u2019]/u.test(clean.body.response), false);
  output = "Stay back ".repeat(30);
  const long = await post(SAY, sayRequest());
  assert.equal(long.status, 502);
  assert.equal(long.body.error, "invalid_provider_payload");
  output = "word ".repeat(26);
  assert.equal((await post(SAY, sayRequest())).status, 502);
});

test("say rejects a line naming a resident missing from the supplied context", async (t) => {
  let line = "Mirelle, keep clear.";
  const { post } = await server(t, { generate: async () => ({ output_text: JSON.stringify({ response: line }) }) });
  assert.equal((await post(SAY, sayRequest())).status, 200);
  line = "Bryn did this, mark me.";
  const result = await post(SAY, sayRequest());
  assert.equal(result.status, 502);
  assert.equal(result.body.code, "unsupplied_name");
  line = "He is hurt, Mirelle.";
  assert.equal((await post(SAY, sayRequest())).status, 200);
});

test("say answers a version mismatch with 409 and a malformed envelope with 400", async (t) => {
  const { post, send } = await server(t);
  const old = sayRequest();
  old.protocol_version = 1;
  const mismatch = await post(SAY, old);
  assert.equal(mismatch.status, 409);
  assert.deepEqual(mismatch.body, { error: "protocol_mismatch", protocol_version: PROTOCOL_VERSION, prompt_version: PROMPT_VERSION });
  const stale = sayRequest();
  stale.prompt_version = "cognition-0";
  assert.equal((await post(SAY, stale)).status, 409);
  const other = sayRequest();
  other.npc_id = "someone_else";
  assert.equal((await post(SAY, other)).status, 400);
  const noEvent = sayRequest();
  noEvent.event.sense = "smell";
  assert.equal((await post(SAY, noEvent)).status, 400);
  assert.equal((await send(SAY, "{not json")).status, 400);
});

test("say answers 503 when the provider fails or returns an incomplete response", async (t) => {
  let mode = "throw";
  const { post } = await server(t, { generate: async () => {
    if (mode === "throw") throw new Error("boom");
    return { status: "incomplete", output_text: "{}" };
  } });
  assert.deepEqual(await post(SAY, sayRequest()), { status: 503, body: { error: "unavailable" } });
  mode = "incomplete";
  assert.equal((await post(SAY, sayRequest())).status, 503);
});

test("a disconnect during say aborts the upstream call and frees the text permit", async (t) => {
  const queue = createProviderQueue();
  const seen = deferred();
  const { send } = await server(t, { queue, generate: async (_input, { signal }) => {
    seen.resolve(signal);
    return untilAborted(signal);
  } });
  const controller = new AbortController();
  const pending = send(SAY, sayRequest(), { signal: controller.signal }).catch((error) => error);
  const signal = await seen.promise;
  controller.abort();
  assert.equal((await pending).name, "AbortError");
  await waitFor(() => signal.aborted, "upstream abort");
  await waitFor(() => queue.stats().text.active === 0, "permit release");
  assert.equal(queue.stats().text.aborted, 1);
});

// ---- chat ----

test("chat runs the player-speech judgments then the grounded reply and returns the typed envelope", async (t) => {
  const { services, decisions, texts } = chatServices();
  const { post } = await server(t, services);
  const request = chatRequest();
  const result = await post(CHAT, request);
  assert.equal(result.status, 200);
  assert.deepEqual(result.body, chatResponse());

  const judgment = decisions.find((call) => call.input.questions.should_remember);
  assert.deepEqual(Object.keys(judgment.input.questions).sort(), [
    "affection_change", "emotional_intensity", "fear_change", "interaction_intent", "memory_importance",
    "respect_change", "response_mode", "should_end_conversation", "should_remember", "should_retrieve_memories",
    "should_update_belief", "suspicion_change", "trust_change"]);
  assert.deepEqual(judgment.input.state.player, request.player);
  assert.deepEqual(judgment.input.state.context.memories.map((memory) => memory.id), ["mem:garrin:4", "mem:garrin:9"]);
  assert.deepEqual(judgment.input.state.context.recent_dialogue, request.recent_dialogue);
  assert.deepEqual([judgment.options.timeout, judgment.options.maxRetries], [UPSTREAM_BUDGETS_MS.judgment, 0]);
  assert.ok(judgment.options.signal instanceof AbortSignal);
  assert.equal("request_id" in judgment.input.state, false);

  assert.equal(texts.length, 1);
  assert.equal(texts[0].input.text.format.name, "npc_dialogue");
  assert.ok(texts[0].options.timeout <= UPSTREAM_BUDGETS_MS.dialogue);
  assert.ok(texts[0].options.timeout > UPSTREAM_BUDGETS_MS.dialogue - 2000);
  const sent = JSON.parse(texts[0].input.input[0].content);
  assert.deepEqual(Object.keys(sent).sort(), ["context", "npc", "player", "policy", "relationship_scales"]);
  assert.equal(sent.policy.retrieve, true);
  assert.equal("relationship_deltas" in sent.policy, false);
  assert.equal("relationship_deltas" in result.body, false);

  const grounding = decisions.find((call) => call.input.questions.supported_0);
  assert.deepEqual([grounding.options.timeout, grounding.options.maxRetries], [UPSTREAM_BUDGETS_MS.grounding, 0]);
});

test("chat gives the model no memory candidates when the retrieval gate declines", async (t) => {
  const judgments = chatResponse().judgments;
  judgments.should_retrieve_memories = { type: "noul", noul: 0.1 };
  const { services, texts } = chatServices({ judgments, output: generation({ recalled_memory_ids: [] }) });
  const { post } = await server(t, services);
  const result = await post(CHAT, chatRequest());
  assert.equal(result.status, 200);
  assert.deepEqual(result.body.recalled_memory_ids, []);
  assert.deepEqual(JSON.parse(texts[0].input.input[0].content).context.memories, []);
});

test("chat reports the typed farewell judgment for the game to end the conversation", async (t) => {
  const judgments = chatResponse().judgments;
  judgments.should_end_conversation = { type: "noul", noul: 0.97 };
  judgments.interaction_intent = { ...judgments.interaction_intent, choice: "FAREWELL",
    probabilities: Object.fromEntries(Object.keys(judgments.interaction_intent.probabilities).map((key) =>
      [key, key === "FAREWELL" ? 1 : 0])) };
  const { services } = chatServices({ judgments, output: generation({ response: "Safe roads.", memory_writes: [], recalled_memory_ids: [] }) });
  const { post } = await server(t, services);
  const result = await post(CHAT, { ...chatRequest(), player: { message: "Goodbye.", identity: { name: "Den", sex: "Male" } } });
  assert.equal(result.status, 200);
  assert.equal(result.body.judgments.should_end_conversation.noul, 0.97);
  assert.equal(result.body.judgments.interaction_intent.choice, "FAREWELL");
  assert.equal(result.body.response, "Safe roads.");
});

test("chat normalizes quotes and dashes and rejects an oversized reply", async (t) => {
  let response = "You \u201cdo\u201d that \u2014 and you answer to the guard.";
  const { services } = chatServices();
  const { post } = await server(t, { ...services, generate: async () => ({ output_text: JSON.stringify(generation({ response, memory_writes: [], recalled_memory_ids: [] })) }) });
  const clean = await post(CHAT, chatRequest());
  assert.equal(clean.status, 200);
  assert.equal(/[\u201c\u201d\u2014]/u.test(clean.body.response), false);
  response = "Leave. ".repeat(1000);
  assert.equal((await post(CHAT, chatRequest())).status, 502);
});

test("chat rejects a reply naming a resident absent from the supplied context with 502", async (t) => {
  let response = "Mirelle saw it, ask her.";
  const { services } = chatServices();
  const { post } = await server(t, { ...services, generate: async () => ({ output_text: JSON.stringify(generation({ response, memory_writes: [], recalled_memory_ids: [] })) }) });
  assert.equal((await post(CHAT, chatRequest())).status, 200);
  response = "Thorne paid me to say it.";
  const result = await post(CHAT, chatRequest());
  assert.equal(result.status, 502);
  assert.equal(result.body.error, "invalid_provider_payload");
  assert.equal(result.body.code, "unsupplied_name");
});

test("names are accepted when supplied by the player message, memories or dialogue", () => {
  const supplied = ["Garrin Holt", "Mirelle", "Den"];
  assert.deepEqual(unsuppliedNames("Mirelle, wait.", supplied), []);
  assert.deepEqual(unsuppliedNames("Wait! Go and find Bryn.", supplied), ["Bryn"]);
  assert.deepEqual(unsuppliedNames("Stop, thief. Hold still.", supplied), []);
});

test("chat answers 400 for invalid input and 409 for version mismatch before any provider call", async (t) => {
  const { post } = await server(t);
  const old = chatRequest();
  old.protocol_version = 1;
  assert.equal((await post(CHAT, old)).status, 409);
  const noPlayer = chatRequest();
  delete noPlayer.player.message;
  assert.equal((await post(CHAT, noPlayer)).status, 400);
  const dup = chatRequest();
  dup.memories[1].id = dup.memories[0].id;
  assert.equal((await post(CHAT, dup)).status, 400);
  const history = chatRequest();
  history.recent_dialogue = "nope";
  assert.equal((await post(CHAT, history)).status, 400);
});

test("chat answers 502 for judgments that fail validation and 503 when a provider is unavailable", async (t) => {
  const bad = chatResponse().judgments;
  bad.should_remember = { type: "noul", noul: 2 };
  const first = chatServices({ judgments: bad });
  const { post } = await server(t, first.services);
  const invalid = await post(CHAT, chatRequest());
  assert.equal(invalid.status, 502);
  assert.equal(invalid.body.error, "invalid_provider_payload");
  assert.equal(first.texts.length, 0);

  const down = await server(t, { decide: async () => { throw new Error("down"); } });
  assert.deepEqual(await down.post(CHAT, chatRequest()), { status: 503, body: { error: "unavailable" } });

  const text = chatServices({ generate: async () => { throw new Error("down"); } });
  const textDown = await server(t, text.services);
  assert.equal((await textDown.post(CHAT, chatRequest())).status, 503);

  const garbled = chatServices({ generate: async () => ({ output_text: "not json" }) });
  const garbledServer = await server(t, garbled.services);
  const result = await garbledServer.post(CHAT, chatRequest());
  assert.equal(result.status, 502);
  assert.equal(result.body.code, "invalid_dialogue");
});

test("chat grounding runs nested under the text permit on a single-slot queue", async (t) => {
  const queue = createProviderQueue({ limits: { judgment: 1, text: 1 } });
  const { services } = chatServices();
  let during;
  const inner = services.decide;
  services.decide = async (input, options) => {
    if (input.questions.supported_0) during = queue.stats();
    return inner(input, options);
  };
  const { post } = await server(t, { ...services, queue });
  const result = await post(CHAT, chatRequest());
  assert.equal(result.status, 200);
  assert.equal(result.body.memory_writes.length, 1);
  assert.deepEqual([during.text.active, during.judgment.active], [1, 1]);
  assert.deepEqual([queue.stats().text.active, queue.stats().judgment.active], [0, 0]);
});

test("a disconnect during chat judgments, generation or grounding aborts upstream and frees every permit", async (t) => {
  for (const stage of ["judgment", "generation", "grounding"]) {
    const queue = createProviderQueue();
    const seen = deferred();
    const { services } = chatServices();
    const decide = services.decide, generate = services.generate;
    const { send } = await server(t, { queue,
      decide: async (input, options) => {
        const grounding = Boolean(input.questions.supported_0);
        if ((stage === "judgment" && !grounding) || (stage === "grounding" && grounding)) {
          seen.resolve(options.signal);
          return untilAborted(options.signal);
        }
        return decide(input, options);
      },
      generate: async (input, options) => {
        if (stage === "generation") { seen.resolve(options.signal); return untilAborted(options.signal); }
        return generate(input, options);
      },
    });
    const controller = new AbortController();
    const pending = send(CHAT, chatRequest(), { signal: controller.signal }).catch((error) => error);
    const signal = await seen.promise;
    controller.abort();
    assert.equal((await pending).name, "AbortError", stage);
    await waitFor(() => signal.aborted, `${stage} abort`);
    await waitFor(() => queue.stats().text.active === 0 && queue.stats().judgment.active === 0, `${stage} permit release`);
  }
});
