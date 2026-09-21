# Town life

The saved world seed generates each resident's personality, speech style, initial relationships and daily preferences. Names, jobs, biographies and the town layout remain authored. Personalities and relationships persist; plans vary by resident and day. Den's name and sex are editable on `PlayerData` (`Den`, `Male` by default).

Each saved personality also has a stable `voice`: register, cadence, verbosity, directness, humor, disclosure and question frequency. Most choices follow the resident's temperament; register and humor use a separate seeded draw. Older personalities gain these choices once without rerolling traits, relationships or memories. The runtime `NpcProfile.voice` dictionary is visible in the Remote Inspector and travels with the profile to every provider request.

The backend's `npc-voice.js` compiles those closed choices into concrete phrasing guidance shared by player dialogue, event reactions and resident conversations. Response modes and social tones describe the current disposition, while voice governs how that person expresses it. Shared prompts allow different sentence rhythms and levels of elaboration. Voices are tendencies, not catchphrases or mandatory jokes; evidence limits, relationship context, direct speech, farewell behavior and bubble size limits still apply. Mocks verify propagation and save stability, not the dialogue model's actual prose quality.

## Ownership

| Component | Responsibility |
| --- | --- |
| `TownLife` | Scene-owned clock, place catalog, bounded decision scheduling and save coordination |
| `TownLifeState` | Saved personalities, plans, relationship graph, positions and social history |
| `NpcTemperament` / `NpcRoutinePlan` | Seeded personality generation and daily preferences |
| `WorldNavigation` / `TownNavigation` | Scene-owned outdoor grid, per-room grids, static walkability and space reservations |
| `ActorRoute` / `ActorCrowd` | Cached A* following and predictive nearby-body steering |
| `NpcPursuit` | Enemy pursuit routes and leased lateral attack approaches |
| `TownBuildings` / `NpcInterior` | Enterable furnished rooms, door transitions and navigation between spaces |
| `NpcDailyRoutine` | Routine destination and hold state; delegates locomotion to the shared route component |
| `TownEncounters` | Nearby two-way social sessions, model calls and interruption guards |
| `TownRumors` | Per-person accounts, provenance, confidence, expiry and loop prevention |
| `NpcMemoryStore` | Long-term admission and bounded changes to feelings toward the player |
| `NpcAmbientHistory` | Short-lived audible speech context for varied reactions; never creates factual memories |

`DialogManager` continues to own only player conversation UI. Town life is attached to the generated region, not another Autoload. New activities can extend the place catalog and routine candidates without changing actor states or dialogue UI.

## Routine and movement

The clock advances 1.5 game minutes per real second by default, with a day/night tint. It pauses while the game is closed. Breakfast and lunch have varied times and locations; residents have their own workplaces and several leisure venues. Jev selects from supplied, feasible activities and a bounded duration. Up to four routine decisions run concurrently. Unavailable or invalid decisions fall back to the day's plan.

Moving bodies are excluded from the static navigation bake. Live routes detour around residents and Den, destinations reserve personal space, and local steering lets approaching walkers yield. Blocked routes are retried. Optional visits and social destinations avoid crowded venues. Encounters arise from proximity along routes or at destinations, rather than a global gathering command.

The outdoor grid covers the whole generated region, including enemy forests, and exists even with town life disabled. Interiors have separate grids. `ActorFootprint` rounds each scene's foot collider while preserving its extents and offset. Actor bodies use physics layer 2 and collide with layers 1 (world) and 2 (actors); interaction areas detect layer 2. Weapon/hurtbox layers are independent. Grid clearance derives from the largest initial NPC footprint, plus a small margin. New actor sizes or runtime changes to static geometry require rebuilding the relevant grid.

Routes remain cached while the actor makes progress. Changed destinations or lack of progress trigger replanning, with a one-second retry cooldown and a budget of four route requests per physics frame per grid. Clear intermediate waypoints can be skipped using a footprint sweep. `ActorCrowd` builds one spatial snapshot per frame, predicts nearby contacts, favors passing on the right and allows a stable participant to back away from a bottleneck. NPC steering accelerates gradually; Den's input remains direct. Idle, awake, unlocked residents step aside early enough for a running player. A completely blocked passage can still require waiting for another actor to move.

