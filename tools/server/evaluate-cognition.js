// Labeled evaluation of the cognition and dialogue contracts.
//
//   node evaluate-cognition.js [--mock] [--kind k] [--case id] [--limit N] [--out file]
//   node evaluate-cognition.js --live --limit N [--yes] [--kind k] [--case id] [--out file]
//
// The default and `--mock` run is offline: a deterministic fake provider answers every case with
// its labeled expectation and the cases go through the real v2 routes in-process. `--live` is the
// only mode that can spend provider quota; see the checks in `main`.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { once } from "node:events";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createApp } from "./src/app.js";
import {
  COGNITION_KINDS,
  ContractError,
  PROMPT_VERSION,
  PROTOCOL_VERSION,
  buildQuestions,
  validateEnvelope,
} from "./src/cognition-contract.js";
import { COGNITION_ROUTES } from "./src/cognition-routes.js";
import { CHAT_QUESTIONS, validateChat, validateSay } from "./src/dialogue-contract.js";
import { speechPolicy } from "./src/npc-decisions.js";
import { UPSTREAM_BUDGETS_MS } from "./src/upstream.js";

export const CASE_KINDS = Object.freeze([...COGNITION_KINDS, "dialogue_chat", "dialogue_say"]);
export const CASES_PATH = fileURLToPath(new URL("./evaluation/cognition-cases.json", import.meta.url));
export const RESULTS_DIR = fileURLToPath(new URL("./evaluation/results/", import.meta.url));
const ENV_PATH = fileURLToPath(new URL("./.env", import.meta.url));
const EXIT_REFUSED = 2;

const ROUTES = Object.freeze({
  ...Object.fromEntries(COGNITION_KINDS.map((kind) => [kind, `/v2/cognition${COGNITION_ROUTES[kind]}`])),
  dialogue_chat: "/v2/dialogue/chat",
  dialogue_say: "/v2/dialogue/say",
});
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const SPEC_KEYS = { noul: ["min", "max"], score: ["min", "max"], choice: ["one_of", "not"] };
const RESPONSE_KEYS = ["reference", "max_words", "min_words", "forbid_patterns", "require_any"];

// ---------------------------------------------------------------------------
// Corpus
// ---------------------------------------------------------------------------

export function loadCorpus(path = CASES_PATH) {
  return JSON.parse(readFileSync(path, "utf8"));
}

// The question set the route will ask for this case, or null when the kind asks none (say).
export function questionsFor(caseDef) {
  if (caseDef.kind === "dialogue_chat") return CHAT_QUESTIONS;
  if (caseDef.kind === "dialogue_say") return null;
  return buildQuestions(validateEnvelope(caseDef.request, caseDef.kind));
}

function checkSpec(id, question, spec) {
  if (!isObject(spec)) return [`${id}: spec must be an object`];
  const problems = [];
  const allowed = SPEC_KEYS[question.type];
  for (const key of Object.keys(spec)) if (!allowed.includes(key)) problems.push(`${id}: unknown key "${key}" for a ${question.type}`);
  if (question.type === "choice") {
    const options = Object.keys(question.criteria);
    if (Number(spec.one_of !== undefined) + Number(spec.not !== undefined) !== 1) problems.push(`${id}: choice needs exactly one of one_of or not`);
    for (const key of ["one_of", "not"]) {
      if (spec[key] === undefined) continue;
      if (!Array.isArray(spec[key]) || !spec[key].length || !spec[key].every((option) => options.includes(option)))
        problems.push(`${id}: ${key} must list options of the question (${options.join(", ")})`);
    }
    if (Array.isArray(spec.not) && spec.not.length >= options.length) problems.push(`${id}: not excludes every option`);
    return problems;
  }
  const top = question.type === "noul" ? 1 : question.criteria.length - 1;
  if (spec.min === undefined && spec.max === undefined) problems.push(`${id}: needs min or max`);
  for (const key of ["min", "max"])
    if (spec[key] !== undefined && !(typeof spec[key] === "number" && spec[key] >= 0 && spec[key] <= top))
      problems.push(`${id}: ${key} must be a number within 0..${top}`);
  if (spec.min !== undefined && spec.max !== undefined && spec.min > spec.max) problems.push(`${id}: min exceeds max`);
  return problems;
}

