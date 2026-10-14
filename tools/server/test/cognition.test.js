import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { existsSync, readFileSync } from "node:fs";
import { createApp } from "../src/app.js";
import { createProviderQueue } from "../src/provider-queue.js";
import {
  COGNITION_KINDS,
  PROMPT_VERSION,
  PROTOCOL_VERSION,
  buildQuestions,
  validateEnvelope,
  validateJudgments,
} from "../src/cognition-contract.js";
import { COGNITION_ROUTES } from "../src/cognition-routes.js";
import { GAME_DEADLINES_MS, GAME_DEADLINE_MARGIN_MS, UPSTREAM_BUDGETS_MS } from "../src/upstream.js";

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
// Resolves when the upstream call is aborted, mirroring an SDK that honours its signal.
const untilAborted = (signal) => new Promise((_resolve, reject) => {
  signal.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")), { once: true });
});

function answers(questions, overrides = {}) {
  return Object.fromEntries(Object.entries(questions).map(([id, q]) => {
    const value = overrides[id] ?? (q.type === "noul" ? 0.1 : q.type === "score" ? 0
      : Object.keys(q.criteria).includes("UNCHANGED") ? "UNCHANGED" : Object.keys(q.criteria)[0]);
    if (q.type === "noul") return [id, { type: q.type, noul: value }];
    const keys = q.type === "score" ? q.criteria.map((_, i) => String(i)) : Object.keys(q.criteria);
    return [id, { type: q.type, [q.type]: value, confidence: 0.95,
      probabilities: Object.fromEntries(keys.map((key) => [key, key === String(value) ? 1 : 0])) }];
  }));
}

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

const route = (kind) => COGNITION_ROUTES[kind] && `/v2/cognition${COGNITION_ROUTES[kind]}`;

test("fixtures cover every kind and the manifest points at existing files", () => {
  assert.equal(manifest.protocol_version, PROTOCOL_VERSION);
  assert.equal(manifest.prompt_version, PROMPT_VERSION);
  assert.deepEqual(Object.keys(manifest.kinds).sort(), [...COGNITION_KINDS].sort());
  for (const [kind, entry] of Object.entries(manifest.kinds)) {
    assert.equal(entry.route, route(kind));
    assert.ok(existsSync(new URL(entry.request, FIXTURES)), entry.request);
    assert.ok(existsSync(new URL(entry.response, FIXTURES)), entry.response);
  }
  assert.equal(manifest.invalid.length, 5);
  for (const entry of manifest.invalid) assert.ok(existsSync(new URL(entry.file, FIXTURES)), entry.file);
});

for (const kind of COGNITION_KINDS) {
  test(`${kind} returns the validated typed judgments for the fixture exchange`, async (t) => {
    const request = fixture(manifest.kinds[kind].request);
    const expected = fixture(manifest.kinds[kind].response);
    const calls = [];
    const { post } = await server(t, { decide: async (input, options) => {
      calls.push({ input, options });
      return { answers: clone(expected.judgments), model: expected.model };
    } });
    const result = await post(route(kind), request);
    assert.equal(result.status, 200);
    assert.deepEqual(result.body, expected);

    assert.equal(calls.length, 1);
    const { input, options } = calls[0];
    assert.deepEqual(Object.keys(input.questions).sort(), Object.keys(expected.judgments).sort());
    assert.deepEqual(input.state.evidence, request.evidence);
    assert.equal(input.state.npc_id, request.npc_id);
    assert.equal("ticket" in input.state || "request_id" in input.state, false);
    assert.equal(options.timeout, UPSTREAM_BUDGETS_MS.judgment);
    assert.equal(options.maxRetries, 0);
    assert.ok(options.signal instanceof AbortSignal);
    for (const question of Object.values(input.questions)) {
      assert.match(question.instructions, /independently/);
      if (question.type === "score") assert.equal(question.criteria.length, 5);
    }
  });
}

