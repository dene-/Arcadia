import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { PROMPT_VERSION, PROTOCOL_VERSION } from "../src/cognition-contract.js";
import {
  CASE_KINDS,
  checkCase,
  checkCorpus,
  createMockProviders,
  estimate,
  loadCorpus,
  main,
  requiredEnv,
  runCases,
  selectCases,
  summarize,
} from "../evaluate-cognition.js";

const corpus = loadCorpus();
const byId = (id) => corpus.cases.find((caseDef) => caseDef.id === id);

// The evaluator talks to its own in-process app on loopback. Anything else is a provider or network
// call, which is recorded in `calls` and refused.
async function withoutNetwork(run) {
  const realFetch = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (input, init) => {
    const url = String(input?.url ?? input);
    if (new URL(url).hostname === "127.0.0.1") return realFetch(input, init);
    calls.push(url);
    throw new Error("network access is not allowed in this test");
  };
  try {
    return { ...(await run()), calls };
  } finally {
    globalThis.fetch = realFetch;
  }
}

function capture() {
  const chunks = { out: "", err: "" };
  return {
    chunks,
    stdout: { write: (text) => { chunks.out += text; } },
    stderr: { write: (text) => { chunks.err += text; } },
  };
}

async function runMain(argv, options = {}) {
  const io = capture();
  let liveCreated = 0;
  const result = await withoutNetwork(async () => ({
    code: await main(argv, {
      env: {},
      stdout: io.stdout,
      stderr: io.stderr,
      createLive: async () => { liveCreated++; throw new Error("live providers must not be created"); },
      ...options,
    }),
  }));
  return { ...result, ...io.chunks, liveCreated };
}

test("the corpus is versioned and covers every kind with at least 30 cases", () => {
  assert.equal(corpus.protocol_version, PROTOCOL_VERSION);
  assert.equal(corpus.prompt_version, PROMPT_VERSION);
  assert.ok(corpus.cases.length >= 30, `${corpus.cases.length} cases`);
  for (const kind of CASE_KINDS) {
    assert.ok(corpus.cases.some((caseDef) => caseDef.kind === kind), `no case for ${kind}`);
  }
});

test("every case validates against the same contract code the routes use", () => {
  assert.deepEqual(checkCorpus(corpus), []);
  for (const caseDef of corpus.cases) {
    assert.deepEqual(checkCase(caseDef), [], caseDef.id);
    assert.equal(caseDef.request.prompt_version, PROMPT_VERSION, caseDef.id);
  }
});

test("every primary case has a counterexample of the same kind", () => {
  const pairs = Object.groupBy(corpus.cases.filter((caseDef) => caseDef.pair), (caseDef) => caseDef.pair.id);
  assert.ok(Object.keys(pairs).length >= 15);
  for (const [id, members] of Object.entries(pairs)) {
    assert.deepEqual(members.map((member) => member.pair.role).sort(), ["counterexample", "primary"], id);
  }
  for (const caseDef of corpus.cases) assert.ok(caseDef.pair, `${caseDef.id} has no pair`);
});

test("the corpus labels the behaviors the plan names", () => {
  const tags = new Set(corpus.cases.flatMap((caseDef) => caseDef.tags));
  for (const tag of ["greeting", "injury", "uncertain_sound", "family_loss", "conflicting_rumor", "guard_warning", "surrender", "workload", "fatigue", "farewell", "promise"]) {
    assert.ok(tags.has(tag), `no case tagged ${tag}`);
  }
  assert.ok(byId("appraise.armed_attack_visible").labels.judgments.immediate_danger.min >= 0.7);
  assert.ok(byId("appraise.noon_bell").labels.judgments.remember.max <= 0.3);
  assert.deepEqual(byId("listen.messenger_brings_bad_news").labels.judgments["disposition:mirelle:trust:direction"], { not: ["NEGATIVE"] });
  assert.deepEqual(byId("utterance.quiet_work_no_speech").labels.judgments.intent, { one_of: ["silence"] });
  assert.ok(byId("select_goal.hungry_resident_at_noon").labels.orderings.length);
});

