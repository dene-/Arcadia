@tool

class_name RegionArt
extends RefCounted

## Atlas regions use the original, unmodified 8px Minifantasy sheets.
const ROOT: String = "res://assets/art/world_packs/"
const PLAINS: String = "Minifantasy_ForgottenPlainsProps.png"
const SWAMP: String = "Minifantasy_MurkySwampProps.png"
const TOWN: String = "Minifantasy_TownsProps.png"
const TOWN_II: String = "Minifantasy_TownsIIProps.png"
const FARM: String = "Minifantasy_FarmProps.png"
var _textures: Dictionary[String, Texture2D] = {}
var _offsets: Dictionary[String, Vector2] = {}

func available() -> bool:
	for sheet: String in [PLAINS, SWAMP, TOWN, TOWN_II, FARM,
		"Minifantasy_TownsIIStuccoBuildingIndoorTileset.png",
		"Minifantasy_ForgottenPlainsPropsShadows.png", "Minifantasy_MurkySwampPropsShadows.png",
		"Minifantasy_MurkySwampGrassToGrass.png", "Minifantasy_TownsIIWindmillFrames.png",
		"Minifantasy_FarmTileset.png", "Minifantasy_CraftingAndProfessionsBlacksmithProps.png",
		"Minifantasy_CraftingAndProfessionsWoodworkProps.png", "Minifantasy_CraftingAndProfessionsTailorProps.png"]:
		if not ResourceLoader.exists(ROOT + sheet):
			return false
	return true

func sprite(parent: Node2D, sheet: String, region: Rect2i, foot: Vector2,
		footprint: Rect2 = Rect2()) -> Sprite2D:
	if not _textures.has(sheet):
		_textures[sheet] = load(ROOT + sheet)
	var prop := Sprite2D.new()
	prop.texture = _textures[sheet]
	prop.region_enabled = true
	prop.region_rect = region
	prop.position = foot
	var key: String = sheet + str(region)
	if not _offsets.has(key):
		var used: Rect2i = prop.texture.get_image().get_region(region).get_used_rect()
		_offsets[key] = Vector2(0, region.size.y * 0.5 - used.end.y)
	prop.offset = _offsets[key]
	if footprint.has_area():
		# Art and collision share an authored anchor at the bottom of the footprint.
		var anchor := Vector2(footprint.get_center().x, footprint.end.y)
		prop.offset = Vector2(region.size) * 0.5 - anchor
	parent.add_child(prop)
	if footprint.has_area():
		barrier(prop, Vector2(0, -footprint.size.y * 0.5), footprint.size)
	return prop

func decoration(parent: Node2D, sheet: String, region: Rect2i, foot: Vector2) -> Sprite2D:
	var prop: Sprite2D = sprite(parent, sheet, region, foot)
	prop.z_index = -3
	return prop

## Editor-only art preview. No AI, physics, persistence, or provider calls.
static func actor_preview(parent: Node2D, data: NpcData, foot: Vector2, label: String) -> void:
	var frames: SpriteFrames = data.sprite_frames
	if frames is ActorSpriteFrames:
		frames.ensure_built()
	var preview := AnimatedSprite2D.new()
	preview.name = label + "Preview"
	preview.position = foot
	preview.sprite_frames = frames
	preview.animation = &"idle"
	parent.add_child(preview)

static func barrier(parent: Node2D, center: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body
