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
## Confidence (0..1) a choice or score answer needs; below it the policy uses the neutral fallback.
@export_range(0.0, 1.0, 0.01) var min_confidence: float = 0.65
## Suitability score (0..4) a candidate goal needs to be chosen.
@export_range(0.0, 4.0, 0.25) var goal_min_suitability: float = 2.0
## Game minutes a chosen goal lasts for each duration choice.
@export_range(1.0, 480.0, 1.0) var brief_goal_minutes: float = 20.0
@export_range(1.0, 480.0, 1.0) var ordinary_goal_minutes: float = 45.0
@export_range(1.0, 480.0, 1.0) var extended_goal_minutes: float = 75.0
