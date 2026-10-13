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
| M2 | in progress | |
| M3 | pending | |
| M4 | pending | |
| M5 | pending | |
| M6 | pending | |
| M7 | pending | |
| M8 | pending | |
| M9 | pending | |
| M10 | pending | |

### M1 evidence

- Unit 281 passed; every integration above plus `npc_reset_world_test` (fixed) and `npc_cognition_scenarios_test` passed; backend 32 passed.
- Review checkpoint: a copy of the real `npc_world.json` (33 people, 10 dead, 221 memories, 1056 ties) migrated with zero relationship/tie mismatches; seeds (`region_seed` 828248366, `npc_seed` 508309546), personalities, population, economy, justice, deaths and rumors semantically equal; no v2 file written by loading; the real save's checksum unchanged.

## Remaining migration adapters

- `NpcMemoryStore.snapshot(id).relationship` (player relationship read adapter) and `TownLifeState.get_person(id).ties` (resident tie read adapter). Removed when context building moves to cognition (M6/M9).

## Next step

M2 integration: perception produces `NpcObservation` records into each mind's `NpcEvidenceInbox`; the event processor claims from the inbox; knowledge bootstrap and sightings; migration revision 2.
