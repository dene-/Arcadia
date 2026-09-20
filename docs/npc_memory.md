# NPC memory and Jev decisions

This implements the memory design from the [Designing NPC Memory System conversation](https://chatgpt.com/c/58a2744a-5150-832c-993b-6a294513fd10), including its later Arcadia-specific decision to keep saves in Godot. Jev supplies typed judgments; game code owns changes; OpenAI generates dialogue and proposed memory text.

## Ownership and turn flow

`NpcProfile` is immutable authored identity. `NpcMemoryStore` owns save-specific experiences, recent dialogue, relationships and pending observed events. `NpcConversation` constructs temporary context, runs the two backend stages, and commits successful exchanges. `DialogManager` owns the helper and UI lifecycle, not memory algorithms. There is no extra Autoload or server database.

```mermaid
sequenceDiagram
    participant G as Godot
    participant S as Local Node server
    participant J as Jev
    participant L as Dialogue model
    G->>S: /decide: profile, current state, recent dialogue, relationship
    S->>J: Batched typed questions
    J-->>S: Probabilities, scores and choices
    S-->>G: Validated answers and deterministic policy
    G->>G: Retrieve and filter recall; preview relationship change
    G->>S: /chat: accessible memories and updated context
    S->>L: Universal cognitive prompt and strict output schema
    L-->>S: Dialogue, replies, proposed memory gists, used memory IDs
    S-->>G: Validated result
    G->>G: Check conversation freshness, commit and save
```

The preview affects the current response, but persistent state changes only after valid dialogue returns. Closing, switching, reopening, or losing the source invalidates pending results. Failed requests do not advance memory time, reinforce recall, consume events or change relationships. A response cannot apply to a later conversation with the same NPC.

Opening an interaction automatically chooses a short player greeting, such as "Hi." or "Hey." The same greeting reaches Jev, the dialogue model and recent history; typed player messages remain unchanged. NPC responses contain spoken words only. The prompt asks for natural conversational language, and the server replaces any remaining em dashes in displayed responses and suggested replies.

## Authoring NPCs

Give each individual an explicit, unique `NpcProfile.npc_id`. Renaming the display name must not change it. Multiple scene instances with the same ID represent the same person; distinct people need separate profiles/IDs. All nine existing human profiles have IDs.

Profiles compose these resources:

- `NpcKnowledgePack`: reusable knowledge plus explicit expertise limits. All current humans share Rekala knowledge and have a profession pack.
- `NpcCognitionProfile`: attention, factual/social/name recall, emotional retention and sensory association. The alchemist, social trades and practical crafts have different values.
- `NpcCoreMemory`: authored gist, stable memory ID, age, importance, emotion, vividness, confidence, retrieval cues, remembered details and known gaps. Blacksmith, alchemist and tailor include examples.

Keep gists broad. Put precise facts in `important_details` and `weak_details`; these are removed from context as recall weakens. `known_gaps` describes missing information, not the hidden answer. `people` must list names that should be filtered when name recall is weak. Sensory cues are actual remembered sensations, not invented atmospheric decoration.

Old `NpcProfile.memories` strings are imported once as legacy episodic records. They are never sent wholesale as profile fields. Authored records are copied when a save first encounters that NPC, so later authoring edits do not overwrite that save's experiences.

## Memory and belief rules

Runtime records are JSON-compatible dictionaries, not mutable shared Resources:

| Type | Meaning |
| --- | --- |
| episodic | An experienced event or the experience of hearing a claim |
| semantic | A provisional belief admitted by the belief gate |
| social | A supported impression about someone |
| prospective | A promise or unresolved intention |

The last 12 speaker turns form recent dialogue. Ordinary greetings and small talk normally remain there without durable admission. Semantic memory requires Jev's belief gate. Player claims retain `source: player_claim` and belief confidence 0.6; even a believed claim does not become authoritative world state. Different NPCs can retain conflicting beliefs. Exact repeated gists from the same source are deduplicated without increasing confidence.

The dialogue model proposes text and categories but cannot choose trust deltas, importance, belief admission or save IDs. The server requires a verbatim evidence span in the current message, NPC response, or a supplied observed event. This checks grounding and source attribution; it cannot prove that a generated paraphrase is semantically correct. Evaluate that behavior with live models before shipping.

Relationship dimensions remain independent: familiarity, trust, respect, affection, fear and suspicion. Jev selects direction; code applies a bounded magnitude derived from importance. Uncertain choices leave dispositions unchanged. Forgiveness does not delete history. Core identity and procedural expertise remain in authored data.

## Retrieval and forgetting

Retrieval uses normalized word overlap, entities, importance, emotion, recency, rehearsal, sensory cues and unresolved intentions. It returns at most six records with deterministic tie-breaking. No vector database is needed.

Recall separately computes quality using age, cognition, emotional retention, vividness, repetition and matching sensations. Tiers are familiarity, fragmentary, fuzzy, clear and vivid. Weak tiers omit the gist or precise details; names have a separate recall threshold. The LLM receives only the resulting view, never the hidden details with an instruction to pretend it forgot them. Missing information remains absent even when the player repeatedly asks.

Only supplied memories reported as actually used receive rehearsal credit. Emotional memories can keep fragments longer; associative cues can retrieve a memory without a direct question. Saved records remain intact. There is no random rewriting of world facts and no forced confabulation.

Memory age uses a **logical turn clock**, not wall-clock time: every successful exchange advances it once, across NPCs. Game time skips can call `DialogManager.get_memory_store().advance_time(turns)` and save. `age_turns` is an authoring/tuning unit, not a claim that one turn equals a day. The game currently has no world calendar. Sleep consolidation, embedding retrieval, learned distortions and NPC-to-NPC gossip are later extensions, not simulated implicitly.

## Perception and intentions

`BaseNpc.get_cognitive_context()` supplies current location, activity, physical condition and sensory cues. Override it for a specific actor to add only things they can perceive. `BaseNpc.take_damage()` records an injury without inventing an attacker identity.

Other game systems can call:

```gdscript
DialogManager.record_npc_event(npc.get_npc_profile(), "I watched the player return my tools.")
```

Pending events are bounded to eight and consumed only after a successful exchange. Events that arrive during a request are preserved for a later exchange. Player assertions must stay player messages; never feed them through this observation API.

Game code, not model prose, resolves a prospective record:

```gdscript
var memory_store: NpcMemoryStore = DialogManager.get_memory_store()
memory_store.complete_intention("garrin_holt", "mem:12")
memory_store.save_file()
```

This changes the NPC's intention record, never inventory, quests or other world truth. Generic world event simulation and a quest system are outside this change.

## Persistence

The default save is `user://npc_memory.json`, version 1. Successful exchanges and observed injury events save automatically. Writes go through a temporary file and rename. Loading validates the entire save before replacing state. Invalid or unsupported saves are left untouched and automatic overwriting is disabled; memory can continue in RAM while the file is recovered. Warnings report persistence errors.

`to_save_data()` and `from_save_data()` expose an explicit contract for a future game save system. This temporary default is one local playthrough. A future new-game/save-slot UI should own separate store instances or embed this data in its own slot; no multiplayer identity or server-side persistence is implied.

## Jev configuration and validation

The [official TypeSafe skill](https://github.com/typesafe-ai/skills) and [API contract](https://docs.typesafe.ai/api) guide the integration. Questions and thresholds are in `tools/server/src/npc-decisions.js`. Noul is a yes-probability; Choice is a categorical decision with confidence; Score is a probability-weighted **zero-based** level. Five importance levels are normalized from 0–4 to 0–1. Raw answers remain available during the exchange.

Initial gates: admission 0.7, retrieval 0.5, belief update 0.8, Choice confidence 0.65. These are tunable starting policies, not measured game-domain calibration. Jev receives current state and recent context before retrieval; it does not receive the full archive. Its pre-response admission gate evaluates the input interaction, so an unsolicited promise first invented by the dialogue model is not automatically admitted when that gate is closed.

Use [server setup](../tools/server/README.md) for credentials and the dialogue model. All automated inference tests use mocks. Godot tests cover isolation, admission, recall, aging, repetition, names, persistence and cancellation; the Node suite exercises the official SDK shape, policy and actual Godot-to-server HTTP flow. Live inference behavior, latency, and thresholds remain to be evaluated after local key configuration.

## Validation notes (2026-09-20)

Validated with Godot 4.7.1 and Node 24.19.0. All 18 changed/new GDScript files passed script checks, the game passed the headless smoke test, and all 10 Node tests passed with `GODOT` set (including the real HTTP client with mocked providers). The Godot suite passed 62/63 tests; all 21 new memory/conversation tests passed.

The existing `npc_ai_test.gd::test_lateral_attack_position_respects_soft_collision_distance` also fails on untouched master `c9d3b4a` under 4.7.1 (43/44 tests). Its attack-distance implementation was left unchanged. Separately, `npm audit` reports existing low/moderate advisories in `body-parser` and `qs`; adding the TypeSafe SDK did not change either locked dependency. Those maintenance issues need a separate review.

The headless editor import also emits existing inventory `@tool`/placeholder-instance errors on both untouched master and this branch; the runtime game smoke test is clean. The sandbox cannot write the editor's global settings file, so validation logs were directed to `/tmp`.