test("question ids are built only from the validated supplied ids", () => {
  const appraise = buildQuestions(validateEnvelope(fixture("appraise.request.json"), "appraise"));
  for (const subject of ["player", "mirelle"])
    for (const dimension of ["trust", "affection", "respect", "fear", "suspicion"])
      for (const part of ["direction", "magnitude"]) assert.ok(appraise[`disposition:${subject}:${dimension}:${part}`]);
  assert.deepEqual(Object.keys(appraise[`disposition:player:trust:direction`].criteria), ["NEGATIVE", "UNCHANGED", "POSITIVE"]);
  assert.equal(Object.keys(appraise).length, 7 + 2 * 5 * 2);

  const goals = buildQuestions(validateEnvelope(fixture("select_goal.request.json"), "select_goal"));
  assert.deepEqual(Object.keys(goals).sort(), [
    "duration:REST_HOME", "duration:VISIT_MIRELLE", "duration:WORK_FORGE",
    "suitability:REST_HOME", "suitability:VISIT_MIRELLE", "suitability:WORK_FORGE"]);
  assert.deepEqual(Object.keys(goals["duration:REST_HOME"].criteria), ["BRIEF", "ORDINARY", "EXTENDED"]);

  const social = buildQuestions(validateEnvelope(fixture("social.request.json"), "social"));
  assert.deepEqual(Object.keys(social.topic.criteria), ["SMALL_TALK", "news:forge_attack", "news:market_prices"]);
  assert.deepEqual(Object.keys(social.tone.criteria), ["friendly", "reserved", "concerned", "curious"]);

  const listen = buildQuestions(validateEnvelope(fixture("listen.request.json"), "listen"));
  assert.ok(listen.believe_account && listen.remember && listen.importance && listen["disposition:mirelle:respect:magnitude"]);
});

test("protocol and prompt mismatches are rejected with 409 before any other validation or provider work", async (t) => {
  const { post } = await server(t);
  const request = fixture("appraise.request.json");
  for (const change of [
    (r) => { r.protocol_version = 1; },
    (r) => { r.protocol_version = 3; },
    (r) => { delete r.protocol_version; },
    (r) => { r.prompt_version = "cognition-0"; },
    (r) => { r.prompt_version = 7; },
    (r) => { delete r.prompt_version; r.state = "broken"; },
  ]) {
    const body = clone(request);
    change(body);
    const result = await post(route("appraise"), body);
    assert.equal(result.status, 409);
    assert.deepEqual(result.body, { error: "protocol_mismatch", protocol_version: PROTOCOL_VERSION, prompt_version: PROMPT_VERSION });
  }
});