function checkResponse(text, spec) {
  const failures = [];
  const words = text.trim().split(/\s+/u).length;
  if (spec.max_words !== undefined && words > spec.max_words) failures.push(`${words} words exceeds max_words ${spec.max_words}`);
  if (spec.min_words !== undefined && words < spec.min_words) failures.push(`${words} words below min_words ${spec.min_words}`);
  for (const pattern of spec.forbid_patterns ?? [])
    if (new RegExp(pattern, "iu").test(text)) failures.push(`matches forbidden /${pattern}/`);
  if (spec.require_any?.length && !spec.require_any.some((pattern) => new RegExp(pattern, "iu").test(text)))
    failures.push(`matches none of ${spec.require_any.map((pattern) => `/${pattern}/`).join(", ")}`);
  return failures;
}

function regexProblems(patterns, where) {
  if (patterns === undefined) return [];
  if (!Array.isArray(patterns) || !patterns.length) return [`${where} must be a non-empty array`];
  return patterns.flatMap((pattern) => {
    try {
      new RegExp(pattern, "iu");
      return [];
    } catch {
      return [`${where} has an invalid pattern ${JSON.stringify(pattern)}`];
    }
  });
}

// Problems with one case: the request is validated by the contract code the routes use, and every
// label must name a real question and a value that question can produce.
export function checkCase(caseDef) {
  const problems = [];
  if (!isObject(caseDef) || typeof caseDef.id !== "string" || !caseDef.id) return ["case needs a string id"];
  if (!CASE_KINDS.includes(caseDef.kind)) return [`unknown kind "${caseDef.kind}"`];
  if (!isObject(caseDef.request) || !isObject(caseDef.labels)) return ["case needs request and labels objects"];
  try {
    if (caseDef.kind === "dialogue_chat") validateChat(caseDef.request);
    else if (caseDef.kind === "dialogue_say") validateSay(caseDef.request);
    else validateEnvelope(caseDef.request, caseDef.kind);
  } catch (error) {
    if (!(error instanceof ContractError)) throw error;
    return [`request fails the contract: ${error.body.code ?? error.body.error}`];
  }
  const labels = caseDef.labels;
  const text = caseDef.kind === "dialogue_chat" || caseDef.kind === "dialogue_say";
  const questions = questionsFor(caseDef);
  const allowed = text ? ["judgments", "orderings", "policy", "response"] : ["judgments", "orderings"];
  if (caseDef.kind === "dialogue_say") allowed.splice(0, 3);
  for (const key of Object.keys(labels)) if (!allowed.includes(key)) problems.push(`labels.${key} is not used by ${caseDef.kind}`);

  if (questions) {
    const specs = labels.judgments;
    if (!isObject(specs) || !Object.keys(specs).length) problems.push("labels.judgments must label at least one question");
    for (const [id, spec] of Object.entries(specs ?? {})) {
      if (!questions[id]) problems.push(`labels.judgments names unknown question "${id}"`);
      else problems.push(...checkSpec(id, questions[id], spec));
    }
    for (const [index, order] of (labels.orderings ?? []).entries()) {
      const where = `labels.orderings[${index}]`;
      for (const key of ["higher", "lower"])
        if (questions[order?.[key]]?.type !== "score") problems.push(`${where}.${key} must name a score question`);
      if (order?.margin !== undefined && !(typeof order.margin === "number" && order.margin >= 0)) problems.push(`${where}.margin must be a non-negative number`);
    }
  }
  if (labels.policy !== undefined) {
    if (caseDef.kind !== "dialogue_chat") problems.push("labels.policy applies to dialogue_chat only");
    else for (const [key, value] of Object.entries(labels.policy)) {
      if (!["remember", "retrieve", "update_belief", "end_conversation", "interaction_intent", "response_mode"].includes(key)
        || !["boolean", "string"].includes(typeof value)) problems.push(`labels.policy.${key} is not a comparable policy field`);
    }
  }
  if (text) {
    const response = labels.response;
    if (!isObject(response) || typeof response.reference !== "string" || !response.reference.trim()) {
      problems.push("labels.response.reference must be a known-good line");
    } else {
      for (const key of Object.keys(response)) if (!RESPONSE_KEYS.includes(key)) problems.push(`labels.response.${key} is unknown`);
      problems.push(...regexProblems(response.forbid_patterns, "labels.response.forbid_patterns"));
      problems.push(...regexProblems(response.require_any, "labels.response.require_any"));
      if (!problems.length)
        for (const failure of checkResponse(response.reference, response)) problems.push(`reference line violates its own labels: ${failure}`);
    }
  }
  return problems;
}

