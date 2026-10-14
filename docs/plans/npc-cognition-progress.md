# NPC cognition implementation progress

Implementation continuity for `docs/plans/2026-09-21-npc-cognition-architecture.md`. Not a second design document.

- Branch: `feat/npc-cognition`
- Base (`COGNITION_BASE`): `348ec24867fc3fed716d4f9d775f0c73d400a548`
- Godot: 4.7.1.stable.official.a13da4feb (`/Applications/Godot.app/Contents/MacOS/Godot`)

## Baseline (base SHA)

- Unit runner: 167 passed.
- Backend `npm --prefix tools/server test` with `GODOT` exported: 32 passed, 0 skipped.
- Integrations passing: town_emergency_flow, npc_safety_world, town_watch, town_life_world, town_interiors, town_traffic, actor_navigation, actor_contacts, combat_contact, npc_combat_position, pixel_camera.
- Pre-existing failure: `npc_reset_world_test` fails for every procedural resident ("Resident did not use the new NPC seed"). The test predates `8be7b17`, which derives procedural `personality` from role/age in `npc_procedural_profile.gd`, so comparing it with `NpcTemperament.generate().personality` no longer holds. Fixed in M1 with the reset tooling.
- Pre-existing order dependence: `npc_observation_test::test_background_processing_commits_without_conversation_and_keeps_new_arrivals` passes in the full run but fails when its file runs alone.

## Validation notes

- `tests/test_runner.gd` accepts `ARCADIA_TEST_FILTER=<substring>` for focused runs.
- Run `--import` after adding `class_name` scripts so the global class cache knows them.
- Godot runs are serialized; parallel slices never run two Godot processes in the checkout.

## Milestones

| Milestone | Status | Commit |
| --- | --- | --- |
| M0 | done: simulation fixture, fake decision service, four audit-probe characterizations, 11 synthetic legacy fixtures | `5c89f4d` |
| M1 | done: `NpcMindStore`/`NpcMindState`/`NpcRelationshipGraph`/`NpcCommitments`; v2 save with load resolution v2 → v1 world → memory-only → new; `NpcSaveMigration` revision 1; reset tooling on v2; relationships single-owned with receipts | see git log |
| M2 | done: `NpcObservation` evidence per observer in a per-mind `NpcEvidenceInbox` (fair 32-item window, noise coalescing, protected evidence never dropped, deferred retry); `NpcKnowledge` with provenance/contradiction rules, public bootstrap (runtime-only, not saved), throttled first-hand sightings; `WorldEventSnapshot`; migration revision 2 | see git log |
| M3 | done: `NpcTaskController` (owner-checked claims, one suspended task, checkpoints), `NpcBrain` per resident, routine/safety tasks, directed-travel/hold adapter tasks; `TownBuildings` is a task-owned executor (no sleep/wake decisions); `NpcDailyRoutine.hold` and the `maintain` priority chain removed | see git log |
| M4 | done: `NpcSocialTask`; encounter sessions invite (no claims, 8 s) → approach → converse → leave; player dialogue through the brain (urgent duties refuse with a short line); protected speech tokens; session id/minute/delivery in dialogue and social history (migration revision 3, legacy = unknown time); commitments resolved by task outcome, intentions completed only through commitments | see git log |
| M5 | done: `TownDeaths` intent API with private records (no `transition()`); `NpcRecoveryTask` (witness absorb → seek help from own knowledge → report, or defer with a 30-minute retry; guard acknowledge → reach body → assess → prepare → carry → cemetery → bury); `NpcGuardTask` (patrol/investigate/warn/intervene/pursue/surrendered, force only on own evidence); guard shifts from role data (no named-guard cases); bereavement concerns for informed kin; graves teach burial; directed-travel/hold adapters removed | see git log |
| M6 | done: memories carry modality/incident/origin/evidence ids/perceived minute/hearsay chain; admission keyed by the evidence receipt and completed in the same commit (`store_unavailable`, `not_claimed`, `receipts_full` reasons); per-incident relationship budget (0.15, one fresh budget per fatal or surrender-violation escalation); undated legacy memories stay undated; salience from bereavement, commitments and duties; retrieval with name/topic aliases and incident/commitment links; hourly consolidation and reference-aware receipt compaction (no FIFO drops) | see git log |
| M7 | pending | |
| M8 | pending | |
| M9 | pending | |
| M10 | pending | |

### M1 evidence

