// Server-side limits for upstream provider work. The game mirrors GAME_DEADLINES_MS.
export const UPSTREAM_BUDGETS_MS = Object.freeze({
  judgment: 8000, // one Jev request; SDK retries are disabled, the game owns retry
  dialogue: 30000, // main dialogue generation
  grounding: 5000, // memory-grounding judgment nested in a dialogue request
  ambient: 10000, // optional reaction and NPC-to-NPC speech
});

// A game deadline shorter than the server budget would discard slow successful work.
export const GAME_DEADLINE_MARGIN_MS = 2000;
export const GAME_DEADLINES_MS = Object.freeze({
  judgment: 10000,
  dialogue: 40000,
  ambient: 12000,
});

export const PROVIDER_LIMITS = Object.freeze({ judgment: 4, text: 2 });

// Aborts when the client disconnects before the response was fully written.
export function disconnectSignal(res) {
  const controller = new AbortController();
  res.on("close", () => {
    if (!res.writableFinished) controller.abort();
  });
  return controller.signal;
}