// Corpus-level problems: version, unique ids, every case, and paired counterexamples.
export function checkCorpus(corpus) {
  const problems = [];
  if (!isObject(corpus) || !Array.isArray(corpus.cases)) return ["corpus needs a cases array"];
  if (corpus.prompt_version !== PROMPT_VERSION) problems.push(`prompt_version ${corpus.prompt_version} is not ${PROMPT_VERSION}`);
  if (corpus.protocol_version !== PROTOCOL_VERSION) problems.push(`protocol_version ${corpus.protocol_version} is not ${PROTOCOL_VERSION}`);
  const ids = new Set();
  const pairs = new Map();
  for (const caseDef of corpus.cases) {
    const id = caseDef?.id;
    if (ids.has(id)) problems.push(`duplicate case id ${id}`);
    ids.add(id);
    for (const problem of checkCase(caseDef)) problems.push(`${id}: ${problem}`);
    if (isObject(caseDef) && caseDef.request?.prompt_version !== PROMPT_VERSION) problems.push(`${id}: request prompt_version is not ${PROMPT_VERSION}`);
    const pair = caseDef?.pair;
    if (pair !== undefined) {
      if (!isObject(pair) || typeof pair.id !== "string" || !["primary", "counterexample"].includes(pair.role)) {
        problems.push(`${id}: pair needs {id, role: primary|counterexample}`);
        continue;
      }
      const members = pairs.get(pair.id) ?? [];
      members.push(caseDef);
      pairs.set(pair.id, members);
    }
  }
  for (const [id, members] of pairs) {
    const roles = members.map((member) => member.pair.role).sort().join();
    if (roles !== "counterexample,primary" || new Set(members.map((member) => member.kind)).size !== 1)
      problems.push(`pair ${id} needs one primary and one counterexample of the same kind`);
  }
  return problems;
}

// Round-robin by kind in corpus order, so a small limit still samples every kind.
export function selectCases(cases, { kinds = [], ids = [], limit } = {}) {
  let selected = cases;
  if (kinds.length) selected = selected.filter((caseDef) => kinds.includes(caseDef.kind));
  if (ids.length) selected = selected.filter((caseDef) => ids.includes(caseDef.id));
  if (limit === undefined || limit >= selected.length) return selected;
  const queues = CASE_KINDS.map((kind) => selected.filter((caseDef) => caseDef.kind === kind)).filter((queue) => queue.length);
  const picked = [];
  for (let round = 0; picked.length < limit; round++)
    for (const queue of queues) if (round < queue.length && picked.length < limit) picked.push(queue[round]);
  return selected.filter((caseDef) => picked.includes(caseDef));
}

// ---------------------------------------------------------------------------
// Scoring
// ---------------------------------------------------------------------------

function judgmentFailures(id, spec, judgment) {
  if (!judgment) return [`${id}: no judgment returned`];
  if (judgment.type === "choice") {
    if (spec.one_of && !spec.one_of.includes(judgment.choice)) return [`${id}: chose ${judgment.choice}, expected one of ${spec.one_of.join("/")}`];
    if (spec.not?.includes(judgment.choice)) return [`${id}: chose ${judgment.choice}, which the label excludes`];
    return [];
  }
  const value = judgment.type === "noul" ? judgment.noul : judgment.score;
  const failures = [];
  if (spec.min !== undefined && value < spec.min) failures.push(`${id}: ${value} below min ${spec.min}`);
  if (spec.max !== undefined && value > spec.max) failures.push(`${id}: ${value} above max ${spec.max}`);
  return failures;
}

