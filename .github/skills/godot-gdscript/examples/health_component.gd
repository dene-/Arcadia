class_name HealthComponent
extends Node

signal health_changed(current: int, maximum: int)
signal died

@export var max_health: int = 100:
	set(value):
		max_health = max(value, 1)
		health = mini(health, max_health)

var health: int = max_health

func _ready() -> void:
	health = max_health
	health_changed.emit(health, max_health)

func take_damage(amount: int) -> void:
	if amount <= 0 or health == 0:
		return

	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)

	if health == 0:
		died.emit()

func heal(amount: int) -> void:
	if amount <= 0 or health == max_health:
		return

	health = mini(health + amount, max_health)
	health_changed.emit(health, max_health)
