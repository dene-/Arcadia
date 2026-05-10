extends "res://tests/test_case.gd"

const BaseNpcResource = preload("res://game/actors/npcs/base_npc.gd")
const NpcDataResource = preload("res://game/resources/actors/npc_data.gd")

var _npc: BaseNpc

func before_each() -> void:
	_npc = BaseNpcResource.new()
	_npc.npc_data = NpcDataResource.new()
	_npc.npc_data.attack_range = 13.0
	_npc.npc_data.attack_side_offset = 12.0
	_npc.npc_data.attack_vertical_tolerance = 4.0
	_npc.npc_data.attack_slot_arrival_distance = 3.0
	_npc.npc_data.soft_collision_distance = 12.0

func after_each() -> void:
	_npc.free()

func test_lateral_attack_position_prefers_current_left_side() -> void:
	_npc.global_position = Vector2(-30.0, 0.0)

	assert_eq(_npc.get_lateral_attack_position(Vector2.ZERO), Vector2(-12.0, 0.0))

func test_lateral_attack_position_prefers_current_right_side() -> void:
	_npc.global_position = Vector2(30.0, 0.0)

	assert_eq(_npc.get_lateral_attack_position(Vector2.ZERO), Vector2(12.0, 0.0))

func test_lateral_attack_position_uses_facing_when_above_or_below_target() -> void:
	_npc.global_position = Vector2(0.0, -20.0)
	_npc.facing = BaseActor.Facing.LEFT

	assert_eq(_npc.get_lateral_attack_position(Vector2.ZERO), Vector2(-12.0, 0.0))

func test_lateral_attack_requires_vertical_alignment() -> void:
	_npc.global_position = Vector2(-12.0, -6.0)

	assert_false(_npc.is_in_lateral_attack_position(Vector2.ZERO))

	_npc.global_position = Vector2(-12.0, -3.0)

	assert_true(_npc.is_in_lateral_attack_position(Vector2.ZERO))

func test_lateral_attack_rejects_top_or_bottom_range() -> void:
	_npc.global_position = Vector2(0.0, -3.0)

	assert_false(_npc.is_in_lateral_attack_position(Vector2.ZERO))

func test_lateral_attack_position_respects_soft_collision_distance() -> void:
	_npc.npc_data.attack_side_offset = 8.0
	_npc.global_position = Vector2(-30.0, 0.0)

	assert_eq(_npc.get_lateral_attack_position(Vector2.ZERO), Vector2(-12.0, 0.0))

	_npc.global_position = Vector2(-9.0, 0.0)

	assert_false(_npc.is_in_lateral_attack_position(Vector2.ZERO))

func test_lateral_attack_soft_collision_distance_stays_inside_attack_range() -> void:
	_npc.npc_data.attack_side_offset = 8.0
	_npc.npc_data.soft_collision_distance = 20.0
	_npc.global_position = Vector2(-30.0, 0.0)

	assert_eq(_npc.get_lateral_attack_position(Vector2.ZERO), Vector2(-13.0, 0.0))