Enemies share this navigation for both roaming and pursuit. Two attackers can claim opposite lateral approaches while others wait at separate nearby positions. Claims expire or release when pursuit ends. Approaches and actual melee contacts require an unobstructed line through world geometry; each target receives at most one hit per swing. Preferred spacing guides the approach without preventing attacks against closer opponents. Attack readiness is also checked immediately after movement, avoiding endless tracking of a running target.

Door transitions check the arriving actor's actual collider and current occupancy. If the threshold is occupied, they try offsets within 12 pixels. A fully blocked arrival leaves the actor, space and camera unchanged; residents retry and Den can interact again. Successful transitions move the actor's navigation registration between spaces.

`TownNavigation.metrics()` reports build time, route count/time, steering count/time and nearby-body checks. These are diagnostic totals, not frame-rate measurements. The isolated three-enemy regression uses three searches over 12 simulated seconds at 60 and 120 physics ticks; the corridor scenario completes with two searches. The full 3,522-tree test region's outdoor bake measured about 60 ms locally; machines and scene density will vary.

Each resident has an enterable home and shop, furnished with a bed, meal table and work area. Press the existing interact key (E) near the exterior door to enter, and near the interior door to leave. Rooms use the owned Towns/Towns II artwork; run the world-pack importer when installing those assets on another checkout. Doors are currently unlocked.

Room dimensions and working/sleeping zones vary by trade; stable seeded details personalize them. `TownInteriorLayout` owns complete furniture atlas crops and matching footprints. Door interaction and arrival use the visible threshold, with a short approach range. Interaction prompts use the native theme font at the bottom of the viewport.

Residents walk through their own doors to work, eat and rest. Rest places them in bed with a sleeping pose. Interaction or nearby combat wakes them, and dialogue receives the room, activity and recent awakening. Sleeping residents cannot see events or initiate speech. Separate rooms have independent navigation and perception boundaries; actors keep their identity and cognition through transitions. Saved room membership restores residents indoors after restarting. Crafting and food consumption are not simulated.

Activity durations stop at the next daily schedule boundary. Morning wakeups run locally even while a provider is unavailable or slow; stale nighttime decisions cannot put residents back to bed. Daytime rests are bounded breaks, with no consecutive REST selection when the schedule calls for another activity.

Wake context includes its cause and expires after five game minutes, 30 real seconds, or leaving the room. Waking does not imply morning. Door transitions update indoor/outdoor lighting immediately, using the current clock.

## Social decisions and knowledge

Residents initially know the names, jobs and homes of the other townspeople. Directed relationships vary in familiarity, trust and affection. Knowing a neighbor does not reveal their private memories, current position or death automatically.

| Endpoint | Decision |
| --- | --- |
| `POST /life/routine` | Supplied activity choice and duration |
| `POST /life/social` | Engage, topic, tone and willingness to linger |
| `POST /life/listen` | Listener belief, memory admission, importance and bounded relationship effects |
| `POST /life/say` | Spoken words for an admitted exchange, using the dialogue provider |

Conversations require proximity, line of sight, availability and individual cooldowns. At most three pairs converse concurrently. The listener gets a turn after a greeting. Resting residents do not initiate these encounters. Injury, death, player dialogue, separation and a session deadline invalidate pending results and release both actors. Model refusal or service failure never fabricates a conversation or new information.

Audible exchanges generate speech bubbles when Den is nearby. Offscreen exchanges use the same social and listener decisions but omit dialogue generation. For an audible rumor, successful speech must precede the knowledge transfer. Speech stays direct, uses ASCII quote normalization, and follows the existing dialogue style rules. Bubbles fit their text up to `maximum_width`, wrap vertically and use the theme font at its native size; neither text nor its parent is scaled to fit.

Ambient dialogue has its own voice guidance: one immediate thought shaped by personality, familiarity and circumstance. Witnesses receive their own relationship to recognized participants; hearing alone never supplies identities. Each awake listener keeps at most six nearby utterances for 45 seconds so generation can respond to what others just said. Exact repeated long combat reactions are suppressed even when simultaneous requests return the same words. Player dialogue displays the speaker's actual profile name above the text at the native font size.

