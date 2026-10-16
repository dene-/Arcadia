@tool
class_name TownCemetery
extends Node2D

## Fixed plots keep graves in the same place across reloads and population deaths.
## The enclosure's fence belongs to the region's town fencing (RegionTown.CEMETERY).
const ORIGIN := Vector2(-280, 248)
const STONES: Array[String] = ["grave_small", "grave_tall", "grave_wide", "stone_slim"]
var residents: Array[String] = []
var _graves: Dictionary[String, Node2D] = {}
var _labels: Dictionary[String, Label] = {}
var _elapsed: float = 0.0
var _art := RegionArt.new()

func _ready() -> void:
	y_sort_enabled = true
	residents.sort()
	_art.prop(self, "signpost", Vector2(-100, 344))
	# Old weathered markers and wild flowers stand east of the resident plots.
	for index: int in range(5):
		_art.prop(self, STONES[index % STONES.size()], Vector2(-136, 248 + index * 22),
			index % 2 == 1)
	for foot: Vector2 in [Vector2(-288, 236), Vector2(-292, 384), Vector2(-150, 384),
		Vector2(-214, 236)]:
		_art.cover(self, "flowers", foot)

func plot_for(id: String) -> Vector2:
	var index: int = maxi(0, residents.find(id))
	return ORIGIN + Vector2((index % 6) * 24, (index / 6) * 24)

## Deceased id -> world position of each grave dug so far.
func graves() -> Dictionary[String, Vector2]:
	var result: Dictionary[String, Vector2] = {}
	for id: String in _graves:
		result[id] = _graves[id].global_position
	return result

func bury(id: String, person_name: String) -> void:
	if _graves.has(id):
		return
	var grave := Node2D.new()
	grave.name = id.to_pascal_case() + "Grave"
	grave.position = plot_for(id)
	grave.y_sort_enabled = true
	add_child(grave)
	_art.cover(grave, "pebbles", Vector2(0, 6))
	_art.prop(grave, STONES[absi(id.hash()) % STONES.size()], Vector2.ZERO)
	_graves[id] = grave
	var label := Label.new()
	label.theme = preload("res://assets/art/ui/theme.tres")
	label.theme_type_variation = &"HudTag"
	label.text = person_name
	# Night tint must not dim the name; the tag already reads against grass.
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	label.material = unshaded
	label.z_index = 20
	label.hide()
	grave.add_child(label)
	# Centre the name tag under the stone on whole pixels.
	label.reset_size()
	label.position = Vector2(-floorf(label.size.x * 0.5), 8)
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
