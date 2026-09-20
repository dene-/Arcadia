import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { createApp } from "../src/app.js";
import { existsSync } from "node:fs";

function answers(questions, overrides = {}) {
  return Object.fromEntries(Object.entries(questions).map(([id, q]) => {
    const value = overrides[id] ?? (q.type === "noul" ? 0.9 : q.type === "score" ? 3 : Object.keys(q.criteria)[0]);
    if (q.type === "noul") return [id, { type: q.type, noul: value }];
    const keys = q.type === "score" ? q.criteria.map((_, i) => String(i)) : Object.keys(q.criteria);
    return [id, { type: q.type, [q.type]: value, confidence: 0.95,
      probabilities: Object.fromEntries(keys.map((key) => [key, key === String(value) ? 1 : 0])) }];
  }));
}
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
    return { status: response.status, body: await response.json() };
  };
}
test("routine selection is restricted to supplied activities and survives ambiguous preferences", async (t) => {
  const post = await server(t, { decide: async ({ state, questions }) => {
    assert.equal(state.current.player_identity.name, "Den");
    assert.deepEqual(Object.keys(questions.activity.criteria), ["PLAN", "VISIT"]);
    return { answers: answers(questions, { activity: "VISIT", linger: 0.2 }) };
  } });
  const result = await post("routine", { ...request(), candidates: [
    { id: "PLAN", description: "Work at the forge." }, { id: "VISIT", description: "Visit a neighbor." },
  ] });
  assert.equal(result.status, 200);
  assert.deepEqual(result.body.policy, { activity: "VISIT", duration_minutes: 35 });
});
test("social decisions can choose a specific account or decline an encounter", async (t) => {
  let engage = 0.9;
  const post = await server(t, { decide: async ({ state, questions }) => {
    assert.equal(state.topics[0].source_name, "Lysa");
    assert.match(questions.topic.instructions, /attributed accounts/);
    return { answers: answers(questions, { engage, topic: "NEWS_0", tone: "CONCERNED" }) };
  } });
  const result = await post("social", request());
  assert.equal(result.status, 200);
  assert.equal(result.body.policy.topic_index, 0);
  assert.equal(result.body.policy.engage, true);
  engage = 0.2;
  assert.equal((await post("social", request())).body.policy.engage, false);
});
test("hearsay affects belief separately from memory and never blames an unidentified player", async (t) => {
  const post = await server(t, { decide: async ({ questions }) => ({ answers: answers(questions, {
    belief: 0.9, remember: 0.1, trust_player: "NEGATIVE", affinity: "UNCHANGED",
  }) }) });
  const body = { ...request(), topic: rumor(), speaker: { id: "mirelle", name: "Mirelle" } };
  const result = await post("listen", body);
  assert.equal(result.body.policy.belief, 0.9);
  assert.equal(result.body.policy.remember, false);
  assert.equal(result.body.policy.trust_player, -0.03);
  body.topic.player_involved = false;
  assert.equal((await post("listen", body)).body.policy.trust_player, 0);
});
test("social speech gets attributed evidence and normalized direct dialogue", async (t) => {
  const post = await server(t, { generate: async ({ instructions, input, store }) => {
    assert.equal(store, false);
    assert.match(instructions, /ORIGINAL observer/);
    assert.equal(JSON.parse(input[0].content).topic.originator_name, "Mirelle");
    return { output_text: JSON.stringify({ response: "She said—‘Den did it.’" }) };
  } });
  const result = await post("say", { ...request(), topic: rumor(), mode: "share" });
  assert.equal(result.status, 200);
  assert.equal(result.body.response, "She said, 'Den did it.'");
});
test("malformed town decisions and service failures fail without fabricated fallback facts", async (t) => {
  const post = await server(t, { decide: async () => ({ answers: {} }),
    generate: async () => ({ status: "incomplete" }) });
  assert.equal((await post("social", request())).status, 503);
  assert.equal((await post("social", { ...request(), topics: Array(5).fill(rumor()) })).status, 400);
  assert.equal((await post("routine", { ...request(), candidates: [] })).status, 400);
  assert.equal((await post("listen", { ...request(), topic: { ...rumor(), hops: 8 } })).status, 400);
  assert.equal((await post("say", { ...request(), topic: rumor(), mode: "share" })).status, 503);
});

test("real town routes, social decisions, audible speech and rumor memory cross HTTP", {
  skip: !process.env.GODOT || !existsSync(new URL("../../../assets/art/world_packs/Minifantasy_TownsProps.png", import.meta.url)),
}, async (t) => {
  const { execFile } = await import("node:child_process");
  const { promisify } = await import("node:util");
  const { mkdtemp, rm } = await import("node:fs/promises");
  const { tmpdir } = await import("node:os");
  const { fileURLToPath } = await import("node:url");
  const directory = await mkdtemp(`${tmpdir()}/arcadia-town-http-`);
  t.after(() => rm(directory, { recursive: true, force: true }));
  const listener = createApp({
    decide: async ({ state, questions }) => {
      assert.equal(state.current.player_identity.name, "Den");
      assert.equal(Object.keys(state.npc.profile.social_traits).length, 5);
      const overrides = questions.activity ? {
        activity: "SOCIAL" in questions.activity.criteria ? "SOCIAL" : "PLAN", linger: 0.9,
      } : questions.engage ? {
        engage: 0.9, topic: state.topics.length ? "NEWS_0" : "SMALL_TALK", another_exchange: 0.1,
      } : { belief: 0.8, remember: 0.9, trust_player: "NEGATIVE", affinity: "POSITIVE" };
      return { answers: answers(questions, overrides) };
    },
    generate: async () => ({ output_text: JSON.stringify({ response: "Did you hear about the fighting?" }) }),
  }).listen(0, "127.0.0.1");
  await once(listener, "listening");
  t.after(() => { listener.closeAllConnections(); listener.close(); });
  const { stdout, stderr } = await promisify(execFile)(process.env.GODOT, [
    "--headless", "--path", fileURLToPath(new URL("../../../", import.meta.url)),
    "--fixed-fps", "60", "--script", "res://tests/integration/town_life_world_test.gd",
    "--log-file", `${directory}/godot.log`,
  ], { timeout: 40000, env: {
    ...process.env, ARCADIA_TOWN_SERVER_URL: `http://127.0.0.1:${listener.address().port}`,
  } });
  assert.match(stdout, /Town life failures: \[\]/);
  assert.doesNotMatch(stderr, /SCRIPT ERROR|Dialog backend unavailable/);
});
