class_name PlayerData
extends Resource

## Tunable player data consumed by BasePlayer.

## Base walking speed in pixels per second.
@export var move_speed: float = 72.0
## Multiplier applied to move speed while the run input is held.
@export var run_speed_multiplier: float = 1.75
## Multiplier applied to move speed while attacking or using action states.
@export var action_speed_multiplier: float = 0.35
## Seconds the attack button must be held to start a charged attack.
@export_range(0.1, 2.0, 0.05) var charge_attack_hold_time: float = 0.35
## Animation speed multiplier used while the player is running.
@export var run_animation_multiplier: float = 1.5
## Maximum health assigned when the player is initialized.
@export var max_health: int = 5
## Base damage applied by the player's normal attack hit box.
@export var attack_damage: int = 1
## Damage multiplier applied during charged attacks.
@export_range(1.0, 10.0, 0.1) var charged_attack_damage_multiplier: float = 2.0
## Collision layer and mask settings for combat hit and hurt boxes.
@export var combat_layers: CombatLayers
## Initial horizontal facing direction when the player spawns.
@export_enum("Left", "Right") var starting_facing: int = 1
## SpriteFrames resource used by the player's AnimatedSprite2D.
@export var sprite_frames: SpriteFrames
