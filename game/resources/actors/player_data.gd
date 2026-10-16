class_name PlayerData
extends Resource

## Tunable player data consumed by BasePlayer.
@export var display_name: String = "Den"
@export_enum("Male", "Female", "Non-binary") var sex: String = "Male"

## Base walking speed in pixels per second: five 8 px terrain cells per second.
@export var move_speed: float = 40.0
## Multiplier applied to move speed while the run input is held (60 px/s with the default speed,
## so goblins at 64 px/s still catch a runner while orcs cannot).
@export var run_speed_multiplier: float = 1.5
## Multiplier applied to move speed while attacking or using action states.
@export var action_speed_multiplier: float = 0.35
## Seconds before the end of a swing in which a fresh attack press is remembered and replayed.
@export_range(0.0, 0.5, 0.01) var attack_buffer_time: float = 0.2
## Animation speed multiplier used while the player is running.
@export var run_animation_multiplier: float = 1.5
## Maximum health assigned when the player is initialized.
@export var max_health: int = 5
## Base damage applied by the player's normal attack hit box.
@export var attack_damage: int = 1
## Damage multiplier applied during charged attacks.
@export_range(1.0, 10.0, 0.1) var charged_attack_damage_multiplier: float = 2.0
## Seconds the player cannot act after being hit; shorter than the hurt animation.
@export_range(0.0, 0.5, 0.01) var hurt_stun_time: float = 0.3
## Seconds after a hit during which further hits are ignored (the sprite blinks).
@export_range(0.0, 2.0, 0.05) var hurt_invulnerability_time: float = 0.7
## Initial knockback speed away from the attacker; distance is speed^2 / (2 * friction).
@export var hurt_knockback_speed: float = 96.0
## Deceleration applied to hurt knockback in pixels per second squared.
@export var hurt_knockback_friction: float = 576.0
## Seconds without taking damage before health starts to recover.
@export_range(0.0, 60.0, 0.5) var health_regen_delay: float = 8.0
## Seconds per recovered health point once recovery has started; 0 disables recovery.
@export_range(0.0, 60.0, 0.5) var health_regen_interval: float = 5.0
## Collision layer and mask settings for combat hit and hurt boxes.
@export var combat_layers: CombatLayers
## Initial horizontal facing direction when the player spawns.
@export_enum("Left", "Right") var starting_facing: int = 1
## SpriteFrames resource used by the player's AnimatedSprite2D.
@export var sprite_frames: SpriteFrames

func social_identity() -> Dictionary:
	return {"id": "player", "name": display_name, "sex": sex}