test("invalid envelopes are rejected with 400 and a stable code before any provider work", async (t) => {
  const { post, send } = await server(t);
  const cases = [
    ["appraise", "invalid_request_id", (r) => { r.request_id = "has space"; }],
    ["appraise", "invalid_request_id", (r) => { delete r.request_id; }],
    ["appraise", "invalid_npc_id", (r) => { r.npc_id = 4; }],
    ["appraise", "kind_mismatch", (r) => { r.kind = "listen"; }],
    ["appraise", "invalid_ticket", (r) => { r.ticket.task_generation = -1; }],
    ["appraise", "invalid_ticket", (r) => { delete r.ticket; }],
    ["appraise", "invalid_ticket", (r) => { r.ticket.candidate_ids = Array(9).fill("a").map((v, i) => v + i); }],
    ["appraise", "invalid_state", (r) => { r.state = []; }],
    ["appraise", "state_too_large", (r) => { r.state = { blob: "x".repeat(16 * 1024) }; }],
    ["appraise", "invalid_evidence", (r) => { r.evidence = Array.from({ length: 9 }, (_, i) => ({ ...r.evidence[0], id: `ev:${i}` })); }],
    ["appraise", "invalid_evidence", (r) => { r.evidence[1].id = r.evidence[0].id; }],
    ["appraise", "invalid_evidence", (r) => { r.evidence[0].text = ""; }],
    ["appraise", "invalid_evidence", (r) => { delete r.evidence[0].participant_ids; }],
    ["appraise", "invalid_subjects", (r) => { r.subjects = ["a", "b", "c", "d"]; }],
    ["appraise", "invalid_subjects", (r) => { r.subjects = ["player", "player"]; }],
    ["appraise", "invalid_subjects", (r) => { r.subjects = ["bad id"]; }],
    ["listen", "invalid_subjects", (r) => { delete r.subjects; }],
    ["select_goal", "invalid_candidates", (r) => { r.candidates = []; }],
    ["select_goal", "invalid_candidates", (r) => { r.candidates = Array.from({ length: 9 }, (_, i) => ({ id: `g${i}`, description: "x" })); }],
    ["select_goal", "invalid_candidates", (r) => { r.candidates[1].id = r.candidates[0].id; }],
    ["select_goal", "invalid_candidates", (r) => { r.candidates[0].id = "not valid!"; }],
    ["select_goal", "invalid_candidates", (r) => { r.candidates[0].description = 5; }],
    ["social", "invalid_topics", (r) => { r.topics = Array.from({ length: 7 }, (_, i) => `t${i}`); }],
    ["social", "invalid_topics", (r) => { r.topics = ["SMALL_TALK"]; }],
    ["social", "invalid_tones", (r) => { r.tones = []; }],
    ["utterance", "invalid_intents", (r) => { r.intents = []; }],
    ["utterance", "invalid_intents", (r) => { r.intents = "warn"; }],
  ];
  for (const [kind, code, change] of cases) {
    const body = clone(fixture(manifest.kinds[kind].request));
    change(body);
    const result = await post(route(kind), body);
    assert.deepEqual([result.status, result.body], [400, { error: "invalid_request", code }], `${kind}: ${code}`);
  }
  const array = await post(route("appraise"), []);
  assert.deepEqual([array.status, array.body], [400, { error: "invalid_request", code: "invalid_envelope" }]);
  for (const body of ["null", '"text"', "4"]) {
    const response = await send(route("appraise"), body);
    assert.deepEqual([response.status, await response.json()], [400, { error: "invalid_request", code: "invalid_json" }]);
  }
  const malformed = await send(route("appraise"), "{not json");
  assert.deepEqual([malformed.status, await malformed.json()], [400, { error: "invalid_request", code: "invalid_json" }]);
  const huge = await send(route("appraise"), JSON.stringify({ filler: "x".repeat(100 * 1024) }));
  assert.deepEqual([huge.status, await huge.json()], [413, { error: "invalid_request", code: "payload_too_large" }]);
});

test("a route only accepts its own kind", async (t) => {
  const { post } = await server(t);
  const result = await post(route("social"), fixture("utterance.request.json"));
  assert.deepEqual([result.status, result.body.code], [400, "kind_mismatch"]);
});

test("invalid provider payloads return 502 with no partial data", async (t) => {
  for (const { file, kind } of manifest.invalid) {
    const invalid = fixture(file);
    assert.equal(invalid.kind, kind);
    const { post } = await server(t, { decide: async () => ({ answers: clone(invalid.response.judgments), model: "m" }) });
    const result = await post(route(kind), fixture(manifest.kinds[kind].request));
    assert.deepEqual([result.status, result.body], [502, { error: "invalid_provider_payload" }], file);
  }
});

test("every violation of the judgment contract is rejected atomically", () => {
  const envelope = validateEnvelope(fixture("appraise.request.json"), "appraise");
  const questions = buildQuestions(envelope);
  const valid = fixture("appraise.response.json").judgments;
  assert.deepEqual(validateJudgments(clone(valid), questions), valid);

  const extra = clone(valid);
  extra.importance.rationale = "ignored";
  extra.remember.surprise = true;
  assert.deepEqual(validateJudgments(extra, questions), valid, "unknown fields never reach the game");

  const violations = [
    (a) => { a.remember.noul = Number.NaN; },
    (a) => { a.remember.noul = 1.01; },
    (a) => { a.remember.noul = "0.9"; },
    (a) => { a.importance.score = -0.1; },
    (a) => { a.importance.score = 4.01; },
    (a) => { a.importance.score = Infinity; },
    (a) => { a.importance.confidence = 2; },
    (a) => { delete a.importance.probabilities; },
    (a) => { a.importance.probabilities = { 0: 1 }; },
    (a) => { a.importance.probabilities["0"] = 0.9; },
    (a) => { a.importance.probabilities["3"] = -0.1; },
    (a) => { a["disposition:player:trust:direction"].choice = "SOMEWHAT_POSITIVE"; },
    (a) => { a["disposition:player:trust:direction"].type = "score"; },
    (a) => { a["disposition:player:trust:direction"].probabilities.UNCHANGED = 0.5; },
    (a) => { a["disposition:stranger:trust:direction"] = a["disposition:player:trust:direction"]; },
    (a) => { delete a.anger; },
    (a) => { a.grief = null; },
    (a) => { a.immediate_danger = { type: "noul", noul: 0.5, choice: "NONE" }; a.immediate_danger.type = "choice"; },
  ];
  for (const [index, violate] of violations.entries()) {
    const bad = clone(valid);
    violate(bad);
    assert.throws(() => validateJudgments(bad, questions), { status: 502, body: { error: "invalid_provider_payload" } }, `violation ${index}`);
  }
  for (const bad of [null, [], "x", 3]) assert.throws(() => validateJudgments(bad, questions), { status: 502 });
});

