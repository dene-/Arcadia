class_name TownResidentArt
extends RefCounted

## Build pixel-aligned, cached costumes from the pack's compatible animation layers.
const ROOT: String = "res://assets/art/world_packs/residents/"
const SKINS: Array[String] = ["whiteskin", "brownskin", "blackskin", "paleskin"]
const SHIRTS: Array[String] = ["blue", "green", "red", "purple", "orange", "turquoise", "yellow", "grey"]
const HAIR: Array[String] = ["Bubble", "Long", "Mane", "PonyTail", "Toupee", "Bold"]
const HAIR_COLORS: Array[String] = ["brown", "black", "blonde", "red"]
const FRAME_SIZE: int = 32
## Sheets hold four rows: down-right, down-left, up-right, up-left for the layered
## civilians. The True Heroes sheets swap the first two, so their left view is row 0.
const CIVILIAN_DOWN_ROW: int = 1
const GUARD_DOWN_ROW: int = 0
const UP_ROW_OFFSET: int = 2
## Pack timing: idle runs at 200 ms per frame, actions at 100 ms. A walk cycle should cover about
## two grid cells, so walking takes 150 ms per frame at resident speeds (9 frames at 60 Hz).
const IDLE_FPS: float = 5.0
const WALK_FPS: float = 1.0 / 0.15
const ACTION_FPS: float = 10.0
## The civilian pack has no attack sheet; a quick lean through the walk frames stands in.
const CIVILIAN_ATTACK_COLUMNS: Array[int] = [1, 2, 3]
## name -> [sheet action, source frame columns (empty = all), frames per second, loops, has back view]
const ANIMATIONS: Dictionary[String, Array] = {
	"idle": ["Idle", [], IDLE_FPS, true, true],
	"walk": ["Walk", [], WALK_FPS, true, true],
	"hurt": ["Dmg", [], ACTION_FPS, false, true],
	"die": ["Die", [], ACTION_FPS, false, false],
}
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
	var guard: bool = person.job == "guard"
	var layers: Array[String] = ["Human_" + SKINS[look % SKINS.size()],
		"Trousers_brownleather", "Shirt_" + SHIRTS[(look / 4) % SHIRTS.size()],
		"HumanHair_" + HAIR[(look / 32) % HAIR.size()] + "_" + ("white" if person.age > 60 else HAIR_COLORS[(look / 192) % 4])]
	var down_row: int = GUARD_DOWN_ROW if guard else CIVILIAN_DOWN_ROW
	var sheets: Dictionary[String, Texture2D] = {}
	for animation: String in ANIMATIONS:
		var spec: Array = ANIMATIONS[animation]
		var action: String = spec[0]
		if not sheets.has(action):
			sheets[action] = _sheet(action, guard, layers)
		if sheets[action] == null:
			return preload("res://game/resources/animation/humans/cooker_sprite_frames.tres")
		_add_animation(frames, animation, sheets[action], down_row if spec[4] else 0,
			spec[1], spec[2], spec[3])
		if spec[4]:
			_add_animation(frames, animation + ActorSpriteFrames.UP_SUFFIX, sheets[action],
				down_row + UP_ROW_OFFSET, spec[1], spec[2], spec[3])
	var attack: Texture2D = sheets["Walk"]
	var attack_columns: Array = CIVILIAN_ATTACK_COLUMNS
	if guard:
		attack = load(ROOT + "Minifantasy_TrueHeroesRogueAttack.png")
		attack_columns = []
	_add_animation(frames, "attack", attack, down_row, attack_columns, ACTION_FPS, false)
	_add_animation(frames, "attack" + ActorSpriteFrames.UP_SUFFIX, attack,
		down_row + UP_ROW_OFFSET, attack_columns, ACTION_FPS, false)
	_cache[key] = frames
	return frames

static func _sheet(action: String, guard: bool, layers: Array[String]) -> Texture2D:
	if guard:
		return load(ROOT + "Minifantasy_TrueHeroesRogue%s.png" % action)
	var composite: Image
	for layer: String in layers:
		var sheet: Texture2D = load(ROOT + "Minifantasy_NPCs%s_%s.png" % [action, layer])
		if sheet == null:
			return null
		var pixels: Image = sheet.get_image()
		pixels.convert(Image.FORMAT_RGBA8)
		if composite == null:
			composite = pixels.duplicate()
		else:
			composite.blend_rect(pixels, Rect2i(Vector2i.ZERO, pixels.get_size()), Vector2i.ZERO)
	return ImageTexture.create_from_image(composite)

static func _add_animation(frames: SpriteFrames, animation: String, texture: Texture2D,
		row: int, columns: Array, fps: float, loops: bool) -> void:
	var source_columns: Array = columns
	if source_columns.is_empty():
		source_columns = range(texture.get_width() / FRAME_SIZE)
	frames.add_animation(animation)
	frames.set_animation_loop(animation, loops)
	frames.set_animation_speed(animation, fps)
	for column: int in source_columns:
		var frame := AtlasTexture.new()
		frame.atlas = texture
		frame.region = Rect2(column * FRAME_SIZE, row * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE)
		frames.add_frame(animation, frame)
