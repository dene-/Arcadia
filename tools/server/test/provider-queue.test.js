import test from "node:test";
import assert from "node:assert/strict";
import { createProviderQueue, createProviders } from "../src/provider-queue.js";
import { UPSTREAM_BUDGETS_MS } from "../src/upstream.js";

function deferred() {
  let resolve, reject;
  const promise = new Promise((res, rej) => { resolve = res; reject = rej; });
  return { promise, resolve, reject };
}
const tick = () => new Promise((resolve) => setImmediate(resolve));
const abortOf = (error) => error?.name === "AbortError";

// Starts a job whose completion the test controls; `started` resolves with its signal.
function gated(queue, pool, options) {
  const gate = deferred();
  const started = deferred();
  const result = queue.run(pool, (signal) => { started.resolve(signal); return gate.promise; }, options);
  return { gate, started: started.promise, result };
}

test("a pool never runs more jobs than its limit and starts waiting jobs in FIFO order", async () => {
  const queue = createProviderQueue({ limits: { judgment: 2, text: 1 } });
  const order = [];
  const jobs = [0, 1, 2, 3, 4].map((id) => {
    const gate = deferred();
    const result = queue.run("judgment", async () => { order.push(id); return gate.promise; });
    return { id, gate, result };
  });
  await tick();
  assert.deepEqual(order, [0, 1]);
  assert.deepEqual(queue.stats().judgment, { active: 2, queued: 3, peak_active: 2, peak_queued: 3, completed: 0, failed: 0, aborted: 0 });
  assert.equal(queue.stats().text.active, 0, "pools are independent");

  jobs[1].gate.resolve("b");
  assert.equal(await jobs[1].result, "b");
  await tick();
  assert.deepEqual(order, [0, 1, 2]);
  jobs[0].gate.resolve("a");
  jobs[2].gate.resolve("c");
  await tick();
  assert.deepEqual(order, [0, 1, 2, 3, 4]);
  jobs[3].gate.resolve("d");
  jobs[4].gate.resolve("e");
  assert.deepEqual(await Promise.all(jobs.map((job) => job.result)), ["a", "b", "c", "d", "e"]);
  assert.deepEqual(queue.stats().judgment, { active: 0, queued: 0, peak_active: 2, peak_queued: 3, completed: 5, failed: 0, aborted: 0 });
});

test("permits are released on resolve, reject and synchronous throw", async () => {
  const queue = createProviderQueue({ limits: { text: 1 } });
  assert.equal(await queue.run("text", async () => "ok"), "ok");
  await assert.rejects(queue.run("text", async () => { throw new Error("upstream failed"); }), /upstream failed/);
  await assert.rejects(queue.run("text", () => { throw new Error("sync failure"); }), /sync failure/);
  assert.equal(await queue.run("text", async () => "still available"), "still available");
  assert.deepEqual(queue.stats().text, { active: 0, queued: 0, peak_active: 1, peak_queued: 0, completed: 2, failed: 2, aborted: 0 });
});

test("aborting a queued job removes it without running it and without disturbing others", async () => {
  const queue = createProviderQueue({ limits: { text: 1 } });
  const first = gated(queue, "text");
  await first.started;
  const controller = new AbortController();
  let ran = false;
  const queued = queue.run("text", async () => { ran = true; }, { signal: controller.signal });
  const after = gated(queue, "text");
  assert.equal(queue.stats().text.queued, 2);

  controller.abort();
  await assert.rejects(queued, abortOf);
  assert.equal(queue.stats().text.queued, 1);
  first.gate.resolve();
  await first.result;
  await after.started;
  after.gate.resolve("after");
  assert.equal(await after.result, "after");
  assert.equal(ran, false);
  assert.deepEqual(queue.stats().text, { active: 0, queued: 0, peak_active: 1, peak_queued: 2, completed: 2, failed: 0, aborted: 1 });
});

test("an already aborted signal rejects immediately and takes no permit", async () => {
  const queue = createProviderQueue({ limits: { text: 1 } });
  const controller = new AbortController();
  controller.abort();
  let ran = false;
  await assert.rejects(queue.run("text", async () => { ran = true; }, { signal: controller.signal }), abortOf);
  assert.equal(ran, false);
  assert.deepEqual(queue.stats().text, { active: 0, queued: 0, peak_active: 0, peak_queued: 0, completed: 0, failed: 0, aborted: 1 });
});