// Scores one outcome {status, body, error?} against the case labels. Never throws on a bad answer.
export function scoreCase(caseDef, outcome) {
  if (outcome.status !== 200) {
    const detail = [outcome.body?.error, outcome.body?.code].filter(Boolean).join(" ") || outcome.error || "no answer";
    return { pass: false, failures: [`route answered ${outcome.status}: ${detail}`] };
  }
  const { labels } = caseDef;
  const failures = [];
  const judgments = outcome.body.judgments ?? {};
  for (const [id, spec] of Object.entries(labels.judgments ?? {})) failures.push(...judgmentFailures(id, spec, judgments[id]));
  for (const { higher, lower, margin = 0 } of labels.orderings ?? []) {
    const a = judgments[higher]?.score;
    const b = judgments[lower]?.score;
    if (typeof a !== "number" || typeof b !== "number") failures.push(`ordering ${higher} > ${lower}: score missing`);
    else if (a - b < margin) failures.push(`ordering ${higher} (${a}) must exceed ${lower} (${b}) by ${margin}`);
  }
  if (labels.policy) {
    let policy;
    try {
      policy = speechPolicy(judgments);
    } catch {
      failures.push("policy could not be derived from the judgments");
    }
    for (const [key, expected] of Object.entries(labels.policy ?? {}))
      if (policy && policy[key] !== expected) failures.push(`policy.${key} is ${policy[key]}, expected ${expected}`);
  }
  if (labels.response) {
    const line = outcome.body.response;
    if (typeof line !== "string") failures.push("no response line");
    else failures.push(...checkResponse(line, labels.response).map((failure) => `response "${line}" ${failure}`));
  }
  return { pass: failures.length === 0, failures };
}

// ---------------------------------------------------------------------------
// Mock provider: answers with the labeled expectation
// ---------------------------------------------------------------------------

const middle = (low, high) => Number(((low + high) / 2).toFixed(4));
const UNLABELED_NOUL = 0.1;

function mockAnswer(question, spec) {
  if (question.type === "noul") {
    return { type: "noul", noul: spec ? middle(spec.min ?? 0, spec.max ?? 1) : UNLABELED_NOUL };
  }
  if (question.type === "score") {
    const top = question.criteria.length - 1;
    const score = spec ? middle(spec.min ?? 0, spec.max ?? top) : 0;
    const low = Math.floor(score);
    const high = Math.ceil(score);
    const probabilities = Object.fromEntries(question.criteria.map((_, level) => [String(level), 0]));
    probabilities[String(low)] += high === low ? 1 : high - score;
    if (high !== low) probabilities[String(high)] += score - low;
    return { type: "score", score, confidence: 0.9, probabilities };
  }
  const options = Object.keys(question.criteria);
  const fallback = options.includes("UNCHANGED") ? "UNCHANGED" : options[0];
  const allowed = (option) => (spec?.one_of ? spec.one_of.includes(option) : !spec?.not?.includes(option));
  const choice = spec?.one_of?.[0] ?? (allowed(fallback) ? fallback : options.find(allowed));
  const rest = options.length - 1;
  return {
    type: "choice",
    choice,
    confidence: 0.9,
    probabilities: Object.fromEntries(options.map((option) => [option, option === choice ? (rest ? 0.9 : 1) : 0.1 / rest])),
  };
}

// `tamper.answers(caseDef, answers)` and `tamper.line(caseDef, line)` replace the labeled answer;
// the tests use them to prove that a wrong provider answer is caught.
export function createMockProviders({ tamper = {} } = {}) {
  let current;
  return {
    models: { judgment: "mock-jev", text: "mock-text" },
    use(caseDef) {
      current = caseDef;
    },
    async decide({ questions }) {
      const specs = current.labels.judgments ?? {};
      const answers = Object.fromEntries(Object.entries(questions).map(([id, question]) => [id, mockAnswer(question, specs[id])]));
      return { answers: tamper.answers?.(current, answers) ?? answers, model: "mock-jev" };
    },
    async generate(request) {
      const line = tamper.line?.(current, current.labels.response.reference) ?? current.labels.response.reference;
      const chat = request.text?.format?.name === "npc_dialogue";
      return {
        status: "completed",
        output_text: JSON.stringify(chat ? { response: line, memory_writes: [], recalled_memory_ids: [] } : { response: line }),
      };
    },
  };
}

