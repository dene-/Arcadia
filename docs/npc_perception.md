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

`NpcEventProcessor`, a child owned by the `NpcCognition` autoload, immediately adds each perception to the NPC's bounded **Observations** list. It then calls `/observe` with identity, cognition, existing feelings, prior observations and the new perceived event. There is one assessment worker per NPC and at most two globally. Speech generation has a separate limit of two requests and never holds an assessment worker. A bounded queue drops the oldest observations after eight; an evicted or already-classified event cannot apply a late result.

Jev judges lasting-memory admission, importance, emotional intensity, five relationship directions, and whether to speak. Godot applies bounded changes once. An admitted event becomes an episodic record using the game's perceived text, without asking the dialogue model to invent a memory description. A non-admitted event remains in short-term observations until displaced. Independent events may change feelings even when not admitted to long-term memory.

The Remote Inspector's **Runtime Memory > Observations** shows each perception, sense, status, decision and diagnostics: raw speech probability, delivery eligibility, queue age, assessment latency and final speech result (`displayed`, `not_selected`, expired, blocked or failed). Status is `pending`, `classified`, or `unavailable`. Provider failure leaves the observation available as context without changing relationships or creating a lasting memory. Failed events are not automatically retried. Pending saved observations resume when their NPC loads. Legacy memory saves are imported without losing memories; new saves couple memories to named-NPC world state.

Conversations wait for that NPC's queued assessments before collecting context. Previously assessed perceptions are passed as `past_observations`, without old decisions or diagnostics feeding back into Jev. Their consequences must not be applied again. `current_concerns` highlights recent player-involved perceptions and personal injury while the NPC is still hurt. A greeting cannot implicitly resolve these concerns. The player’s presence is also a recall cue for admitted memories even when the message only says hello. The legacy `record_npc_event(profile, text)` API still queues authored text for the next conversation; combat uses the independent observation path.

## Speech bubbles

Memory admission and speech are separate decisions. Jev considers personality, attention, **Cognition > Verbal Reactivity**, danger and relationship. Verbal reactivity ranges from 0 (silent) to 1 (very inclined to speak); it is context for the classifier, not a random coin flip. The speech threshold is 0.5: Jev must judge speaking more likely than silence. The winning response style is used directly, while relationship changes still require the higher confidence gate.

Only admitted speech requests reach `/react` and the dialogue model. The model receives the updated relationship and filtered recall, and produces one short spoken reaction rather than a full conversation. Existing punctuation normalization applies. A `ReactionBubble` child follows the NPC in world space and hides after 2.5–6 seconds. A reaction does not open dialogue or interrupt movement.

Cooldowns, active conversations, dead/freed NPCs and responses arriving more than 20 seconds after the event suppress speech. Old saved events may still update memory but do not produce belated bubbles. Only a line actually displayed enters recent dialogue. Speech failure does not roll back the already-classified event.

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

Successful event assessments also advance the logical memory turn clock. This is still an abstract memory-aging unit, not elapsed seconds or a world calendar.

## Event architecture and extension

`BaseActor` publishes typed `WorldEvent` facts through the `WorldEvents.occurred` signal. The event holds live participants only during synchronous dispatch. `NpcCognition` applies a registered `NpcPerceptionRouter` adapter to each observer; only the filtered observation enters the asynchronous queue. Actors do not call dialogue UI to report combat.

To add theft, gifts or sounds, publish a new event kind and register its perception adapter with `NpcCognition.perception.register(kind, callable)`. The adapter decides what the individual could perceive and returns `text`, `sense`, `player_involved` and optional `topics`. New kinds require no changes to dialogue, bubble rendering or the assessment queue. Unknown kinds are ignored. Never forward hidden event facts or participant IDs as perceived knowledge. The backend questions must be evaluated with representative examples for each new domain.

`DialogManager` owns conversation presentation. `NpcCognition` owns event assessment and the shared memory store. `NpcWorldSave` owns the atomic persistence boundary. Models can propose interpretations and speech; they cannot change who is alive.

## Named NPC death and restarting

A lethal hit records a named NPC's stable profile ID synchronously, before classification. `user://npc_world.json` saves this authoritative death list and all NPC memories in one atomic file. On restart, dead named NPCs are removed before interaction or observation starts; loading does not replay death events or drop loot again. NPCs without a stable profile ID, including the current monsters, retain their existing restart behavior.

The first load imports `npc_memory.json` if no combined save exists. The legacy file is retained. Historical deaths cannot be reconstructed safely from old prose (victims were anonymous), so death persistence begins with this version. Unsupported or corrupt saves are preserved and block further writes rather than being replaced.

For an explicit fresh NPC world, stop the game and run:

```sh
"$GODOT" --headless --path . --script res://tools/reset_npc_world.gd -- --confirm
```

The command backs up the combined save, then clears deaths and memories together. It does not reset unrelated game systems. Ordinary restart never resets either half. Resurrection is not implemented: a future explicit world operation must update the authoritative lifecycle and emit its own perception event.
