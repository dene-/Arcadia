class_name NpcData
extends Resource

## Tunable NPC data consumed by BaseNpc.

const DropTableResource = preload("res://game/items/drops/drop_table.gd")

## Base walking speed in pixels per second.
@export var move_speed: float = 28.0
## Multiplier applied to move speed while running or chasing.
@export var run_speed_multiplier: float = 1.65
## Multiplier applied to move speed while performing non-stationary actions.
@export var action_speed_multiplier: float = 0.35
## Distance from a patrol target that counts as arrival.
@export var arrival_distance: float = 3.0
## Radius around spawn used when choosing random roam targets.
@export var roam_radius: float = 24.0
## Chance that a roaming NPC chooses run instead of walk.
@export var run_chance: float = 0
## Minimum and maximum idle duration before choosing a new roam target.
@export var idle_duration_range: Vector2 = Vector2(0.8, 1.8)
## Local-space patrol points visited before random roaming is used.
@export var patrol_points: Array[Vector2] = []
## Maximum health assigned when the NPC is initialized.
@export var max_health: int = 3
## Damage applied by this NPC's hit box during attacks.
@export var attack_damage: int = 1
## Initial knockback speed applied when this NPC is hurt.
@export var hurt_knockback_speed: float = 70.0
## Deceleration applied to hurt knockback each physics frame.
@export var hurt_knockback_friction: float = 360.0
## Number of blood particles emitted when this NPC is hit.
@export_range(0, 32, 1) var blood_particle_count: int = 30
## Maximum starting speed for blood particles.
@export var blood_particle_speed: float = 72.0
## Spread angle for blood particles in degrees.
@export_range(0.0, 90.0, 1.0) var blood_particle_spread_degrees: float = 25.0
## Lifetime of each blood particle burst in seconds.
@export_range(0.1, 1.5, 0.05) var blood_particle_lifetime: float = 0.38
## Downward gravity applied to blood particles.
@export var blood_particle_gravity: float = 60.0
## Tint used by emitted blood particles.
@export var blood_color: Color = Color(0.76, 0.08, 0.08, 0.95)
## Collision layer and mask settings for combat hit and hurt boxes.
@export var combat_layers: CombatLayers
@export_category("Enemy AI")
## Enables enemy behavior: player detection, chasing, attacking, and enemy grouping.
@export var ai_enabled: bool = false
## Group name used to find potential targets.
@export var target_group: StringName = &"players"
## Maximum distance at which a target can be acquired.
@export_range(0.0, 256.0, 1.0) var detection_range: float = 72.0
## Distance at which the current target is forgotten.
@export_range(0.0, 320.0, 1.0) var lose_interest_range: float = 112.0
## Distance at which the enemy stops chasing and starts attacking.
@export_range(1.0, 64.0, 1.0) var attack_range: float = 13.0
## Horizontal offset beside the target where this enemy tries to attack from.
@export_range(1.0, 64.0, 1.0) var attack_side_offset: float = 12.0
## Maximum vertical mismatch allowed before the enemy repositions beside the target.
@export_range(0.0, 32.0, 1.0) var attack_vertical_tolerance: float = 4.0
## Distance from the preferred side position that still counts as attack-ready.
@export_range(0.0, 16.0, 1.0) var attack_slot_arrival_distance: float = 3.0
## Minimum horizontal spacing kept from the target before attacking beside it.
@export_range(0.0, 32.0, 1.0) var soft_collision_distance: float = 12.0
## Minimum seconds between attack attempts.
@export_range(0.1, 5.0, 0.05) var attack_cooldown: float = 0.9
## Requires a clear raycast from the enemy to the target before detection.
@export var require_line_of_sight: bool = true
## Physics mask used by the detection raycast.
@export_flags_2d_physics var line_of_sight_collision_mask: int = 1
## Local offset from the NPC origin where sight rays begin.
@export var line_of_sight_origin_offset: Vector2 = Vector2(0.0, -4.0)
## Local offset from the target origin where sight rays end.
@export var line_of_sight_target_offset: Vector2 = Vector2(0.0, -4.0)
## Loot table rolled once when this NPC dies.
@export var drop_table: DropTableResource
@export_category("Interaction")
## Enables the interaction area and dialog entry point for this NPC.
@export var interaction_enabled: bool = true
## Text shown by the interaction prompt.
@export var interaction_text: String = "Talk"
## Allows DialogManager to request backend dialog for this NPC.
@export var able_to_chat: bool = false
## Initial horizontal facing direction when the NPC spawns.
@export_enum("Left", "Right") var starting_facing: int = 1
## Optional dialog/backend profile data for conversational NPCs.
@export var profile: NpcProfile
## SpriteFrames resource used by this NPC's AnimatedSprite2D.
@export var sprite_frames: SpriteFrames
