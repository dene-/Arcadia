class_name NpcBehaviorTuning
extends Resource

## Task priorities and game-minute timings consumed by NpcBrain and the NPC tasks.

## Game minutes a CAUTION safety task lasts when its own deadline is later.
@export_range(0.0, 120.0, 0.5) var caution_minutes: float = 10.0
## Priority (0..1) of routine tasks.
@export_range(0.0, 1.0, 0.01) var routine_priority: float = 0.3
## Priority (0..1) of tasks that hold a resident still for an external owner.
@export_range(0.0, 1.0, 0.01) var hold_priority: float = 0.4
## Default priority (0..1) of directed-travel adapter tasks.
@export_range(0.0, 1.0, 0.01) var directed_travel_priority: float = 0.6
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
