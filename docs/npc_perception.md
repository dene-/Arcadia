# NPC perception and spontaneous reactions

NPCs with a stable profile ID observe successful damage and lethal hits independently of conversations. Both player and NPC damage publish these events. Extra hits during a death animation do not report another kill. `NpcPerception` filters the event for each living observer before any model sees it.

## What an NPC can know

Tune **Npc Data > Perception** in the Inspector:

- **Perception Enabled** enables event observation for this individual.
- **Vision Radius** defaults to 128 pixels. Sight is radial, with an obstruction raycast using **Vision Collision Mask** (default layer 1). It does not currently model a facing cone.
- **Hearing Radius** defaults to 192 pixels. Combat inside this radius can be heard through walls. Hearing exposes fighting sounds, not unseen identities or a confirmed death.
- **Reaction Cooldown** defaults to 8 seconds between unprompted lines.

An injured NPC always feels its own nonlethal injury when perception is enabled. It identifies the attacker only if it can see them. A witness must see the victim to know an injury or death occurred, and must separately see the attacker to attribute it. Hearing alone never changes the relationship toward the player. Visible violence is classified in context: defeating a hostile creature is different from attacking a villager, and neither proves the player's motives.

These are starting tuning values. Hearing does not simulate acoustic attenuation, and perception currently covers combat rather than inventory transfers, theft, movement noise or other world events. Other humans are described as people; sight does not grant knowledge of their names. Individual NPC-to-NPC recognition is a future extension.

## Short-term observations and Jev

`BaseActor` publishes a typed `WorldEvent`; `NpcCognition._on_world_event` filters it through `NpcPerceptionRouter` into one `NpcObservation` per observer who could perceive it. The observation updates the resident's personal knowledge (`NpcCognition.learn`) and is then enqueued in that resident's `NpcEvidenceInbox` by `NpcEventProcessor.observe`. Evidence is durable: it is saved with the mind, deduplicated by observation id, and coalesced when the same incident produces repeated noise.

`NpcEventProcessor`, a child owned by the `NpcCognition` autoload, appraises one inbox item per resident turn through `POST /v2/cognition/appraise` (`NpcDecisionService`, ticket kind `APPRAISE`), then yields to the other residents, who are served round-robin. At most two appraisals run globally (`MAX_WORKERS`). Speech generation has a separate limit of two (`MAX_SPEECH_WORKERS`) and never holds an appraisal worker. The request carries the observation, a bounded state with the resident's relationships and filtered recall, and the versions it read; an answer that arrives after the mind was reloaded or the claim was evicted commits nothing.