test("aborting an active job frees its permit once even if its task never settles or settles late", async () => {
  const queue = createProviderQueue({ limits: { judgment: 1 } });
  const controller = new AbortController();
  const hung = gated(queue, "judgment", { signal: controller.signal });
  const signal = await hung.started;
  const next = gated(queue, "judgment");
  const third = gated(queue, "judgment");
  await tick();
  assert.equal(signal.aborted, false);
  assert.equal(queue.stats().judgment.queued, 2);

  controller.abort();
  await assert.rejects(hung.result, abortOf);
  assert.equal(signal.aborted, true);
  await next.started;
  assert.deepEqual([queue.stats().judgment.active, queue.stats().judgment.queued], [1, 1]);

  // The transport finally completes, and a second abort fires: neither may release a second permit.
  hung.gate.resolve("late");
  controller.abort();
  await tick();
  assert.deepEqual([queue.stats().judgment.active, queue.stats().judgment.queued], [1, 1]);
  next.gate.resolve();
  await next.result;
  await third.started;
  third.gate.reject(new Error("boom"));
  await assert.rejects(third.result, /boom/);
  assert.deepEqual(queue.stats().judgment, { active: 0, queued: 0, peak_active: 1, peak_queued: 2, completed: 1, failed: 1, aborted: 1 });
});

test("a job that fails after its abort does not count twice", async () => {
  const queue = createProviderQueue({ limits: { text: 1 } });
  const controller = new AbortController();
  const job = gated(queue, "text", { signal: controller.signal });
  await job.started;
  controller.abort();
  await assert.rejects(job.result, abortOf);
  job.gate.reject(new Error("socket closed"));
  await tick();
  assert.deepEqual(queue.stats().text, { active: 0, queued: 0, peak_active: 1, peak_queued: 0, completed: 0, failed: 0, aborted: 1 });
});

test("a job may run a nested job in another pool without deadlock, even at limit one", async () => {
  const queue = createProviderQueue({ limits: { judgment: 1, text: 1 } });
  let during;
  const result = await queue.run("text", async () => {
    const grounded = await queue.run("judgment", async () => {
      during = queue.stats();
      return "grounded";
    });
    return `dialogue+${grounded}`;
  });
  assert.equal(result, "dialogue+grounded");
  assert.equal(during.text.active, 1);
  assert.equal(during.judgment.active, 1);
  assert.deepEqual([queue.stats().text.active, queue.stats().judgment.active], [0, 0]);
});

test("nested acquisition of the same pool is rejected instead of deadlocking", async () => {
  const queue = createProviderQueue({ limits: { judgment: 1, text: 1 } });
  await queue.run("text", async () => {
    await assert.rejects(queue.run("text", async () => "never"), /Nested acquisition of the "text" provider pool/);
  });
  // The rule follows the whole chain of held pools, not just the immediate parent.
  await queue.run("text", () => queue.run("judgment", async () => {
    await assert.rejects(queue.run("text", async () => "never"), /Nested acquisition/);
    await assert.rejects(queue.run("judgment", async () => "never"), /Nested acquisition/);
  }));
  // Outside a job the pool is available again, and the rejected attempts consumed nothing.
  assert.equal(await queue.run("text", async () => "free"), "free");
  assert.deepEqual(queue.stats().text, { active: 0, queued: 0, peak_active: 1, peak_queued: 0, completed: 3, failed: 0, aborted: 0 });
});

test("unknown pools and invalid limits are rejected", async () => {
  assert.throws(() => createProviderQueue({ limits: { text: 0 } }), RangeError);
  await assert.rejects(createProviderQueue().run("mystery", async () => {}), /Unknown provider pool/);
});

test("providers queue every call with the shared budgets and bind nested calls to the held text job", async () => {
  const seen = [];
  const queue = createProviderQueue({ limits: { judgment: 1, text: 1 } });
  const providers = createProviders({
    queue,
    decide: async (request, options) => { seen.push(["decide", request, options, queue.stats()]); return { answers: {} }; },
    generate: async (request, options) => { seen.push(["generate", request, options, queue.stats()]); return { output_text: "{}" }; },
  });
  const controller = new AbortController();
  await providers.decide("q", { signal: controller.signal });
  await providers.generate("g", { signal: controller.signal, timeout: 1234 });
  await providers.withText(async ({ generate, decide }) => {
    await generate("dialogue");
    await decide("ground", { timeout: UPSTREAM_BUDGETS_MS.grounding });
  });

  const [judge, text, dialogue, ground] = seen;
  assert.deepEqual([judge[2].timeout, judge[2].maxRetries], [UPSTREAM_BUDGETS_MS.judgment, 0]);
  assert.equal(judge[3].judgment.active, 1);
  assert.equal(text[2].timeout, 1234);
  assert.equal(text[3].text.active, 1);
  assert.equal(dialogue[2].timeout, UPSTREAM_BUDGETS_MS.dialogue);
  assert.deepEqual([ground[2].timeout, ground[2].maxRetries], [UPSTREAM_BUDGETS_MS.grounding, 0]);
  assert.deepEqual([ground[3].text.active, ground[3].judgment.active], [1, 1]);
  assert.equal(ground[2].signal, dialogue[2].signal, "nested work shares the text job's signal");
  assert.equal(judge[2].signal.aborted, false);
  assert.equal(text[2].signal, controller.signal);
});
