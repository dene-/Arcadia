import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { createApp } from "../src/app.js";
import { VOICE_DIRECTIONS, voiceInstructions } from "../src/npc-voice.js";

const rumor = () => ({ origin_id: "world:1", originator: "mirelle", originator_name: "Mirelle",
  source_id: "lysa", source_name: "Lysa", text: "I saw Den hurt Garrin.", confidence: 0.7,
  hops: 1, chain: ["mirelle", "lysa"], player_involved: true, sense: "sight" });
const request = () => ({ protocol_version: 1, npc: { id: "lysa", profile: { name: "Lysa" } },
  current: { activity: "meal", player_identity: { name: "Den", sex: "Male" } },
  listener: { id: "garrin", name: "Garrin", job: "Blacksmith" }, topics: [rumor()] });
async function server(t, services = {}) {
  const app = createApp({ decide: async ({ questions }) => ({ answers: answers(questions) }),
    generate: async () => ({ output_text: JSON.stringify({ response: "Mirelle told me about Den." }) }), ...services });
  const listener = app.listen(0, "127.0.0.1");
  await once(listener, "listening");
  t.after(() => { listener.closeAllConnections(); listener.close(); });
  return async (kind, body) => {
    const response = await fetch(`http://127.0.0.1:${listener.address().port}/life/${kind}`, {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
    });
    return { status: response.status, body: response.status === 404 ? null : await response.json() };
  };
}
test("social speech gets attributed evidence and normalized direct dialogue", async (t) => {
  const body = { ...request(), topic: rumor(), mode: "share", intent: "share" };
  body.npc.profile.voice = { register: "PRECISE", questions: "RARE" };
  const post = await server(t, { generate: async ({ instructions, input, store }) => {
    assert.equal(store, false);
    assert.match(instructions, /ORIGINAL observer/);
    assert.equal(JSON.parse(input[0].content).topic.originator_name, "Mirelle");
    assert.ok(instructions.endsWith(voiceInstructions(body.npc.profile)));
    assert.ok(instructions.includes(VOICE_DIRECTIONS.register.PRECISE));
    return { output_text: JSON.stringify({ response: "She said—‘Den did it.’" }) };
  } });
  const result = await post("say", body);
  assert.equal(result.status, 200);
  assert.equal(result.body.response, "She said, 'Den did it.'");
});
test("social speech accepts one closed intent and the game's topic or small talk", async (t) => {
  const seen = [];
  const post = await server(t, { generate: async ({ input }, options) => {
    seen.push({ data: JSON.parse(input[0].content), options });
    return { output_text: JSON.stringify({ response: "Fine day." }) };
  }, decide: async () => assert.fail("speech must not call a judgment") });
  const base = { ...request() };
  delete base.topics;
  for (const [intent, topic] of [["share", rumor()], ["reply", rumor()], ["small_talk", null]]) {
    const body = { ...base, topic, mode: intent, intent, tone: "FRIENDLY" };
    const result = await post("say", body);
    assert.equal(result.status, 200, intent);
    assert.equal(result.body.response, "Fine day.");
  }
  // mode is optional; intent alone is the request.
  assert.equal((await post("say", { ...base, topic: null, intent: "small_talk" })).status, 200);
  assert.deepEqual(seen.map(({ data }) => data.intent), ["share", "reply", "small_talk", "small_talk"]);
  assert.equal(seen[0].data.topic.originator_name, "Mirelle");
  assert.equal(seen[0].data.tone, "FRIENDLY");
  for (const { options } of seen) {
    assert.equal(options.timeout, 10000);
    assert.ok(options.signal instanceof AbortSignal);
  }
});
test("the v1 town-life decision routes are gone", async (t) => {
  const post = await server(t, { decide: async () => assert.fail("removed routes must not call inference"),
    generate: async () => assert.fail("removed routes must not call inference") });
  for (const kind of ["routine", "social", "listen"]) assert.equal((await post(kind, request())).status, 404, kind);
});
test("malformed speech requests and service failures fail without fabricated fallback facts", async (t) => {
  let calls = 0;
  const post = await server(t, { generate: async () => { calls++; return { status: "incomplete" }; } });
  const share = { ...request(), topic: rumor(), intent: "share" };
  for (const change of [
    (b) => delete b.intent,
    (b) => (b.intent = "gossip"),
    (b) => (b.intent = "SHARE"),
    (b) => (b.mode = "reply"),
    (b) => (b.topic = null),
    (b) => delete b.topic,
    (b) => (b.topic.hops = 8),
    (b) => (b.listener = {}),
    (b) => (b.protocol_version = 2),
    (b) => (b.npc.id = ""),
  ]) {
    const bad = structuredClone(share);
    change(bad);
    assert.equal((await post("say", bad)).status, 400);
  }
  assert.equal(calls, 0);
  assert.equal((await post("say", share)).status, 503);
  assert.equal(calls, 1);
});
