@tool
class_name TownCemetery
extends Node2D

## Fixed plots keep graves in the same place across reloads and population deaths.
const ORIGIN := Vector2(-280, 248)
var residents: Array[String] = []
var _graves: Dictionary[String, Node2D] = {}
var _labels: Dictionary[String, Label] = {}
var _elapsed: float = 0.0

class Grave extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(-5, -3, 11, 8), Color("705332"))
		draw_rect(Rect2(-4, -2, 9, 6), Color("967346"))
		draw_rect(Rect2(-3, -11, 7, 8), Color("373c3c"))
		draw_rect(Rect2(-2, -12, 5, 8), Color("899187"))
		draw_rect(Rect2(-1, -10, 3, 1), Color("b2b2a0"))
		draw_rect(Rect2(0, -10, 1, 4), Color("b2b2a0"))

func _ready() -> void:
	y_sort_enabled = true
	residents.sort()
	var art := RegionArt.new()
	for x: int in range(-304, -120, 24):
		for y: int in [224, 392]:
			art.sprite(self, RegionArt.TOWN_II, Rect2i(8, 8, 24, 8), Vector2(x + 12, y))
	for y: int in range(240, 384, 24):
		art.sprite(self, RegionArt.TOWN_II, Rect2i(40, 8, 8, 24), Vector2(-304, y))
		if y != 360:
			art.sprite(self, RegionArt.TOWN_II, Rect2i(40, 8, 8, 24), Vector2(-120, y))
	RegionArt.barrier(self, Vector2(-304, 304), Vector2(3, 160))
	RegionArt.barrier(self, Vector2(-120, 280), Vector2(3, 112))
	RegionArt.barrier(self, Vector2(-120, 382), Vector2(3, 20))
	for y: int in [224, 392]:
		RegionArt.barrier(self, Vector2(-212, y), Vector2(184, 3))
	var sign := Label.new()
	sign.theme = preload("res://assets/art/ui/theme.tres")
	sign.text = "Cemetery"
	sign.position = Vector2(-260, 212)
	add_child(sign)

func plot_for(id: String) -> Vector2:
	var index: int = maxi(0, residents.find(id))
	return ORIGIN + Vector2((index % 6) * 24, (index / 6) * 24)

func bury(id: String, person_name: String) -> void:
	if _graves.has(id):
		return
	var grave := Grave.new()
	grave.name = id.to_pascal_case() + "Grave"
	grave.position = plot_for(id)
	add_child(grave)
	_graves[id] = grave
	var label := Label.new()
	label.theme = preload("res://assets/art/ui/theme.tres")
	label.text = person_name
	label.position = Vector2(-35, 8)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.z_index = 20
	label.hide()
	grave.add_child(label)
	_labels[id] = label

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.3 or Engine.is_editor_hint():
		return
	_elapsed = 0
	var player: BasePlayer = get_tree().get_first_node_in_group(&"players")
	for id: String in _labels:
		_labels[id].visible = player != null and player.world_space == &"outdoors" \
			and player.global_position.distance_to(plot_for(id)) < 22
