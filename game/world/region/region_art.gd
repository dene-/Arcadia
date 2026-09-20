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
		"Minifantasy_ForgottenPlainsPropsShadows.png", "Minifantasy_MurkySwampPropsShadows.png",
		"Minifantasy_MurkySwampGrassToGrass.png", "Minifantasy_TownsIIWindmillFrames.png",
		"Minifantasy_FarmTileset.png", "Minifantasy_CraftingAndProfessionsBlacksmithProps.png",
		"Minifantasy_CraftingAndProfessionsWoodworkProps.png", "Minifantasy_CraftingAndProfessionsTailorProps.png"]:
		if not ResourceLoader.exists(ROOT + sheet):
			return false
	return true

func sprite(parent: Node2D, sheet: String, region: Rect2i, foot: Vector2,
		solid_size: Vector2 = Vector2.ZERO) -> Sprite2D:
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
	parent.add_child(prop)
	if solid_size != Vector2.ZERO:
		barrier(prop, Vector2(0, -solid_size.y * 0.5), solid_size)
	return prop

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