// ---------------------------------------------------------------------------
// Live provider: the same SDK calls as index.js
// ---------------------------------------------------------------------------

export function requiredEnv(cases) {
  const needsText = cases.some((caseDef) => caseDef.kind === "dialogue_chat" || caseDef.kind === "dialogue_say");
  return ["TYPESAFE_API_KEY", ...(needsText ? ["OPENAI_API_KEY", "OPENAI_MODEL"] : [])];
}

export async function createLiveProviders(env) {
  const [{ TypeSafeClient }, { default: OpenAI }] = await Promise.all([import("@typesafe-ai/sdk"), import("openai")]);
  const judgmentModel = env.TYPESAFE_MODEL || "jev-latest";
  return {
    models: { judgment: judgmentModel, text: env.OPENAI_MODEL || "" },
    use() {},
    decide: async (request, options = {}) => new TypeSafeClient({ apiKey: env.TYPESAFE_API_KEY }).systemOne(
      { ...request, model: judgmentModel },
      { signal: options.signal, timeout: options.timeout ?? UPSTREAM_BUDGETS_MS.judgment, retry: { maxRetries: options.maxRetries ?? 0 } },
    ),
    generate: async (request, options = {}) => new OpenAI({ apiKey: env.OPENAI_API_KEY, maxRetries: 0 }).responses.create(
      { ...request, model: env.OPENAI_MODEL },
      { signal: options.signal, timeout: options.timeout ?? UPSTREAM_BUDGETS_MS.dialogue },
    ),
  };
}

// Provider requests one case costs, and the longest it can run if every upstream call uses its budget.
export function estimateCase(caseDef) {
  if (caseDef.kind === "dialogue_say") return { judgment: [0, 0], text: [1, 1], worstMs: UPSTREAM_BUDGETS_MS.ambient };
  if (caseDef.kind === "dialogue_chat") {
    // One judgment call, one generation, and a grounding call only when the reply proposes memories.
    return {
      judgment: [1, 2],
      text: [1, 1],
      worstMs: UPSTREAM_BUDGETS_MS.judgment + UPSTREAM_BUDGETS_MS.dialogue + UPSTREAM_BUDGETS_MS.grounding,
    };
  }
  return { judgment: [1, 1], text: [0, 0], worstMs: UPSTREAM_BUDGETS_MS.judgment };
}

export function estimate(cases) {
  const total = { judgment: [0, 0], text: [0, 0], worstMs: 0 };
  for (const caseDef of cases) {
    const each = estimateCase(caseDef);
    for (const pool of ["judgment", "text"]) {
      total[pool][0] += each[pool][0];
      total[pool][1] += each[pool][1];
    }
    total.worstMs += each.worstMs;
  }
  return total;
}

// ---------------------------------------------------------------------------
// Execution
// ---------------------------------------------------------------------------

const POST_TIMEOUT_MS = 90_000;

// Runs the cases one at a time through the real routes of an in-process app backed by `providers`.
export async function runCases(cases, providers) {
  const app = createApp({ decide: providers.decide, generate: providers.generate });
  const listener = app.listen(0, "127.0.0.1");
  await once(listener, "listening");
  const base = `http://127.0.0.1:${listener.address().port}`;
  const results = [];
  try {
    for (const caseDef of cases) {
      providers.use(caseDef);
      const started = performance.now();
      let outcome;
      try {
        const response = await fetch(base + ROUTES[caseDef.kind], {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(caseDef.request),
          signal: AbortSignal.timeout(POST_TIMEOUT_MS),
        });
        outcome = { status: response.status, body: await response.json() };
      } catch (error) {
        outcome = { status: 0, body: null, error: error?.name || "request failed" };
      }
      const latencyMs = Math.round(performance.now() - started);
      const { pass, failures } = scoreCase(caseDef, outcome);
      results.push({
        id: caseDef.id,
        kind: caseDef.kind,
        pass,
        failures,
        status: outcome.status,
        latency_ms: latencyMs,
        model: outcome.body?.model ?? null,
        output: outcome.body,
      });
    }
  } finally {
    listener.closeAllConnections();
    listener.close();
  }
  return results;
}

