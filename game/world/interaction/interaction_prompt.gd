extends CanvasLayer

## NodePath to the player body used for overlap checks and interaction calls.
@export var player_path: NodePath
## Input action that triggers interaction or advances open dialog.
@export var interact_action: StringName = &"player_interact"
## Text prepended to the current target's interaction prompt.
@export var prompt_prefix: String = "[E] "

@onready var prompt_label: Label = $PromptLabel

var _player: Node2D
var _current_target: Node

func _ready() -> void:
	_player = get_node_or_null(player_path) as Node2D
	_set_prompt_target(null)

func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_node_or_null(player_path) as Node2D

	# While a dialog is open, forward confirm input and skip interaction logic.
	var dialog_manager := get_node_or_null("/root/DialogManager")
	if dialog_manager != null and dialog_manager.call("is_dialog_open"):
		if _current_target != null:
			_set_prompt_target(null)
		if Input.is_action_just_pressed(interact_action) or Input.is_action_just_pressed(&"ui_accept"):
			dialog_manager.call("advance_dialog")
		return

	var next_target := _find_closest_interactable()
	if next_target != _current_target:
		_set_prompt_target(next_target)

	if _current_target != null and Input.is_action_just_pressed(interact_action):
		_current_target.call("interact", _player)

func _find_closest_interactable() -> Node:
	if _player == null:
		return null

	var best_target: Node = null
	var best_distance_sq := INF
	for candidate in get_tree().get_nodes_in_group("interactables"):
		if candidate == null or not is_instance_valid(candidate):
			continue
		if not candidate.has_method("get_interaction_area"):
			continue

		var candidate_node := candidate as Node2D
		if candidate_node == null:
			continue

		var interaction_area := candidate.call("get_interaction_area") as Area2D
		if interaction_area == null or not interaction_area.monitoring:
			continue
		if not interaction_area.overlaps_body(_player):
			continue

		var distance_sq := candidate_node.global_position.distance_squared_to(_player.global_position)
		if best_target == null or distance_sq < best_distance_sq:
			best_target = candidate
			best_distance_sq = distance_sq

	return best_target

func _set_prompt_target(target: Node) -> void:
	_current_target = target
	if _current_target == null:
		prompt_label.text = ""
		prompt_label.hide()
		return

	var prompt_text := "Interact"
	if _current_target.has_method("get_interaction_prompt"):
		prompt_text = str(_current_target.call("get_interaction_prompt"))
	if prompt_text.is_empty():
		prompt_text = "Interact"

	prompt_label.text = "%s%s" % [prompt_prefix, prompt_text]
	prompt_label.show()
