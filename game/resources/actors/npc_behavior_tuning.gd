class_name NpcBehaviorTuning
extends Resource

## Task priorities and game-minute timings consumed by NpcBrain and the NPC tasks.

## Game minutes a CAUTION safety task lasts when its own deadline is later.
@export_range(0.0, 120.0, 0.5) var caution_minutes: float = 10.0
## Priority (0..1) of routine tasks.
@export_range(0.0, 1.0, 0.01) var routine_priority: float = 0.3
## Priority (0..1) of conversation tasks.
@export_range(0.0, 1.0, 0.01) var hold_priority: float = 0.4
## Priority (0..1) of recovery duties.
@export_range(0.0, 1.0, 0.01) var duty_priority: float = 0.6
## Priority (0..1) of CAUTION safety tasks. Conversations are refused at or above it.
@export_range(0.0, 1.0, 0.01) var caution_priority: float = 0.7
## Priority (0..1) of SHELTER safety tasks.
@export_range(0.0, 1.0, 0.01) var shelter_priority: float = 0.95
## Game minutes a journey may take before the task fails as unreachable.
@export_range(1.0, 1440.0, 1.0) var travel_timeout_minutes: float = 120.0
## Game minutes a task is protected from being replaced by a comparable one (used from M8).
@export_range(0.0, 120.0, 0.5) var commitment_minimum_minutes: float = 5.0
## Score margin (0..1) a competing goal needs to displace the current one (used from M8).
@export_range(0.0, 1.0, 0.01) var switch_advantage: float = 0.15

## Decision thresholds read by NpcDecisionPolicy. Probability gates (0..1) compare a judgment's noul.
@export_range(0.0, 1.0, 0.01) var danger_threshold: float = 0.5
@export_range(0.0, 1.0, 0.01) var remember_threshold: float = 0.7
## Probability that a heard account is believed before it changes beliefs or dispositions.
@export_range(0.0, 1.0, 0.01) var belief_threshold: float = 0.8
@export_range(0.0, 1.0, 0.01) var engage_threshold: float = 0.5
@export_range(0.0, 1.0, 0.01) var speak_threshold: float = 0.5
## Player speech: whether recalled memories reach the reply, and whether the player is leaving.
@export_range(0.0, 1.0, 0.01) var retrieve_threshold: float = 0.5
@export_range(0.0, 1.0, 0.01) var end_conversation_threshold: float = 0.8
## Confidence (0..1) a choice or score answer needs; below it the policy uses the neutral fallback.
@export_range(0.0, 1.0, 0.01) var min_confidence: float = 0.65
## Suitability score (0..4) a candidate goal needs to be chosen.
@export_range(0.0, 4.0, 0.25) var goal_min_suitability: float = 2.0
## Game minutes a chosen goal lasts for each duration choice.
@export_range(1.0, 480.0, 1.0) var brief_goal_minutes: float = 20.0
@export_range(1.0, 480.0, 1.0) var ordinary_goal_minutes: float = 45.0
@export_range(1.0, 480.0, 1.0) var extended_goal_minutes: float = 75.0
## Game minutes a kept plan or schedule fallback lasts before the next goal decision.
@export_range(1.0, 480.0, 1.0) var plan_kept_minutes: float = 20.0

## Weights (0..1) of named goal components added to normalized suitability (suitability / 4).
@export_range(0.0, 1.0, 0.01) var goal_need_weight: float = 0.4
@export_range(0.0, 1.0, 0.01) var goal_obligation_weight: float = 0.2
@export_range(0.0, 1.0, 0.01) var goal_concern_weight: float = 0.4
@export_range(0.0, 1.0, 0.01) var goal_commitment_weight: float = 0.5
@export_range(0.0, 1.0, 0.01) var goal_personality_weight: float = 0.3
## Game minutes an absent relative's search waits after every known place was searched.
@export_range(1.0, 1440.0, 1.0) var search_defer_minutes: float = 180.0
## Fear intensity (0..1) at or above which goal inertia is bypassed.
@export_range(0.0, 1.0, 0.01) var urgent_fear: float = 0.6

