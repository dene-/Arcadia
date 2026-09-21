# NPC cognition audit

Reviewed 2026-09-21 against `master` at `10c5d48`, with changes on
`fix/npc-cognition-consistency`. This is a code and mocked-provider audit, not a
measurement of live Jev or dialogue quality.

## Corrected in this branch

| Failure | Resulting behavior | Main implementation |
| --- | --- | --- |
| Conversation and observation decisions could not see long-term memories. The server explicitly erased them. | Both receive up to six relevant recollections, with the existing detail loss, attribution and uncertainty. Conversation policy still decides whether to use them in dialogue. Merely considering them does not reinforce them. | `npc_conversation.gd`, `npc_event_processor.gd`, `app.js` |
| A genuine quoted phrase could be attached to an invented gist or invented details. | After dialogue generation, a separate Jev batch assesses each proposed memory against its actual source. Only supported proposals pass the 0.85 admission threshold. Errors reject proposals while preserving valid dialogue. Exact evidence is retained for inspection, excluded from recall views. | `tools/server/src/memory-grounding.js`, `dialogue.js`, `npc_memory_store.gd` |
| An event arriving during inference could leave the NPC delivering and committing an obsolete response. | Per-NPC revision checks invalidate old results before commitment. Dialogue refreshes and retries once, then closes if interrupted again. Spontaneous speech also checks actor revision and world space. Diagnostics and unrelated NPC activity do not invalidate a reply. | `npc_memory_store.gd`, `npc_conversation.gd`, `dialog_manager.gd`, `npc_event_processor.gd` |
| Ambient remarks were inserted as if spoken directly to the player. | Player conversation history now contains actual player exchanges. Spontaneous lines use the existing spatially perceived ambient speech history. Existing historical entries cannot be reliably repaired because they lack addressee metadata. | `npc_event_processor.gd` |
| Unremembered perceptions remained in prompts indefinitely; their recency also aged while the game was closed. | New perceptions use saved game minutes for a three-game-hour working-memory window. Ongoing injury remains salient. Older observations stay in diagnostics and admitted memories remain available through retrieval. Legacy records without game time use a two-real-minute fallback. | `npc_cognitive_context.gd`, `npc_memory_store.gd` |
| Strong listener judgments could amplify a weak rumor into a trust penalty. Retelling an unremembered story could apply that penalty again. | Effective confidence cannot exceed the account's confidence; weak accounts cannot alter player trust. Claims start below firsthand confidence. Persistent origin receipts prevent duplicate penalties even without a durable memory. Expired accounts no longer count as known. An assessment cannot transfer an account replaced while it was in flight. | `town_rumors.gd`, `npc_memory_store.gd`, `tools/server/src/town-life.js` |

The grounding batch runs only when proposals survive structural and quote checks,
with at most three questions. It has a five-second timeout and no retry, within the
existing 45-second Godot request budget after dialogue generation's 30-second
budget. This reduces unsupported admissions; semantic classification remains
fallible and needs live evaluation before claiming accuracy.

Existing saves load without a reset. New optional fields are validated. Runtime
revision counters are not persisted. Origin receipts contain IDs, not the story's
contents; their eventual compaction must preserve deduplication.

## Follow-up status and remaining priorities

### 1. Memory age now follows the saved world clock

Implemented in the continuation: new durable memories have `created_minute` and
rehearsals have `last_recalled_minute`. The turn counter remains an ordering value;
other NPCs' conversations and combat do not alter retention. `TownLifeState` owns
the clock and publishes changes to the memory store through `NpcWorldSave`.

Legacy memories preserve their existing retention age at a saved game-time anchor.
They do not gain fabricated event dates, and repeated loads do not re-anchor them.
Authored memories initialize independently of how many exchanges occurred before
meeting that NPC. A retention unit is currently 30 game minutes; this is a tuning
policy, not an empirically calibrated model of human memory.

Still needed: age/session metadata on dialogue history and better consolidation
and rehearsal policies.

### 2. Perceived danger now produces an executable safety response

Implemented: Jev independently chooses NONE, CAUTION or SHELTER during perception
assessment. `NpcSafetyState` keeps the temporary concern separate from persistent
relationships. A direct injury provisionally requests shelter even if inference
is unavailable; anonymous noise initially creates caution. A confident assessment
may conclude that no continuing danger warrants a response. Late assessments
cannot replace newer concerns or revive expired ones.

Town life interrupts social holds and an existing player conversation, then uses
the normal navigation and door system to seek the NPC's home. If the danger was
inside that home, the NPC instead leaves for the public market. Shelter lasts at
most 45 game minutes from the perception, unless another injury renews it. It does
not become sleep, restart on each tick, or end merely because a schedule slot or
day boundary changed. Ordinary routines resume when the concern expires or is
cleared. A pending routine request cannot block or overwrite the retreat.

The refuge is a known destination, not a guarantee of safety. This first action
does not lock doors, heal injuries or detect a pursuer without a new perception.
Next executable actions should be seeking help and checking on a friend, with
actual interaction/completion conditions. Persistent needs and goal commitments
remain the next architectural priority.