test("non-object provider results and provider failures are reported without leaking details", async (t) => {
  for (const result of [null, {}, { answers: null }, { answers: [] }]) {
    const { post } = await server(t, { decide: async () => result });
    const response = await post(route("utterance"), fixture("utterance.request.json"));
    assert.deepEqual([response.status, response.body], [502, { error: "invalid_provider_payload" }]);
  }
  const { post } = await server(t, { decide: async () => { throw new Error("secret upstream detail"); } });
  const response = await post(route("utterance"), fixture("utterance.request.json"));
  assert.deepEqual([response.status, response.body], [503, { error: "unavailable" }]);
});

test("a client disconnect aborts the upstream v2 call and frees its permit", async (t) => {
  const queue = createProviderQueue();
  const seen = deferred();
  const { send } = await server(t, { queue, decide: async (_input, { signal }) => {
    seen.resolve(signal);
    return untilAborted(signal);
  } });
  const controller = new AbortController();
  const pending = send(route("social"), fixture("social.request.json"), { signal: controller.signal }).catch((error) => error);
  const signal = await seen.promise;
  assert.equal(signal.aborted, false);
  assert.equal(queue.stats().judgment.active, 1);
  controller.abort();
  assert.equal((await pending).name, "AbortError");
  await waitFor(() => signal.aborted, "upstream abort");
  await waitFor(() => queue.stats().judgment.active === 0, "permit release");
  assert.equal(queue.stats().judgment.aborted, 1);
});

test("abort frees the permit even when the transport never settles", async (t) => {
  const queue = createProviderQueue({ limits: { judgment: 1, text: 1 } });
  const seen = deferred();
  const { send, post } = await server(t, { queue, decide: (_input, { signal }) => {
    if (!seen.settled) { seen.settled = true; seen.resolve(signal); return new Promise(() => {}); }
    return Promise.resolve({ answers: fixture("utterance.response.json").judgments, model: "m" });
  } });
  const controller = new AbortController();
  const hung = send(route("utterance"), fixture("utterance.request.json"), { signal: controller.signal }).catch((error) => error);
  await seen.promise;
  controller.abort();
  await hung;
  await waitFor(() => queue.stats().judgment.active === 0, "permit release");
  const result = await post(route("utterance"), fixture("utterance.request.json"));
  assert.equal(result.status, 200);
});

test("a disconnect while still queued never reaches the provider", async (t) => {
  const queue = createProviderQueue({ limits: { judgment: 1, text: 1 } });
  const gate = deferred();
  const started = deferred();
  let calls = 0;
  const { send } = await server(t, { queue, decide: async () => {
    calls++;
    started.resolve();
    await gate.promise;
    return { answers: fixture("utterance.response.json").judgments, model: "m" };
  } });
  const first = send(route("utterance"), fixture("utterance.request.json"));
  await started.promise;
  const controller = new AbortController();
  const second = send(route("utterance"), fixture("utterance.request.json"), { signal: controller.signal }).catch((error) => error);
  await waitFor(() => queue.stats().judgment.queued === 1, "queued request");
  controller.abort();
  assert.equal((await second).name, "AbortError");
  await waitFor(() => queue.stats().judgment.queued === 0, "queue to drop the aborted job");
  gate.resolve();
  assert.equal((await first).status, 200);
  assert.equal(calls, 1);
  assert.equal(queue.stats().judgment.aborted, 1);
});

