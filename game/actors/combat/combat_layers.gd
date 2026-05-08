class_name CombatLayers
extends Resource

## Collision layer and mask configuration for an actor's hit box and hurt box.

## Physics layer assigned to the actor's outgoing hit box.
@export_flags_2d_physics var hit_box_layer: int = 8
## Physics mask used by the actor's outgoing hit box to find hurt boxes.
@export_flags_2d_physics var hit_box_mask: int = 16
## Physics layer assigned to the actor's incoming hurt box.
@export_flags_2d_physics var hurt_box_layer: int = 16
## Physics mask used by the actor's hurt box to receive hit boxes.
@export_flags_2d_physics var hurt_box_mask: int = 8