- Unit 281 passed; every integration above plus `npc_reset_world_test` (fixed) and `npc_cognition_scenarios_test` passed; backend 32 passed.
- Review checkpoint: a copy of the real `npc_world.json` (33 people, 10 dead, 221 memories, 1056 ties) migrated with zero relationship/tie mismatches; seeds (`region_seed` 828248366, `npc_seed` 508309546), personalities, population, economy, justice, deaths and rumors semantically equal; no v2 file written by loading; the real save's checksum unchanged.

### M2 evidence

- Unit 326 passed (includes the landed but not yet wired M3 core); all integrations above plus `npc_cognition_scenarios_test` passed; backend 32 passed.
- Regression probes 1-3 flipped: death evidence survives 12 newer observations; a spoken body report becomes a hearsay memory naming the deceased and the reporter with no fighting cue; a provider failure defers evidence and a later attempt appraises it once.
- Save size with knowledge: 221 KB on load, 303 KB after 2 game hours (public facts are re-derived at load; only personal facts are saved). Self-sighting history is not kept.

### M3 evidence

- Unit 386 passed; all 13 integrations passed (incl. new scenarios: sleeper → stirring → shelter → resume with one locomotion owner per trace entry; a safety task ends a two-person session and the late session release cannot release its claims; reload mid-travel resumes the same task from the saved position and nobody idles > 4.5 game minutes); backend 64 passed with `GODOT` set.
- Grep for `daily_routine.hold`, `buildings.travel(`, `.travel_to(`, `investigate(`, `sleep_at(` outside the executor/tasks finds only `BaseNpc.sleep_at`'s definition.
- Behavior changes: an investigating guard (caution priority) refuses conversations; a conversation replaces a patrol leg, which is re-requested after the session; a restored watch investigation is dropped on reload; safety tasks interrupt player dialogue.

### M4 evidence

- Unit 406 passed; all 13 integrations passed (new world scenarios: crossing invitations, danger releases both participants and the late reply cannot deliver a rumor, the player takes over a session, an urgent resident refuses the player, a commitment completes once across a world reload); backend 64 passed with `GODOT` set.
- Behavior changes: invitations take no claims until both agree; `NpcConversation` commits require a session id.

### M5 evidence

- Unit 433 passed (new: `town_deaths`, `npc_recovery_task`, `npc_guard_task`, `npc_bereavement`; regression probe 4 flipped: burial before discovery/acknowledgment/pickup fails and changes nothing); all 13 integrations passed (new world scenarios: patrol → intervention → surrender → same patrol; report/recovery/burial with a reload mid-carry, one body and one grave; carrier killed leaves the body where it fell; no surviving guard → the witness defers, resumes ordinary life and the report is taken up again later); backend 64 passed with `GODOT` set.
- Behavior changes: a witness searches guards' last-known places then help places instead of walking to the nearest living guard; a deferred report is retried after 30 minutes; recovery tasks wake their resident; old-save `directed_travel`/`hold` checkpoints are cancelled on restore (`restore_invalid`); a safety record's saved span accepts 0.001 minutes of JSON rounding.

### M6 evidence

- Unit 495 passed (new: `npc_incident_budget`, `npc_memory_evidence`, `npc_memory_retrieval`, `npc_memory_consolidation`, `npc_receipt_compaction`); all 13 integrations passed; backend 64 passed with `GODOT` set.
- Paraphrase fixture (16 queries, top-3): word matching 0.38, new retriever 0.94.
- Synthetic archive (one resident, 30 incidents × 12 low-importance sightings): `maintain()` 360 → 60 memories, 540 → 15 receipts, memory save 216 KB → 41 KB.
- Rumor loop: a forgotten rumor re-heard after save/reload adds no memory and no trust change while any account is live; an origin nobody can retell is forgotten with its receipt.
- Behavior changes: ten hits and three hits of one assault end within 0.15 of each other (seeing and feeling one incident share a budget); receipts at the 4096 bound refuse new completions until compaction frees room; first-hand sightings of one incident consolidate across origins (hearsay only within one origin).

## Remaining migration adapters

- `NpcMemoryStore.snapshot(id).relationship` (player relationship read adapter) and `TownLifeState.get_person(id).ties` (resident tie read adapter). Removed when context building moves to cognition (M6/M9).
- `TownLifeState.select_activity` activity/place/until remain as a saved context projection of the current routine/safety task (M9).

## Next step

M7 (Godot side): `NpcDecisionService` with tickets, a fair scheduler and cancellable transport; move every caller to the v2 cognition routes; `NpcDecisionPolicy` owns effects; remove the v1 routes and JS delta formulas.