## Needs run from 0 (satisfied) to 1 (pressing). Rates are per game minute.
@export_range(0.0, 0.1, 0.00001) var hunger_per_minute: float = 1.0 / 480.0
@export_range(0.0, 0.1, 0.00001) var fatigue_awake_per_minute: float = 1.0 / 1440.0
@export_range(0.0, 0.1, 0.00001) var fatigue_sleep_relief_per_minute: float = 1.0 / 480.0
## Social need rises by this rate multiplied by (social_rate_base + sociability).
@export_range(0.0, 0.1, 0.00001) var social_per_minute: float = 1.0 / 2880.0
@export_range(0.0, 2.0, 0.01) var social_rate_base: float = 0.5
## Hunger after a completed meal.
@export_range(0.0, 1.0, 0.01) var meal_hunger: float = 0.15
## Social need removed by one delivered meaningful exchange.
@export_range(0.0, 1.0, 0.01) var exchange_social_relief: float = 0.1
## Social need removed by a wordless greeting while the dialogue providers are unavailable.
@export_range(0.0, 1.0, 0.01) var greeting_social_relief: float = 0.08
## Real seconds two residents stand facing each other for such a greeting.
@export_range(0.5, 20.0, 0.1) var greeting_min_seconds: float = 3.0
@export_range(0.5, 20.0, 0.1) var greeting_max_seconds: float = 6.0
## Neutral needs of a new or legacy mind (not reconstructed history).
@export_range(0.0, 1.0, 0.01) var initial_hunger: float = 0.25
@export_range(0.0, 1.0, 0.01) var initial_fatigue: float = 0.2
@export_range(0.0, 1.0, 0.01) var initial_social: float = 0.3
## Need bands: below moderate is "low"; at or above pressing is "pressing".
@export_range(0.0, 1.0, 0.01) var need_moderate: float = 0.4
@export_range(0.0, 1.0, 0.01) var need_pressing: float = 0.75

## Emotion half-lives in game minutes, measured from the cause's onset.
@export_range(1.0, 10080.0, 1.0) var fear_half_life_minutes: float = 15.0
@export_range(1.0, 10080.0, 1.0) var anger_half_life_minutes: float = 60.0
@export_range(1.0, 10080.0, 1.0) var relief_half_life_minutes: float = 20.0
@export_range(1.0, 10080.0, 1.0) var grief_half_life_minutes: float = 2880.0
## Emotion bands: below mild is "none" (and the cause is no longer listed); at or above strong is "strong".
@export_range(0.0, 1.0, 0.01) var emotion_mild: float = 0.1
@export_range(0.0, 1.0, 0.01) var emotion_strong: float = 0.5
## Pain (1 - health ratio) bands, same shape as need bands.
@export_range(0.0, 1.0, 0.01) var pain_moderate: float = 0.25
@export_range(0.0, 1.0, 0.01) var pain_pressing: float = 0.6

## Priorities (0..1) of commitments opened by known family events.
@export_range(0.0, 1.0, 0.01) var endangered_check_priority: float = 0.8
@export_range(0.0, 1.0, 0.01) var bereaved_check_priority: float = 0.5
@export_range(0.0, 1.0, 0.01) var visit_grave_priority: float = 0.4

## A resident performing an activity takes a short idle step about this often (game minutes).
## Zero disables idle steps.
@export_range(0.0, 240.0, 1.0) var fidget_min_minutes: float = 18.0
@export_range(0.0, 240.0, 1.0) var fidget_max_minutes: float = 55.0
## Farthest an idle step goes from the scheduled spot (pixels; at most the presence radius).
@export_range(8.0, 12.0, 0.5) var fidget_radius: float = 12.0
## A guard lingers at a patrol stop for this many game minutes before walking on.
@export_range(0.0, 60.0, 0.5) var patrol_dwell_min_minutes: float = 6.0
@export_range(0.0, 60.0, 0.5) var patrol_dwell_max_minutes: float = 15.0
## A daytime rest is only offered when the plan leaves this many game minutes before it changes.
@export_range(0.0, 240.0, 1.0) var rest_min_minutes: float = 45.0
