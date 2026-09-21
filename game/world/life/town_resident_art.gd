class_name TownResidentArt
extends RefCounted

## Build pixel-aligned, cached costumes from the pack's compatible animation layers.
const ROOT: String = "res://assets/art/world_packs/residents/"
const SKINS: Array[String] = ["whiteskin", "brownskin", "blackskin", "paleskin"]
const SHIRTS: Array[String] = ["blue", "green", "red", "purple", "orange", "turquoise", "yellow", "grey"]
const HAIR: Array[String] = ["Bubble", "Long", "Mane", "PonyTail", "Toupee", "Bold"]
const HAIR_COLORS: Array[String] = ["brown", "black", "blonde", "red"]
static var _cache: Dictionary[String, SpriteFrames] = {}
static var _warned_missing: bool = false

static func frames_for(person: Dictionary) -> SpriteFrames:
	if not FileAccess.file_exists(ROOT + "Minifantasy_TrueHeroesRogueIdle.png") \
		or not FileAccess.file_exists(ROOT + "Minifantasy_NPCsIdle_Human_whiteskin.png"):
		if not _warned_missing:
			push_warning("Resident art missing. Run tools/art/import_resident_packs.gd with your owned ZIPs; using temporary sprites.")
			_warned_missing = true
		return preload("res://game/resources/animation/humans/cooker_sprite_frames.tres")
	var key: String = "%s:%s:%s" % [person.appearance, person.age, person.job]
	if _cache.has(key):
		return _cache[key]
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var look: int = int(person.appearance)
	var layers: Array[String] = ["Human_" + SKINS[look % SKINS.size()],
		"Trousers_brownleather", "Shirt_" + SHIRTS[(look / 4) % SHIRTS.size()],
		"HumanHair_" + HAIR[(look / 32) % HAIR.size()] + "_" + ("white" if person.age > 60 else HAIR_COLORS[(look / 192) % 4])]
	var animations: Dictionary = {"idle": "Idle", "walk": "Walk", "run": "Walk", "hurt": "Dmg", "die": "Die", "attack": "Idle"}
	if person.job == "guard":
		animations.attack = "Attack"
	for animation: String in animations:
		var action: String = animations[animation]
		var texture: Texture2D
		if person.job == "guard":
			texture = load(ROOT + "Minifantasy_TrueHeroesRogue%s.png" % action)
		else:
			var composite: Image
			for layer: String in layers:
				var sheet: Texture2D = load(ROOT + "Minifantasy_NPCs%s_%s.png" % [action, layer])
				if sheet == null:
					return preload("res://game/resources/animation/humans/cooker_sprite_frames.tres")
				var pixels: Image = sheet.get_image()
				pixels.convert(Image.FORMAT_RGBA8)
				if composite == null:
					composite = pixels.duplicate()
				else:
					composite.blend_rect(pixels, Rect2i(Vector2i.ZERO, pixels.get_size()), Vector2i.ZERO)
			texture = ImageTexture.create_from_image(composite)
		frames.add_animation(animation)
		frames.set_animation_loop(animation, animation in ["idle", "walk", "run"])
		frames.set_animation_speed(animation, 10.0 if animation in ["hurt", "die", "attack", "run"] else 5.0)
		for column: int in range(texture.get_width() / 32):
			var frame := AtlasTexture.new()
			frame.atlas = texture
			frame.region = Rect2(column * 32, 0 if animation == "die" else 32, 32, 32)
			frames.add_frame(animation, frame)
	_cache[key] = frames
	return frames