test("the mock run passes every case through the real routes", async () => {
  const results = await runCases(corpus.cases, createMockProviders());
  assert.equal(results.length, corpus.cases.length);
  assert.deepEqual(results.filter((result) => !result.pass).map((result) => [result.id, result.failures]), []);
  const summary = summarize(results);
  assert.equal(summary.failed, 0);
  assert.equal(summary.passed, corpus.cases.length);
  for (const kind of CASE_KINDS) assert.equal(summary.by_kind[kind].passed, summary.by_kind[kind].total, kind);
});

test("--mock prints a per-kind pass rate and exits 0", async () => {
  const run = await runMain(["--mock"]);
  assert.equal(run.code, 0, run.out + run.err);
  assert.equal(run.calls.length, 0);
  for (const kind of CASE_KINDS) assert.match(run.out, new RegExp(`${kind}\\s+\\d+\\s+\\d+\\s+100\\.0%`));
  assert.match(run.out, /all\s+\d+\s+\d+\s+100\.0%/);
});

test("a deliberately wrong judgment is detected as a label failure", async () => {
  const tamper = {
    answers(caseDef, answers) {
      if (caseDef.id !== "appraise.armed_attack_visible") return answers;
      return { ...answers, immediate_danger: { type: "noul", noul: 0.05 } };
    },
  };
  const results = await runCases([byId("appraise.armed_attack_visible"), byId("appraise.noon_bell")], createMockProviders({ tamper }));
  const [attack, bell] = results;
  assert.equal(attack.pass, false);
  assert.match(attack.failures.join("\n"), /immediate_danger/);
  assert.equal(bell.pass, true);
  assert.equal(summarize(results).failed, 1);
});

test("a wrong choice and a violated ordering are detected", async () => {
  const wrongChoice = {
    answers(caseDef, answers) {
      const intent = answers.intent;
      return { ...answers, intent: { ...intent, choice: "warn" } };
    },
  };
  const [silent] = await runCases([byId("utterance.quiet_work_no_speech")], createMockProviders({ tamper: wrongChoice }));
  assert.equal(silent.pass, false);
  assert.match(silent.failures.join("\n"), /intent/);

  const flipped = {
    answers(caseDef, answers) {
      const eat = answers["suitability:EAT_AT_HOME"];
      const work = answers["suitability:WORK_FORGE"];
      return { ...answers, "suitability:EAT_AT_HOME": work, "suitability:WORK_FORGE": eat };
    },
  };
  const [goal] = await runCases([byId("select_goal.hungry_resident_at_noon")], createMockProviders({ tamper: flipped }));
  assert.equal(goal.pass, false);
});

test("a reply that breaks its text labels is detected", async () => {
  const tamper = { line: (caseDef, line) => (caseDef.id === "dialogue_chat.farewell_thanks" ? "Take care. Anything else?" : line) };
  const [farewell] = await runCases([byId("dialogue_chat.farewell_thanks")], createMockProviders({ tamper }));
  assert.equal(farewell.pass, false);
  assert.match(farewell.failures.join("\n"), /forbidden|matches/i);

  const longSay = { line: (caseDef, line) => (caseDef.id === "dialogue_say.small_talk_spare_voice" ? "Busy day with iron and coals and orders all morning." : line) };
  const [say] = await runCases([byId("dialogue_say.small_talk_spare_voice")], createMockProviders({ tamper: longSay }));
  assert.equal(say.pass, false);
});

test("--mock exits 1 when a label fails", async () => {
  const run = await runMain(["--mock", "--case", "appraise.armed_attack_visible"], {
    createMock: () => createMockProviders({
      tamper: { answers: (caseDef, answers) => ({ ...answers, immediate_danger: { type: "noul", noul: 0 } }) },
    }),
  });
  assert.equal(run.code, 1);
  assert.match(run.out, /FAIL appraise\.armed_attack_visible/);
});

test("--live without API keys exits non-zero without creating providers or touching the network", async () => {
  const run = await runMain(["--live", "--limit", "5", "--yes"]);
  assert.notEqual(run.code, 0);
  assert.match(run.err, /missing TYPESAFE_API_KEY/);
  assert.equal(run.liveCreated, 0);
  assert.equal(run.calls.length, 0);
});

test("--live names every missing key for text cases", async () => {
  const run = await runMain(["--live", "--limit", "52", "--yes"], { env: { TYPESAFE_API_KEY: "k" } });
  assert.notEqual(run.code, 0);
  assert.match(run.err, /OPENAI_API_KEY/);
  assert.match(run.err, /OPENAI_MODEL/);
  assert.equal(run.liveCreated, 0);
});

