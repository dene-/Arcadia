# Dialog Server

Local, stateless Node.js bridge for Arcadia's NPC cognition and dialogue. It listens only on `127.0.0.1:3536`; Godot owns the memory save. Requires Node.js 22+.

## Setup

```bash
cd tools/server
npm ci
cp .env.example .env
npm start
```

On PowerShell use `Copy-Item .env.example .env`.

Set `TYPESAFE_API_KEY` and `OPENAI_API_KEY` in the ignored `.env`, and choose `OPENAI_MODEL`, a Responses API model supporting strict JSON Schema outputs. `TYPESAFE_MODEL` defaults to `jev-latest`. No keys are stored in Godot resources. The server starts without keys but inference endpoints return 503 until configured.

The previous account-specific stored prompt is replaced by the versioned, universal cognitive prompt in `src/dialogue.js`. No remote prompt editing is required. `store: false` remains enabled.

## Flow

1. Godot sends identity, cognition, current perception, recent dialogue and relationship to `/decide`.
2. The official TypeSafe SDK calls `POST https://api.typesafe.ai/v1/systemone`. Questions and tunable thresholds are together in `src/npc-decisions.js`. Raw typed answers and deterministic policy are returned.
3. Godot selects and filters memories if retrieval is admitted, and previews the bounded relationship change.
4. `/chat` validates the same decisions and supplies the updated context and recall to OpenAI. It returns dialogue, three player replies, grounded memory proposals and the IDs of used memories.
5. Godot commits only a valid result for the still-current conversation, then saves locally.

All human NPC resources enable free-text chat. Suggested replies remain available for scripted NPCs that disable chat. Jev assesses `should_end_conversation` independently of the main interaction intent, so a promise or threat can also be a farewell. At probability 0.8 or higher, code sets `policy.end_conversation`; ambiguous or quoted farewells should keep the conversation open. OpenAI receives that policy to write a short farewell. Godot accepts the exit only after a successful exchange and closes 1.5 seconds after the final page finishes revealing (or when the player advances it). Chat input stays hidden during the farewell. Cancellation, failed requests and reopening clear the pending exit.

Both endpoints use `protocol_version: 1` and structured objects, replacing `npcData` JSON-inside-JSON. Provider failures return generic 503 errors; malformed requests return 400. They never silently substitute a different decision model. The game shows its fallback dialogue and makes no memory/relationship changes on failure.

Spontaneous speech is two steps. The game appraises perception and decides whether and how to speak with the v2 routes (`appraise`, then `utterance`; see below). Only an admitted utterance reaches the text routes, which write one line and make no decisions:

- `POST /react` takes `protocol_version: 1`, `npc`, `event` (`text`, `sense` of `sight`/`hearing`/`touch`, `player_involved`), `context` and `intent`, one of `remark`, `warn`, `call_for_help`, `protest` or `grieve` (silence is never sent). It returns `{response}` in the NPC's saved voice. An unknown intent, a malformed event or any other protocol version returns 400. The server never judges whether to speak: v1 `answers`, `policy` and `speech_allowed` fields have no effect.
- `POST /life/say` takes `protocol_version: 1`, `npc`, `listener`, `current`, `relationship`, `recent_social`, optional `tone`, `topic` (an attributed account, or null) and `intent`: `share` (needs `topic`), `reply` (needs `topic`) or `small_talk`. `mode` is optional and, if sent, must equal `intent`. It returns `{response}`; hearsay stays attributed to the original observer.

Both use the ambient budget and the text pool, abort on client disconnect, and share the length and grounding rules (at most 160 characters, no narration). All dialogue and event requests include explicit relationship scales. See [NPC perception](../../docs/npc_perception.md) for tuning and runtime debugging.

Removed v1 routes: `POST /observe` and `/life/routine`, `/life/social`, `/life/listen`. They return 404; their judgments are the v2 `appraise`, `select-goal`, `social` and `listen` routes. `/decide` and `/chat` (player dialogue) stay on v1 with `decisionPolicy` until the dialogue migration.