test("judgment concurrency is enforced across cognition routes", async (t) => {
  const queue = createProviderQueue({ limits: { judgment: 1, text: 1 } });
  const gates = [];
  let calls = 0;
  const { post } = await server(t, { queue, decide: async (input) => {
    calls++;
    const gate = deferred();
    gates.push(gate);
    await gate.promise;
    return { answers: answers(input.questions), model: "m" };
  } });
  const first = post(route("utterance"), fixture("utterance.request.json"));
  await waitFor(() => calls === 1, "first judgment");
  const second = post(route("utterance"), fixture("utterance.request.json"));
  await waitFor(() => queue.stats().judgment.queued === 1, "second judgment queued");
  assert.equal(calls, 1);
  gates[0].resolve();
  await waitFor(() => calls === 2, "second judgment start");
  gates[1].resolve();
  assert.equal((await first).status, 200);
  assert.equal((await second).status, 200);
  assert.deepEqual(queue.stats().judgment, { active: 0, queued: 0, peak_active: 1, peak_queued: 1, completed: 2, failed: 0, aborted: 0 });
});

test("every provider call receives the upstream budget for its route and no SDK retries", async (t) => {
  const decisions = [], texts = [];
  const chat = fixture(manifest.dialogue.chat.response);
  const { post } = await server(t, {
    decide: async (input, options) => {
      decisions.push({ questions: Object.keys(input.questions), options });
      return { answers: input.questions.supported_0 ? answers(input.questions, { supported_0: 0.95 }) : chat.judgments };
    },
    generate: async (input, options) => {
      texts.push({ format: input.text.format.name, options });
      return { output_text: JSON.stringify(input.text.format.name === "npc_reaction" ? { response: "Keep away!" }
        : { response: chat.response, memory_writes: chat.memory_writes, recalled_memory_ids: chat.recalled_memory_ids }) };
    },
  });
  assert.equal((await post(manifest.dialogue.say.route, fixture(manifest.dialogue.say.request))).status, 200);
  assert.equal((await post(manifest.dialogue.chat.route, fixture(manifest.dialogue.chat.request))).status, 200);

  const judgments = decisions.filter((call) => !call.questions.includes("supported_0"));
  assert.equal(judgments.length, 1);
  for (const { options } of judgments) {
    assert.deepEqual([options.timeout, options.maxRetries], [UPSTREAM_BUDGETS_MS.judgment, 0]);
    assert.ok(options.signal instanceof AbortSignal);
  }
  const grounding = decisions.find((call) => call.questions.includes("supported_0"));
  assert.deepEqual([grounding.options.timeout, grounding.options.maxRetries], [UPSTREAM_BUDGETS_MS.grounding, 0]);
  const byFormat = (name) => texts.filter((call) => call.format === name);
  assert.equal(byFormat("npc_reaction").length, 1);
  for (const { options } of byFormat("npc_reaction")) assert.equal(options.timeout, UPSTREAM_BUDGETS_MS.ambient);
  const dialogueCalls = texts.filter((call) => call.format !== "npc_reaction");
  assert.equal(dialogueCalls.length, 1);
  assert.ok(dialogueCalls[0].options.timeout <= UPSTREAM_BUDGETS_MS.dialogue);
  for (const { options } of texts) assert.ok(options.signal instanceof AbortSignal);
});

test("the exported upstream budgets leave the game a two-second transport margin", () => {
  assert.deepEqual({ ...UPSTREAM_BUDGETS_MS }, { judgment: 8000, dialogue: 30000, grounding: 5000, ambient: 10000 });
  assert.deepEqual({ ...GAME_DEADLINES_MS }, { judgment: 10000, dialogue: 40000, ambient: 12000 });
  assert.equal(GAME_DEADLINE_MARGIN_MS, 2000);
  assert.equal(GAME_DEADLINES_MS.judgment, UPSTREAM_BUDGETS_MS.judgment + GAME_DEADLINE_MARGIN_MS);
  assert.equal(GAME_DEADLINES_MS.ambient, UPSTREAM_BUDGETS_MS.ambient + GAME_DEADLINE_MARGIN_MS);
  assert.ok(GAME_DEADLINES_MS.dialogue >= UPSTREAM_BUDGETS_MS.dialogue + UPSTREAM_BUDGETS_MS.grounding + GAME_DEADLINE_MARGIN_MS);
});
