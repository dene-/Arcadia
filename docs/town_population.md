# Rekala households, watch and economy

Rekala now contains 33 residents in 12 households: the nine existing specialists,
24 additional relatives and ordinary workers, five children and two guards.
Three new homes expand the western and southern neighborhoods. Existing local
relatives mentioned in biographies become residents; widowed and absent-family
details remain intact. Names, clothing, personalities and social ties are stable
for a saved seed. Everyone uses the existing chat, perception and memory system.

## Playing and inspecting

- Guards patrol on staggered daytime/evening shifts and return home off duty.
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
| `BaseNpc` | Explicit combat target and existing pathing/melee mechanics |
| `TownEconomy` | Work accounting, production, input goods, consumption and budgets |

Add population templates with stable IDs, household membership and reciprocal kin
links. A new household also needs an exterior entry in `RegionLayout.HOMES`.
Occupation-specific schedules and work locations live separately from identity.
Production recipes and baseline prices belong to `TownEconomy`, not actor states.
Changes to existing identity templates require a save migration rather than
renaming persisted IDs. Existing feelings are preserved when new neighbors arrive.

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
`town_life_world_test.gd`, `town_watch_test.gd` and `combat_contact_test.gd`
integration scripts under `tests/integration/`. Use `--fixed-fps 60` for deterministic
fast headless runs. Backend tests include mocked Jev intent validation and an HTTP
town-life scenario; no live provider check is required.
