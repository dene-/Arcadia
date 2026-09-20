class_name BuildingDoor
extends Node2D

signal used(player: BasePlayer)
var label: String
## +1 approaches an exterior door from below; -1 approaches an interior exit from above.
var facing: int = 1
var _area: Area2D

func _ready() -> void:
	_area = Area2D.new()
	_area.collision_layer = 0
	_area.collision_mask = 1
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(12, 8)
	collision.shape = rectangle
	_area.add_child(collision)
	add_child(_area)
	add_to_group(&"interactables")

func get_interaction_area() -> Area2D:
	return _area

func get_interaction_prompt() -> String:
	return label

func can_interact(actor: Node2D) -> bool:
	var distance: Vector2 = actor.global_position - global_position
	return absf(distance.x) <= 8 and distance.y * facing >= -2 and distance.y * facing <= 8

func interact(actor: Node) -> void:
	if actor is BasePlayer and actor.health > 0 and not actor.is_input_blocked() and can_interact(actor):
		used.emit(actor)