Only perceived events and admitted conversation claims/statements enter the rumor ledger. Each account retains its original observer, immediate source, chain, evidence basis, confidence and event ID. A listener cannot learn an account the speaker does not know. Accounts cannot circulate back through the same chain or gain confidence through repetition. Chains stop after four transfers. Each person keeps at most 32 recent accounts, expiring after three game hours or seven game days depending on importance/admission. Memory admission remains a separate listener decision.

Hearsay enters memory as `hearsay`, not an eyewitness event. Believed reports can change trust toward Den by at most 0.03 per admitted transfer; conversations can slightly change affection and familiarity between residents. World facts such as death are never changed by rumors. Town knowledge, activity, social history and attributed rumors reach subsequent player dialogue. Current concerns and feelings toward Den also inform routine and social decisions.

## Persistence and debugging

Town state is an optional `world.life` block in `user://npc_world.json`, saved atomically with memories and named deaths. Older saves load without a reset. Daily-plan revisions regenerate plans while keeping personalities, relationships and memories. No wall-clock catch-up is performed on restart. The existing explicit world reset clears life state together with the other world data.

With the game stopped, `tools/reset_npc_world.gd -- --confirm --keep-region` resets NPC memories, deaths and social/routine state while retaining the forest seed. The old save is backed up before replacement; omitting `--keep-region` also resets the region seed.

In Godot's Remote Inspector, select a resident and inspect **Runtime Life**: current activity/destination, personality, known townspeople and relationships, recent social exchanges, rumors and routine decision. `social_status` distinguishes assessment, declined encounters, unavailable services, displayed bubbles and offscreen exchanges. **Runtime Memory** shows admitted hearsay and feelings toward Den. Runtime diagnostics are removed from model context.

Restart the backend after changing its routes. An old server can answer `/chat` normally while returning 404 for `/life/social`, preventing social speech.

## Validation

All automated provider tests use mocks and temporary saves. With Godot installed:

```sh
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . --log-file /tmp/arcadia-unit.log --script res://tests/test_runner.gd
"$GODOT" --headless --path . --fixed-fps 60 --log-file /tmp/arcadia-traffic.log --script res://tests/integration/town_traffic_test.gd
"$GODOT" --headless --path . --fixed-fps 60 --log-file /tmp/arcadia-contacts.log --script res://tests/integration/actor_contacts_test.gd
"$GODOT" --headless --path . --fixed-fps 60 --log-file /tmp/arcadia-navigation.log --script res://tests/integration/actor_navigation_test.gd -- 60
"$GODOT" --headless --path . --fixed-fps 60 --log-file /tmp/arcadia-life.log --script res://tests/integration/town_life_world_test.gd
"$GODOT" --headless --path . --fixed-fps 60 --log-file /tmp/arcadia-interiors.log --script res://tests/integration/town_interiors_test.gd
cd tools/server
GODOT="$GODOT" npm test
```

The full-world HTTP test needs the locally installed licensed world assets and skips when those assets or `GODOT` are absent. It checks real actor movement, destination arrival, social speech, rumor transfer and save reload through mocked providers. The traffic scenario checks two opposing walkers passing a stationary actor. Unit tests cover source attribution, cancellation, save validation, seeded personalities, destination spacing and dynamic bubble sizing. Actual Jev activity preferences and generated prose still need playtesting; mocks validate the application behavior and contracts.

The contacts scenario exercises real player input at walking/running speeds and opposing NPCs in a corridor with a passing bay. The navigation scenario checks a wall detour and a pack reaching both attack approaches; pass `30`, `60` or `120` after `--` and match `--fixed-fps` to check different physics rates. Unit tests cover rounded footprints, cached routes, search budgets, overlap escape, blocked landings, wall occlusion and single-hit swings. The interior scenario also checks that a blocked entry preserves player position and camera limits. Stationary blockers keep their physics body enabled; disabling their entire process mode would remove the collision being tested.