const percentile = (sorted, p) => (sorted.length ? sorted[Math.max(0, Math.ceil(p * sorted.length) - 1)] : 0);

function meanConfidence(results) {
  const values = results.flatMap((result) => Object.values(result.output?.judgments ?? {}))
    .filter((judgment) => typeof judgment.confidence === "number").map((judgment) => judgment.confidence);
  return values.length ? values.reduce((a, b) => a + b, 0) / values.length : null;
}

export function summarize(results) {
  const byKind = {};
  for (const kind of CASE_KINDS) {
    const own = results.filter((result) => result.kind === kind);
    if (!own.length) continue;
    const latencies = own.map((result) => result.latency_ms).sort((a, b) => a - b);
    byKind[kind] = {
      total: own.length,
      passed: own.filter((result) => result.pass).length,
      latency_p50_ms: percentile(latencies, 0.5),
      latency_p95_ms: percentile(latencies, 0.95),
      mean_confidence: meanConfidence(own),
    };
  }
  const passed = results.filter((result) => result.pass).length;
  return { total: results.length, passed, failed: results.length - passed, by_kind: byKind };
}

function formatSummary(summary) {
  const rows = [["kind", "pass", "total", "rate", "p50 ms", "p95 ms", "mean conf"]];
  const row = (name, s) => [name, String(s.passed), String(s.total), `${((100 * s.passed) / s.total).toFixed(1)}%`,
    s.latency_p50_ms === undefined ? "" : String(s.latency_p50_ms), s.latency_p95_ms === undefined ? "" : String(s.latency_p95_ms),
    s.mean_confidence == null ? "-" : s.mean_confidence.toFixed(2)];
  for (const [kind, s] of Object.entries(summary.by_kind)) rows.push(row(kind, s));
  rows.push(row("all", summary));
  const widths = rows[0].map((_, column) => Math.max(...rows.map((cells) => cells[column].length)));
  return rows.map((cells) => cells.map((cell, column) => cell.padEnd(widths[column])).join("  ").trimEnd()).join("\n");
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const options = { mock: false, live: false, yes: false, kinds: [], ids: [], limit: undefined, out: undefined };
  const value = (index, flag) => {
    if (index + 1 >= argv.length || argv[index + 1].startsWith("--")) throw new Error(`${flag} needs a value`);
    return argv[index + 1];
  };
  for (let index = 0; index < argv.length; index++) {
    const flag = argv[index];
    if (flag === "--mock") options.mock = true;
    else if (flag === "--live") options.live = true;
    else if (flag === "--yes") options.yes = true;
    else if (flag === "--kind") options.kinds.push(...value(index++, flag).split(","));
    else if (flag === "--case") options.ids.push(...value(index++, flag).split(","));
    else if (flag === "--out") options.out = value(index++, flag);
    else if (flag === "--limit") {
      const raw = value(index++, flag);
      if (!/^[1-9]\d*$/.test(raw)) throw new Error("--limit must be a positive integer");
      options.limit = Number(raw);
    } else throw new Error(`unknown argument ${flag}`);
  }
  if (options.mock && options.live) throw new Error("--mock and --live are exclusive");
  for (const kind of options.kinds) if (!CASE_KINDS.includes(kind)) throw new Error(`unknown kind "${kind}" (${CASE_KINDS.join(", ")})`);
  return options;
}

const range = ([low, high]) => (low === high ? String(low) : `${low}-${high}`);

