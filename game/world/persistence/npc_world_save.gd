class_name NpcWorldSave
extends RefCounted

## One atomic save for named-NPC world facts and subjective memories.
const SAVE_PATH: String = "user://npc_world.json"
var memory := NpcMemoryStore.new()
var life := TownLifeState.new()
var dead_npcs: Array[String] = []
## Zero means an older save or a new world; the region assigns a seed once.
var region_seed: int = 0
var path: String = SAVE_PATH
var _writable: bool = true

func is_dead(id: StringName) -> bool:
	return not id.is_empty() and String(id) in dead_npcs

func mark_dead(id: StringName) -> void:
	if not id.is_empty() and not is_dead(id):
		dead_npcs.append(String(id))

func load_file(legacy_path: String = NpcMemoryStore.SAVE_PATH) -> Error:
	if not FileAccess.file_exists(path):
		var error: Error = memory.load_file(legacy_path)
		_writable = error == OK
		return error
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_writable = false
		return FileAccess.get_open_error()
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not from_data(parser.data):
		_writable = false
		return ERR_FILE_CORRUPT
	_writable = true
	return OK

func to_data() -> Dictionary:
	return {"version": 1, "world": {"dead_npcs": dead_npcs.duplicate(), "region_seed": region_seed,
		"life": life.to_data()},
		"memory": memory.to_save_data()}

func from_data(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1 or not data.get("world") is Dictionary:
		return false
	var ids: Variant = data.world.get("dead_npcs")
	if not ids is Array:
		return false
	var validated: Array[String] = []
	for id: Variant in ids:
		if not id is String or id.is_empty() or id in validated:
			return false
		validated.append(id)
	var saved_seed: Variant = data.world.get("region_seed", 0)
	if not (saved_seed is int or saved_seed is float):
		return false
	if not is_finite(float(saved_seed)) or saved_seed < 0 or saved_seed > 2147483646:
		return false
	if float(saved_seed) != floorf(float(saved_seed)):
		return false
	# Memory loading is atomic too; neither half mutates if validation fails.
	var validated_life := TownLifeState.new()
	if not validated_life.from_data(data.world.get("life", validated_life.to_data())):
		return false
	if not memory.from_save_data(data.get("memory")):
		return false
	dead_npcs = validated
	region_seed = int(saved_seed)
	life.from_data(validated_life.to_data())
	return true

func save_file() -> Error:
	if not _writable:
		return ERR_FILE_CORRUPT
	return _write(to_data())

## Call only for an explicit new-world/reset action, with the running game stopped.
func reset(keep_region: bool = false) -> Error:
	if FileAccess.file_exists(path):
		var backup: String = path + ".reset-%s.bak" % Time.get_unix_time_from_system()
		var backup_error: Error = DirAccess.copy_absolute(path, backup)
		if backup_error != OK:
			return backup_error
	var empty := NpcWorldSave.new()
	if keep_region:
		empty.region_seed = region_seed
	var error: Error = _write(empty.to_data())
	if error == OK:
		from_data(empty.to_data())
		_writable = true
	return error

func _write(data: Dictionary) -> Error:
	var temporary: String = path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		return error
	return DirAccess.rename_absolute(temporary, path)
