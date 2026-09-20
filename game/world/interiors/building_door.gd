class_name BuildingDoor
extends Node2D

signal used(player: BasePlayer)
var label: String
var _area: Area2D

func _ready() -> void:
	_area = Area2D.new()
	_area.collision_layer = 0
	_area.collision_mask = 1
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(22, 20)
	collision.shape = rectangle
	_area.add_child(collision)
	add_child(_area)
	add_to_group(&"interactables")

func get_interaction_area() -> Area2D:
	return _area

func get_interaction_prompt() -> String:
	return label

func interact(actor: Node) -> void:
	if actor is BasePlayer and actor.health > 0 and not actor.is_input_blocked():
		used.emit(actor)