## Provider queue and upstream budgets

All upstream calls go through one queue (`src/provider-queue.js`) with fixed concurrency: at most 4 judgment calls (TypeSafe) and 2 text calls (OpenAI) run at once; extra work waits in FIFO order. Dialogue grounding runs nested inside the `/chat` text permit with its own judgment permit, so a saturated queue cannot deadlock a chat. Each request carries an `AbortSignal` that fires when the client disconnects: a queued job is dropped without reaching the provider, and an in-flight call is aborted and its permit freed even if the transport never settles. SDK retries are disabled (`maxRetries: 0`); the game decides whether to retry.

Upstream budgets (`src/upstream.js`, exported as `UPSTREAM_BUDGETS_MS`) are aligned with the game's HTTP deadlines (`GAME_DEADLINES_MS`), which each leave a 2000 ms margin (`GAME_DEADLINE_MARGIN_MS`) for transport:

| Call | Server upstream budget | Game deadline |
| --- | --- | --- |
| Judgment: `/decide`, all `/v2/cognition/*` | 8000 ms | 10000 ms |
| Dialogue: `/chat` generation | 30000 ms | 40000 ms (covers dialogue + grounding + margin) |
| Grounding: `/chat` memory-proposal check | 5000 ms | inside the dialogue deadline |
| Ambient text: `/react`, `/life/say` | 10000 ms | 12000 ms |

## Cognition v2 routes

`POST /v2/cognition/{appraise,select-goal,social,listen,utterance}` (`src/cognition-routes.js`, `src/cognition-contract.js`) return validated typed judgments only; they never apply relationship, memory or goal effects. Requests use `protocol_version: 2` and `prompt_version: "cognition-1"`; any other value returns `409 {error: "protocol_mismatch", protocol_version, prompt_version}` before other validation. The envelope carries `request_id`, `npc_id`, `kind` (must match the route), an opaque `ticket` echoed by the game, a bounded `state`, `evidence` (max 8 items), and the per-kind lists `subjects`, `candidates`, `topics`/`tones` or `intents`. Question ids are generated server-side only from the validated ids.

Statuses: 200 `{request_id, kind, protocol_version, prompt_version, model, judgments}`; 400 `{error: "invalid_request", code}`; 409 protocol mismatch; 413 `payload_too_large`; 502 `{error: "invalid_provider_payload"}` when the provider answer breaks the contract (wrong type, out-of-range score or probability, unknown choice, missing or foreign question); 503 `{error: "unavailable"}` on provider failure or missing keys. Judgments are validated atomically: one bad answer rejects the whole response and unknown fields are dropped.

Request/response examples live in `tests/fixtures/cognition_contract/` (`manifest.json` lists them): `{appraise,select_goal,social,listen,utterance}.{request,response}.json` and the invalid provider answers `invalid_{wrong_type,score_out_of_range,unknown_choice,missing_question,foreign_candidate}.json`. The Node tests and the Godot decision service share them.

## Validation without API access

See [Town life](../../docs/town_life.md) for ownership, persistence, provenance and debugging of the town simulation; its NPC-to-NPC speech arrives here only as `/life/say`. Restart the server after updating routes.

```bash
npm test
GODOT=/Applications/Godot.app/Contents/MacOS/Godot npm test
```

The second command also runs a real Godot HTTP exchange against the in-process mock server: player dialogue, a v2 `appraise` and `utterance` judgment through `NpcDecisionService`, and `/react`. All inference is mocked, including the official SDK transport test; no API credentials or paid requests are used. The HTTP integration test is explicitly skipped when `GODOT` is unset.

See [NPC memory](../../docs/npc_memory.md) for authoring, persistence and tuning. Live model quality and thresholds still need evaluation on actual game dialogue after credentials are configured.