// Returns the process exit code: 0 all labels passed, 1 a label failed, 2 refused or invalid usage.
// Options (all injectable for tests): env, stdout, stderr, casesPath, resultsDir, now, createMock, createLive.
export async function main(argv, {
  env = process.env,
  stdout = process.stdout,
  stderr = process.stderr,
  casesPath = CASES_PATH,
  resultsDir = RESULTS_DIR,
  now = () => new Date(),
  createMock = createMockProviders,
  createLive = createLiveProviders,
} = {}) {
  const out = (line = "") => stdout.write(`${line}\n`);
  const refuse = (message) => {
    stderr.write(`${message}\n`);
    return EXIT_REFUSED;
  };
  let options;
  try {
    options = parseArgs(argv);
  } catch (error) {
    return refuse(`${error.message}\nusage: evaluate-cognition.js [--mock | --live --limit N [--yes]] [--kind k] [--case id] [--out file]`);
  }
  // Live mode is refused before anything else can reach a provider.
  if (options.live && options.limit === undefined)
    return refuse("Refusing --live: pass an explicit --limit N so the spend is bounded.");
  const corpus = loadCorpus(casesPath);
  const problems = checkCorpus(corpus);
  if (problems.length) return refuse(`The corpus is invalid:\n${problems.map((problem) => `  ${problem}`).join("\n")}`);
  const known = new Set(corpus.cases.map((caseDef) => caseDef.id));
  const unknown = options.ids.filter((id) => !known.has(id));
  if (unknown.length) return refuse(`Unknown case id: ${unknown.join(", ")}`);
  const cases = selectCases(corpus.cases, options);
  if (!cases.length) return refuse("No case matches the selection.");

  let providers;
  if (options.live) {
    if (env === process.env) (await import("dotenv")).default.config({ path: ENV_PATH });
    const missing = requiredEnv(cases).filter((name) => !env[name]);
    if (missing.length) return refuse(`Refusing --live: missing ${missing.join(", ")}. Set them in tools/server/.env or the environment.`);
    const counts = Object.entries(Object.groupBy(cases, (caseDef) => caseDef.kind)).map(([kind, own]) => `${kind} ${own.length}`);
    const budget = estimate(cases);
    out(`Live evaluation: ${cases.length} of ${corpus.cases.length} cases (${counts.join(", ")})`);
    out(`Estimated provider requests: ${range([budget.judgment[0] + budget.text[0], budget.judgment[1] + budget.text[1]])}`);
    out(`  TypeSafe judgments (${env.TYPESAFE_MODEL || "jev-latest"}): ${range(budget.judgment)}`);
    out(`  OpenAI text (${env.OPENAI_MODEL || "not needed"}): ${range(budget.text)}`);
    out(`Longest run if every call used its full upstream budget: ${Math.round(budget.worstMs / 1000)} s (cases run one at a time)`);
    out("Cost is not estimated: pricing depends on your provider account.");
    if (!options.yes) return refuse("Not executing: add --yes to spend the requests above.");
    providers = await createLive(env);
  } else {
    providers = createMock();
  }

  const results = await runCases(cases, providers);
  const summary = summarize(results);
  const timestamp = now().toISOString();
  out(`${options.live ? "Live" : "Mock"} evaluation, prompt_version ${PROMPT_VERSION}, ${timestamp}`);
  out(formatSummary(summary));
  for (const result of results.filter((entry) => !entry.pass)) {
    out(`FAIL ${result.id}`);
    for (const failure of result.failures) out(`  ${failure}`);
  }
  if (options.live || options.out) {
    const path = options.out
      ? resolve(options.out)
      : resolve(resultsDir, `${timestamp.replaceAll(":", "-")}-${options.live ? "live" : "mock"}.json`);
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, `${JSON.stringify({
      mode: options.live ? "live" : "mock",
      timestamp,
      protocol_version: PROTOCOL_VERSION,
      prompt_version: PROMPT_VERSION,
      models: providers.models,
      summary,
      cases: results,
    }, null, 2)}\n`);
    out(`Stored ${path}`);
  }
  return summary.failed ? 1 : 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = await main(process.argv.slice(2));
}
