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

`NpcEventProcessor`, a child owned by `DialogManager`, immediately adds each perception to the NPC's bounded **Observations** list. It then calls `/observe` with identity, cognition, existing feelings, prior observations and the new perceived event. There is one worker per NPC and at most two workers globally. A bounded queue drops the oldest observations after eight; an evicted or already-classified event cannot apply a late result.

Jev judges lasting-memory admission, importance, emotional intensity, five relationship directions, and whether to speak. Godot applies bounded changes once. An admitted event becomes an episodic record using the game's perceived text, without asking the dialogue model to invent a memory description. A non-admitted event remains in short-term observations until displaced. Independent events may change feelings even when not admitted to long-term memory.

The Remote Inspector's **Runtime Memory > Observations** shows each perception, sense, status and resulting decision. Status is `pending`, `classified`, or `unavailable`. Provider failure leaves the observation available as context without changing relationships or creating a lasting memory. Failed events are not automatically retried. Pending saved observations resume when their NPC loads. Existing version-1 saves gain empty observation fields on load without losing memories.

Conversations wait for that NPC's queued assessments before collecting context. Previously assessed observations are passed as `past_observations`, not fresh events, so their consequences must not be applied again. The legacy `record_npc_event(profile, text)` API still queues authored text for the next conversation; combat uses the independent observation path.

## Speech bubbles

Memory admission and speech are separate decisions. Jev considers personality, attention, **Cognition > Verbal Reactivity**, danger and relationship. Verbal reactivity ranges from 0 (silent) to 1 (very inclined to speak); it is context for the classifier, not a random coin flip. The starting speech threshold is 0.75.

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

These dimensions can conflict. Familiarity does not imply liking, and affection does not rule out fear. The model instructions now state these meanings explicitly; the actual quality and speech frequency still need live playtesting. Automated tests use mocked providers.

Successful event assessments also advance the logical memory turn clock. This is still an abstract memory-aging unit, not elapsed seconds or a world calendar.