test("--live without --limit refuses", async () => {
  const env = { TYPESAFE_API_KEY: "k", OPENAI_API_KEY: "k", OPENAI_MODEL: "m" };
  for (const argv of [["--live"], ["--live", "--yes"]]) {
    const run = await runMain(argv, { env });
    assert.notEqual(run.code, 0, argv.join(" "));
    assert.match(run.err, /--limit/);
    assert.equal(run.liveCreated, 0);
    assert.equal(run.calls.length, 0);
  }
  const invalid = await runMain(["--live", "--limit", "0", "--yes"], { env });
  assert.notEqual(invalid.code, 0);
  assert.equal(invalid.liveCreated, 0);
});

test("--live prints the estimate and refuses to spend without --yes", async () => {
  const env = { TYPESAFE_API_KEY: "k", OPENAI_API_KEY: "k", OPENAI_MODEL: "m" };
  const run = await runMain(["--live", "--limit", "7"], { env });
  assert.notEqual(run.code, 0);
  assert.match(run.out, /Estimated provider requests/);
  assert.match(run.out, /7 of 52 cases/);
  assert.match(run.err, /--yes/);
  assert.equal(run.liveCreated, 0);
  assert.equal(run.calls.length, 0);
});

test("--live with --limit samples every kind first", () => {
  const selected = selectCases(corpus.cases, { limit: CASE_KINDS.length });
  assert.deepEqual([...new Set(selected.map((caseDef) => caseDef.kind))].sort(), [...CASE_KINDS].sort());
  assert.equal(selectCases(corpus.cases, { limit: 3 }).length, 3);
});

test("the estimate counts judgment and text requests and the required keys", () => {
  const judgmentOnly = corpus.cases.filter((caseDef) => !caseDef.kind.startsWith("dialogue_"));
  assert.deepEqual(requiredEnv(judgmentOnly), ["TYPESAFE_API_KEY"]);
  assert.deepEqual(requiredEnv(corpus.cases), ["TYPESAFE_API_KEY", "OPENAI_API_KEY", "OPENAI_MODEL"]);
  const budget = estimate(corpus.cases);
  assert.ok(budget.judgment[0] > 0 && budget.text[0] > 0 && budget.worstMs > 0);
});

test("a confirmed live run stores model ids, prompt_version and timestamp under the results directory", async () => {
  const resultsDir = mkdtempSync(join(tmpdir(), "cognition-eval-"));
  try {
    const env = { TYPESAFE_API_KEY: "k", OPENAI_API_KEY: "k", OPENAI_MODEL: "m" };
    const now = () => new Date("2026-10-14T08:00:00.000Z");
    const run = await runMain(["--live", "--limit", "2", "--yes"], {
      env,
      resultsDir,
      now,
      // The live evaluator runs unchanged; only the provider is a local fake.
      createLive: async () => ({ ...createMockProviders(), models: { judgment: "fake-jev", text: "fake-text" } }),
    });
    assert.equal(run.code, 0, run.out + run.err);
    assert.equal(run.calls.length, 0);
    const [file] = readdirSync(resultsDir);
    assert.equal(file, "2026-10-14T08-00-00.000Z-live.json");
    const stored = JSON.parse(readFileSync(join(resultsDir, file), "utf8"));
    assert.equal(stored.mode, "live");
    assert.equal(stored.prompt_version, PROMPT_VERSION);
    assert.equal(stored.timestamp, "2026-10-14T08:00:00.000Z");
    assert.deepEqual(stored.models, { judgment: "fake-jev", text: "fake-text" });
    assert.equal(stored.cases.length, 2);
    assert.equal(stored.summary.total, 2);
  } finally {
    rmSync(resultsDir, { recursive: true, force: true });
  }
});

test("live results directory is gitignored", () => {
  const ignore = readFileSync(new URL("../.gitignore", import.meta.url), "utf8");
  assert.match(ignore, /^evaluation\/results\/$/m);
});

test("conflicting arguments and unknown ids are refused", async () => {
  for (const argv of [["--mock", "--live", "--limit", "1"], ["--bogus"], ["--mock", "--case", "nope.nothing"], ["--mock", "--kind", "nonsense"]]) {
    const run = await runMain(argv);
    assert.equal(run.code, 2, argv.join(" "));
  }
});
