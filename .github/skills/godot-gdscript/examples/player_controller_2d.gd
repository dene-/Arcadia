class_name PlayerController2D
extends CharacterBody2D

@export var speed: float = 300.0
@export var jump_velocity: float = -420.0
@export var gravity: float = 1200.0

func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")

	if not is_on_floor():
		velocity.y += gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	velocity.x = direction * speed
	move_and_slide()