Jev judges lasting-memory admission, importance, emotional intensity, per-subject relationship directions and the emotions the evidence causes. `NpcDecisionPolicy.appraisal` turns the answer into an `Appraisal` and Godot applies it once through `NpcMemoryStore.commit_evidence` (an episodic record using the game's perceived text, bounded relationship changes through `NpcIncidentBudget`) and `NpcEventProcessor.feel_appraisal` (emotions). A non-remembered event still affects feelings. A provider failure leaves the evidence `DEFERRED` in the inbox, with no relationship change and no memory, and `NpcCognition` retries it on a real-time ladder (2, 10 and 30 seconds, then every 60 seconds) until a provider answers. `NpcEvidenceInbox.Status` values are `PENDING`, `CLAIMED` and `DEFERRED`. Evidence still queued when the game closes resumes when the resident loads.

The Remote Inspector's **Runtime Memory > Observations** shows each perception with its sense, status and diagnostics: speech eligibility, assessment outcome and latency (`assessment`, `assessment_ms`) and the final speech result (`displayed`, `not_selected`, expired, blocked or failed). The **Cognition** group adds `pending_evidence` counts and the inbox receipts; see the [cognition architecture](npc_cognition_architecture.md#recipe-inspect-a-stuck-resident).

Conversations wait up to `ASSESSMENT_WAIT_MSEC` (2 seconds) for that resident's pending appraisals before collecting context; deferred evidence does not hold dialogue. Previously assessed perceptions are passed as `past_observations`, without old decisions or diagnostics feeding back into Jev. Their consequences must not be applied again. `current_concerns` highlights recent player-involved perceptions and personal injury while the NPC is still hurt, and `personal_concerns` carries unresolved personal state such as grief. A greeting cannot implicitly resolve these concerns. The player's presence is also a recall cue for admitted memories even when the message only says hello. `DialogManager.record_npc_event(profile, text)` still queues authored text for the next conversation; combat uses the independent observation path.

## Speech bubbles

Memory admission and speech are separate decisions. Speech is optional and only for evidence that arrived live in this session: loaded or retried evidence never produces a bubble. After a successful appraisal that the source resident may still speak on (alive, not in dialogue, off cooldown), `NpcEventProcessor` asks `POST /v2/cognition/utterance` whether to speak. Jev considers personality, attention, **Cognition > Verbal Reactivity**, danger and relationship. Verbal reactivity ranges from 0 (silent) to 1 (very inclined to speak); it is context for the classifier, not a random coin flip. `NpcDecisionPolicy.utterance` speaks only when the speak probability reaches `NpcBehaviorTuning.speak_threshold` (0.5) and the chosen intent is permitted by the evidence (`remark`; plus `warn` and `call_for_help` for danger, `protest` for touch, `grieve` for a death).

Only an admitted utterance reaches `POST /v2/dialogue/say`, which writes one short line in the resident's saved voice and decides nothing. Existing punctuation normalization applies. A `ReactionBubble` child follows the NPC in world space and hides after 2.5–6 seconds. A reaction does not open dialogue or interrupt movement.

The cooldown (**Reaction Cooldown**), an active conversation, dead or freed NPCs, a duplicate of the resident's recent line and evidence older than `NpcEventProcessor.REACTION_MAX_AGE_MINUTES` (30 simulation minutes) suppress speech. Old saved events may still update memory but do not produce belated bubbles. Only a line actually displayed enters recent dialogue. Speech failure does not roll back the already-appraised event.

## Relationship effects

Both Jev and the dialogue model receive all six current dimensions and explicit scale descriptions:

| Dimension | Range | Intended influence |
| --- | --- | --- |
| Familiarity | 0–1 | Recognition and how well the NPC knows the player |
| Trust | −1–1 | Openness and willingness to rely on the player |
| Respect | −1–1 | Regard versus contempt |
| Affection | −1–1 | Warmth versus dislike |
| Fear | 0–1 | Caution around the player |
| Suspicion | 0–1 | Doubt about the player's claims and motives |

These dimensions can conflict. Familiarity does not imply liking, and affection does not rule out fear. The model instructions now state these meanings explicitly; the actual quality and speech frequency still need live playtesting. Automated tests use mocked providers, including a captured live Jev assault judgment. An approved live check confirmed an unprompted protest followed by a defensive response to a greeting; this is one representative case, not a guarantee for every personality.

Successful event assessments also advance the memory exchange counter (`NpcMemoryStore.turn`). It is only a sequence number: memory age comes from the world clock (`NpcMemoryStore.world_minute`).

## Event architecture and extension

`BaseActor` publishes typed `WorldEvent` facts through the `WorldEvents.occurred` signal. The event holds live participants only during synchronous dispatch. `NpcCognition` applies a registered `NpcPerceptionRouter` adapter to each observer; only the filtered observation enters the asynchronous queue. Actors do not call dialogue UI to report combat.

To add theft, gifts or sounds, publish a new event kind and register its perception adapter with `NpcCognition.perception.register(kind, callable)`. The adapter decides what the individual could perceive and returns `text`, `sense`, `player_involved` and optional `topics`. New kinds require no changes to dialogue, bubble rendering or the assessment queue. Unknown kinds are ignored. Never forward hidden event facts or participant IDs as perceived knowledge. The backend questions must be evaluated with representative examples for each new domain.

`DialogManager` owns conversation presentation. `NpcCognition` owns event assessment and the shared memory store. `NpcWorldSave` owns the atomic persistence boundary. Models can propose interpretations and speech; they cannot change who is alive.

## Named NPC death and restarting

A lethal hit records a named NPC's stable profile ID synchronously, before classification. `user://npc_world_v2.json` saves this authoritative death list (`dead_npcs`) together with every resident's mind, the town simulation and all NPC memories in one atomic file. On restart, dead named NPCs are removed before interaction or observation starts; loading does not replay death events or drop loot again. NPCs without a stable profile ID, including the current monsters, retain their existing restart behavior.

The first load imports `user://npc_world.json` (v1 world) or `user://npc_memory.json` (memory-only) when no v2 file exists; the legacy files are only read, never rewritten or deleted. Historical deaths cannot be reconstructed safely from old prose (victims were anonymous), so a memory-only import starts with no recorded deaths. Unsupported or corrupt saves are preserved and block further writes rather than being replaced. See [the cognition architecture](npc_cognition_architecture.md#recipe-restore-a-legacy-save) for the load order, migration revisions and restoring a legacy world.

For an explicit fresh NPC world, stop the game and run:

```sh
"$GODOT" --headless --path . --script res://tools/reset_npc_world.gd -- --confirm
```

The command backs up the v2 save as `npc_world_v2.json.reset-<unix time>.bak`, then clears deaths, minds and memories together; legacy files are untouched. `--keep-region` retains the region seed and `--reroll-npcs` generates a new NPC seed. It does not reset unrelated game systems. Ordinary restart never resets either half. Resurrection is not implemented: a future explicit world operation must update the authoritative lifecycle and emit its own perception event.
