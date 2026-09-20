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

Both endpoints use `protocol_version: 1` and structured objects, replacing `npcData` JSON-inside-JSON. Provider failures return generic 503 errors; malformed requests return 400. They never silently substitute a different decision model. The game shows its fallback dialogue and makes no memory/relationship changes on failure.

Combat perception also uses `/observe` for independent Jev assessments and `/react` for optional short spoken reactions. `/react` generates text only when the validated speech decision admits it. Observation failures retain short-term perceptions without applying relationship changes. All dialogue and event requests include explicit relationship scales. See [NPC perception](../../docs/npc_perception.md) for tuning and runtime debugging.

## Validation without API access

```bash
npm test
GODOT=/Applications/Godot.app/Contents/MacOS/Godot npm test
```

The second command also runs a real Godot HTTP exchange against the in-process mock server. All inference is mocked, including the official SDK transport test; no API credentials or paid requests are used. The HTTP integration test is explicitly skipped when `GODOT` is unset.

See [NPC memory](../../docs/npc_memory.md) for authoring, persistence and tuning. Live model quality and thresholds still need evaluation on actual game dialogue after credentials are configured.
