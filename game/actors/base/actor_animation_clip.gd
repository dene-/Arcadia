class_name ActorAnimationClip
extends Resource

## Editable clip definition used to build shared actor SpriteFrames resources.

## Animation name exposed by the generated SpriteFrames resource.
@export var animation_name: StringName
## Source PNG sprite sheet used for this animation clip.
@export_file("*.png") var sprite_path: String = ""
## Duration of each frame in seconds.
@export_range(0.01, 2.0, 0.01) var frame_duration: float = 0.2
## First sprite-sheet row to read.
@export_range(0, 16, 1) var source_row: int = 0
## First sprite-sheet column to read on the first row.
@export_range(0, 32, 1) var start_column: int = 0
## Last sprite-sheet row to read; 0 keeps the clip on the source row.
@export_range(0, 16, 1) var end_row: int = 0
## Last sprite-sheet column to read; -1 reads to the end of the row.
@export_range(0, 32, 1) var end_column: int = -1
## Whether the source art faces right before runtime flipping is applied.
@export var source_faces_right: bool = false
## Whether this animation should loop.
@export var loop: bool = true
