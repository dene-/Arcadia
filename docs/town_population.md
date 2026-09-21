# Rekala households, watch and economy

Rekala now contains 33 residents in 12 households: the nine existing specialists,
24 additional relatives and ordinary workers, five children and two guards.
Three new homes expand the western and southern neighborhoods. Existing local
relatives mentioned in biographies become residents; widowed and absent-family
details remain intact. Names, clothing, personalities and social ties are stable
for a saved seed. Everyone uses the existing chat, perception and memory system.

## Playing and inspecting

- Guards patrol on day and overnight shifts and return home off duty. The Ash
  household guard works 18:30–06:30 and sleeps 07:30–15:30. The Voss guard starts
  at 06:00. Saved plans migrate without rerolling identities or relationships.
  Weapon brandishing near residents earns a warning. Witnessed repeated assault
  or a killing permits combat. Guards protect residents and the player from
  witnessed monster attacks; helping fight a monster is not a crime.
- Press **G** to surrender before or during enforcement. In a guard conversation,
  a confident Jev `SURRENDER` intent also accepts ordinary-language surrender.
  Dialogue generation cannot authorize this action by inventing response metadata.
  Surrender cancels the target and active hitbox. A new assault can escalate again.
  Surrender does not erase memories or automatically restore trust.
- Hearing fighting causes investigation of its location, without identifying an
  unseen attacker. Each guard owns their own reports. An active incident expires
  after 30 game minutes without new evidence; historical reports remain available
  as context, bounded to 64 entries. There are no arrests, fines or imprisonment.
- Families have separate beds in a shared home, coordinated meals, explicit kin
  links and shared accounts. Children attend outdoor lessons and play; retirees
  do not receive adult work options. Sleep and guard duty are bounded by schedules.
- The Remote inspector's existing **Runtime Life** dictionary includes household,
  family members, household economy and a guard's enforcement records. The saved
  world contains the population, economy ledger, accounts, stocks and justice data.

## Ownership and extension points

| Owner | Responsibility |
| --- | --- |
| `TownPopulation` | Seeded identities, households, kinship and runtime profiles |
| `TownResidentSchedule` | Age and occupation obligations, shared meal times |
| `TownLifeState` | Daily plans and mutable social ties; backfills new neighbors |
| `TownBuildings` / `NpcInterior` | Shared spaces, per-person beds and door transfers |
| `TownJustice` | Serializable per-guard evidence, warnings and surrender |
| `TownWatch` | Visible/heard events, patrol routes, enforcement and surrender UI |
| `NpcAlertResponse` | Real-time stirring, startle and orientation beats before movement |
| `TownDeaths` | Serializable body locations, discovery, reporting and burial stages |
| `TownFunerals` | Witness errands, guard recovery, interruptions and perceived aftermath |
| `TownCemetery` / `NpcRemains` | Fixed named graves, intact fallen poses and carried shrouds |
| `BaseNpc` | Explicit combat target and existing pathing/melee mechanics |
| `TownEconomy` | Work accounting, production, input goods, consumption and budgets |

Add population templates with stable IDs, household membership and reciprocal kin
links. A new household also needs an exterior entry in `RegionLayout.HOMES`.
Occupation-specific schedules and work locations live separately from identity.
Production recipes and baseline prices belong to `TownEconomy`, not actor states.
Changes to existing identity templates require a save migration rather than
renaming persisted IDs. Existing feelings are preserved when new neighbors arrive.

## Danger and death

Direct injury still causes an immediate physical response. Other sleepers stir
for 1.2–3.4 real seconds, then take a separate moment to get their bearings.
Orientation varies with the resident and their courage. Repeated sounds do not
restart the timer indefinitely. Hearing supplies a disturbance, not knowledge of
an unseen attacker. Jev continues to assess memories, feelings, speech and safety;
physical reaction timing does not depend on provider latency. Brief caution keeps
a newly awakened resident listening before an ordinary routine can send them back
to bed. Shelter routes wait for the reaction beat and use the existing doors.

New town-resident deaths leave a persistent body, frozen before the original art's
disappearance frames. An awake resident must see it through an unobstructed sight
line to discover it. A witness pauses, seeks a guard using ordinary paths and
reports in person. A guard can also discover a body directly. Seeing remains does
not identify a killer or authorize attacking the player.

The guard visits the scene, waits while danger persists, spends six game minutes
recovering the body, carries a shrouded body through the doors to the southwest
cemetery, and spends twelve game minutes at the grave. Combat interrupts carrying;
a dead carrier leaves the body for physical rediscovery. With no surviving guard,
the remains stay in the world. Recovery outranks ordinary errands and social
chatter; immediate enforcement outranks recovery. Saved progress resumes after a
restart, and graves use stable resident plots with names visible nearby.

Discovery, an actual report and witnessed burial enter the existing cognition and
rumor pipeline. Dialogue/routine context includes only deaths the resident has
learned about, together with their family connection. This is a first recovery
and burial flow, not a funeral-attendance or criminal-investigation simulation.
Older death flags remain respected; missing historical body locations are not
invented. Monsters retain their existing death cleanup.

## Economy foundations

Actual time spent at work or on patrol accrues work credit. Once per completed
game day, living adults produce goods or provide services. Processing recipes
consume stock inputs; public treasury payments credit the shared household account.
Households buy food from stock, and missing portions are recorded as shortages.
Children do not earn wages. Coins transfer between accounts and the treasury;
simulation does not mint wages. Initial household endowments and market stock are
seed capital. Prices, yields and wages are initial tuning values.

Settlement is idempotent across saves/restarts. There is no offline production,
trading UI, player purchasing, hunger damage, debt or automatic economy-driven
movement yet. Household shortages and finances are available to NPC dialogue and
routine decisions. The ledger keeps the latest 96 entries.

## Saves and art

Optional save blocks upgrade older worlds without deleting memories, resetting
time or resurrecting dead residents. Validation occurs before committing any part
of a load. Automated tests use temporary saves and mocked providers.

New source art comes from Krishna Palacio's owned
[A Myriad Of NPCs](https://krishna-palacio.itch.io/minifantasy-npcs)
and [True Heroes](https://krishna-palacio.itch.io/minifantasy-true-heroes) packs.
Generic animation layers provide varied townspeople; the Rogue animations provide
the watch's combat animations. The base human sprites also represent children;
there is no separate child animation set in these packs. Source sheets and license
copies stay in ignored `assets/art/world_packs/residents/`, outside Git.

On another licensed checkout, download the two owned ZIPs and run:

```sh
"$GODOT" --headless --path . --script res://tools/art/import_resident_packs.gd -- /path/to/downloads
"$GODOT" --headless --editor --path . --quit
```

Then run the unit suite and the `town_interiors_test.gd`,
`town_life_world_test.gd`, `town_watch_test.gd`, `town_emergency_flow_test.gd`
and `combat_contact_test.gd`
integration scripts under `tests/integration/`. Use `--fixed-fps 60` for deterministic
fast headless runs. Backend tests include mocked Jev intent validation and an HTTP
town-life scenario; no live provider check is required.
