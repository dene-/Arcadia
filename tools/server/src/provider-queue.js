import { AsyncLocalStorage } from "node:async_hooks";
import { PROVIDER_LIMITS, UPSTREAM_BUDGETS_MS } from "./upstream.js";

function abortError(signal) {
  return new DOMException("The provider job was aborted.", { name: "AbortError", cause: signal?.reason });
}

// Upstream concurrency lives here; game-side scheduling decides relevance.
// A job in one pool may run a job in another pool; re-entering its own pool
// from inside a job is rejected because it could wait on itself forever.
export function createProviderQueue({ limits = PROVIDER_LIMITS } = {}) {
  const held = new AsyncLocalStorage();
  const pools = new Map();
  for (const [name, limit] of Object.entries(limits)) {
    if (!Number.isInteger(limit) || limit < 1) throw new RangeError(`Invalid limit for pool "${name}"`);
    pools.set(name, {
      limit,
      active: 0,
      waiting: [],
      stats: { peak_active: 0, peak_queued: 0, completed: 0, failed: 0, aborted: 0 },
    });
  }

  function settle(pool, job, outcome, finish) {
    if (job.done) return;
    job.done = true;
    job.signal.removeEventListener("abort", job.onAbort);
    if (job.started) pool.active--;
    else pool.waiting.splice(pool.waiting.indexOf(job), 1);
    pool.stats[outcome]++;
    finish();
    pump(pool);
  }

  function start(pool, job) {
    job.started = true;
    pool.active++;
    pool.stats.peak_active = Math.max(pool.stats.peak_active, pool.active);
    let promise;
    try {
      promise = Promise.resolve(held.run(job.held, () => job.task(job.signal)));
    } catch (error) {
      promise = Promise.reject(error);
    }
    promise.then(
      (value) => settle(pool, job, "completed", () => job.resolve(value)),
      (error) => settle(pool, job, "failed", () => job.reject(error)),
    );
  }

  function pump(pool) {
    while (pool.active < pool.limit && pool.waiting.length) start(pool, pool.waiting.shift());
  }

  function run(poolName, task, { signal } = {}) {
    const pool = pools.get(poolName);
    if (!pool) return Promise.reject(new RangeError(`Unknown provider pool "${poolName}"`));
    const parents = held.getStore() ?? new Set();
    if (parents.has(poolName))
      return Promise.reject(new Error(`Nested acquisition of the "${poolName}" provider pool would deadlock`));
    if (signal?.aborted) {
      pool.stats.aborted++;
      return Promise.reject(abortError(signal));
    }
    return new Promise((resolve, reject) => {
      const job = {
        task,
        resolve,
        reject,
        signal: signal ?? new AbortController().signal,
        held: new Set([...parents, poolName]),
        started: false,
        done: false,
      };
      job.onAbort = () => settle(pool, job, "aborted", () => reject(abortError(job.signal)));
      job.signal.addEventListener("abort", job.onAbort, { once: true });
      if (pool.active < pool.limit && !pool.waiting.length) start(pool, job);
      else {
        pool.waiting.push(job);
        pool.stats.peak_queued = Math.max(pool.stats.peak_queued, pool.waiting.length);
      }
    });
  }

  function stats() {
    return Object.fromEntries([...pools].map(([name, pool]) => [name, {
      active: pool.active,
      queued: pool.waiting.length,
      ...pool.stats,
    }]));
  }

  return { run, stats };
}

// Wraps the raw SDK callers so every upstream call is queued, aborted with its
// client, and bounded by the shared budgets. `generate` and `withText` use the
// text pool; `decide` uses the judgment pool, including inside `withText`.
export function createProviders({ decide, generate, queue = createProviderQueue() }) {
  const judge = (request, { signal, timeout = UPSTREAM_BUDGETS_MS.judgment, maxRetries = 0 } = {}) =>
    queue.run("judgment", (jobSignal) => decide(request, { signal: jobSignal, timeout, maxRetries }), { signal });
  // `task` receives { generate, decide } bound to the held text permit; generate must not re-enter the pool.
  const withText = (task, { signal } = {}) =>
    queue.run("text", (jobSignal) => task({
      generate: (request, { timeout = UPSTREAM_BUDGETS_MS.dialogue } = {}) =>
        generate(request, { signal: jobSignal, timeout }),
      decide: (request, options = {}) => judge(request, { signal: jobSignal, ...options }),
    }), { signal });
  const text = (request, { signal, timeout } = {}) =>
    withText(({ generate: upstream }) => upstream(request, { timeout }), { signal });
  return { decide: judge, generate: text, withText, queue };
}