### 3. Separate needs, temporary emotion, relationships and commitments

`NpcRelationshipState` holds persistent dimensions, but there is no distinct
short-lived arousal/anger state, measured fatigue/hunger, or goal ownership.
Routine decisions mention energy without an actual energy simulation. Repeated
hits also produce independent fixed-sized relationship changes; interaction
frequency can dominate severity. This needs incident-level appraisal, not merely
larger per-turn deltas.

Start with fatigue, safety and one current commitment. Update them deterministically
from sleep, elapsed game time and witnessed events. Let personality affect
interpretation and priorities, while keeping named identity and long-term traits
stable. Forgiveness should require relevant new evidence; lowering arousal should
not restore trust automatically. Randomness should vary feasible choices and
expression without undoing commitments or knowledge.

### 4. Make social and routine decisions use personal memory consistently

Implemented in the continuation: routine and social requests now retrieve the
same bounded, imperfect memory views used by conversation. Routine cues include
current/planned activity and safety concerns; social cues include the other
person. The full archive stays local. Other people's private memories are never
included. Routine candidate descriptions no longer expose exact counts of unseen
residents and their future destinations; navigation retains its own reservations.

Remaining: lexical retrieval misses paraphrases and many player-related memories
compete for six slots. Consider Jev reranking a small candidate set with a no-match
outcome, then evaluate whether appointments affect visits and past betrayal affects
disclosure under varied phrasing.

### 5. Preserve who said what and limit social omniscience

`TownLifeState.remember_exchange` stores `with`, `text` and `minute`, but no
speaker. `TownEncounters` stores the same initial utterance for both people, and a
reply only for its speaker. That makes attribution ambiguous and leaves the first
speaker without the reply in their social history. The separate leak of exact
crowd counts and unseen destinations in routine descriptions is now corrected.

Record speaker, listener and whether an entry is an utterance or an abstract
encounter summary. Record audible replies for both participants. Keep occupancy
reservations in navigation; only expose perceived crowds or explicitly shared
plans as NPC knowledge. Offscreen encounters may use summaries, but must preserve
the same information-transfer rules as on-screen ones.

### 6. Represent disagreement and memory consolidation explicitly

Admission deduplicates only exact lowercase gist plus source. Paraphrased accounts
can accumulate as separate memories, and there is no supersedes/contradicts link
or mechanism for revising a mistaken belief. Archives and origin receipts grow
with playtime. A convincing correction can coexist with the old belief without
an explicit resolution.

Track an experience's provenance separately from the belief it supports. Preserve
multiple interpretations and allow uncertain or contested beliefs. Consolidate
related experiences without promoting repetition to independent evidence, losing
original sources, or converting a promise into a completed deed. Establish size
budgets only after defining what remains retrievable and what deduplication must
survive compaction.

### 7. Evaluate sequences, not isolated attractive lines

Mock tests establish plumbing and deterministic safeguards, not whether Jev
recognizes sarcasm, excuses, manipulation or conflicting testimony. Current
thresholds are starting policies. Noul is the probability of a yes judgment, not
an emotional intensity measurement; do not silently reuse it as one.

Create a labeled sequence suite: stranger versus friend, accidental injury versus
repeated assault, apology without restitution, fulfilled and broken promises,
anonymous noise, mistaken identity, two witnesses versus one recycled rumor,
correction of a false accusation, secrets shared with different confidants,
interruption during inference, a day later, and save/reload. Check beliefs,
relationships and actions alongside dialogue. Track proposal rejection rate,
contradictions, repeated speech, latency and calls per simulated day. Run a small
approved live sample to calibrate thresholds after the mocked invariants pass.

## Architecture direction

Keep the existing separation: world events -> subjective perception -> bounded
recall -> typed appraisal -> deterministic state/action updates -> speech. Share
that evidence view across conversation, reactions, routines and social encounters.
Extend saved cognition with small explicit data contracts rather than concentrating
more logic in the dialogue manager. A dialogue model may describe a commitment;
only a game action may fulfill it.

TypeSafe references: [state and independent questions](https://docs.typesafe.ai/concepts/state),
[confidence and probability](https://docs.typesafe.ai/confidence). These informed the
separate, dependent grounding call and bounded decision evidence.

## Validation

- Backend: 28 tests, including real Godot HTTP requests against mocked providers.
- Godot: 138 of 139 tests pass. The existing failure is
  `npc_ai_test.gd::test_lateral_attack_position_respects_soft_collision_distance`,
  also present before this branch; combat positioning was not changed.
- Added regressions cover new evidence during both inference stages, bounded retry,
  repeated interruption, obsolete speech after injury/movement, forgotten rumors
  across save/reload, weak-source trust, expiry, altered accounts, evidence
  persistence, and working-memory game time.
- The isolated `npc_safety_world_test.gd` exercises actual damage, an unavailable
  classifier, a delayed routine response, movement through doors into shelter,
  evacuation after a new indoor attack, saved concerns and return to the plan.
- No live provider calls or player-save resets were made for this audit.
