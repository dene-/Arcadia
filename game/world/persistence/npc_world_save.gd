class_name NpcWorldSave
extends RefCounted

## One atomic save for named-NPC world facts, minds and subjective memories.
const SAVE_VERSION: int = 2
const SAVE_PATH: String = "user://npc_world_v2.json"
## Read-only migration sources; never written, renamed or deleted.
const LEGACY_WORLD_PATH: String = "user://npc_world.json"
const LEGACY_MEMORY_PATH: String = "user://npc_memory.json"
const _ROOT_KEYS: Array[String] = ["version", "migration", "world", "minds", "memory"]
const _WORLD_KEYS: Array[String] = ["dead_npcs", "region_seed", "npc_seed", "life", "population",
	"economy", "justice", "deaths"]
const _MIGRATION_KEYS: Array[String] = ["source_version", "source_digest", "revision"]
## The single owner of directed relationships, shared by memory and life.
var minds := NpcMindStore.new()
var memory := NpcMemoryStore.new()
var life := TownLifeState.new()
var population := TownPopulation.new()
var economy := TownEconomy.new()
var justice := TownJustice.new()
var deaths := TownDeaths.new()
var dead_npcs: Array[String] = []
## Zero means an older save or a new world; the region assigns a seed once.
var region_seed: int = 0
## Zero preserves the original map-derived NPC generation for existing saves.
var npc_seed: int = 0
## Provenance of the loaded world: source format, source file digest and migration revision.
var migration: Dictionary = {"source_version": NpcSaveMigration.SOURCE_NEW_WORLD, "source_digest": "",
	"revision": NpcSaveMigration.REVISION}
var path: String = SAVE_PATH
var legacy_world_path: String = LEGACY_WORLD_PATH
var legacy_memory_path: String = LEGACY_MEMORY_PATH
var _writable: bool = true

func _init() -> void:
	memory.minds = minds
	life.minds = minds
	life.time_changed.connect(memory.set_world_minute)
	memory.set_world_minute(life.minute)

func is_dead(id: StringName) -> bool:
	return not id.is_empty() and String(id) in dead_npcs

func get_npc_seed() -> int:
	return npc_seed if npc_seed != 0 else region_seed

func mark_dead(id: StringName) -> void:
	if not id.is_empty() and not is_dead(id):
		dead_npcs.append(String(id))

## Loads v2, else migrates the v1 world file, else the memory-only file, else starts a new world.
## Legacy sources are only read; any failure prohibits writes and leaves live state unchanged.
func load_file() -> Error:
	var source: String = path
	var source_version: int = SAVE_VERSION
	if not FileAccess.file_exists(path):
		if FileAccess.file_exists(legacy_world_path):
			source = legacy_world_path
			source_version = NpcSaveMigration.SOURCE_WORLD_V1
		elif FileAccess.file_exists(legacy_memory_path):
			source = legacy_memory_path
			source_version = NpcSaveMigration.SOURCE_MEMORY_ONLY
		else:
			_writable = true
			return OK
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null:
		_writable = false
		return FileAccess.get_open_error()
	var text: String = file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary \
		or not _is_source_root(parser.data, source_version):
		_writable = false
		return ERR_FILE_CORRUPT
	var upgraded: Dictionary = NpcSaveMigration.upgrade(parser.data)
	if not upgraded.ok:
		_writable = false
		return ERR_FILE_CORRUPT
	var candidate: Dictionary = upgraded.data
	if source_version != SAVE_VERSION:
		candidate.migration.source_digest = NpcSaveMigration.digest(text)
	if not from_data(candidate):
		_writable = false
		return ERR_FILE_CORRUPT
	_writable = true
	return OK

func to_data() -> Dictionary:
	return {"version": SAVE_VERSION, "migration": migration.duplicate(),
		"world": {"dead_npcs": dead_npcs.duplicate(), "region_seed": region_seed, "npc_seed": npc_seed,
			"life": life.to_data(), "population": population.to_data(), "economy": economy.to_data(),
			"justice": justice.to_data(), "deaths": deaths.to_data()},
		"minds": minds.to_data(), "memory": memory.to_save_data()}

## Accepts only a current-revision v2 root. Every part is validated before any live state changes.
func from_data(data: Variant) -> bool:
	if not data is Dictionary or not _has_exactly(data, _ROOT_KEYS) \
		or not NpcMemory.is_integer(data.version) or int(data.version) != SAVE_VERSION:
		return false
	var saved_migration: Dictionary = _parse_migration(data.migration)
	if saved_migration.is_empty() or not data.world is Dictionary or not _has_exactly(data.world, _WORLD_KEYS):
		return false
	var world: Dictionary = data.world
	var ids: Variant = world.dead_npcs
	if not ids is Array:
		return false
	var validated: Array[String] = []
	for id: Variant in ids:
		if not id is String or id.is_empty() or id in validated:
			return false
		validated.append(id)
	var saved_seed: Variant = world.region_seed
	if not NpcMemory.is_integer(saved_seed) or saved_seed < 0 or saved_seed > 2147483646:
		return false
	var saved_npc_seed: Variant = world.npc_seed
	if not NpcMemory.is_integer(saved_npc_seed) or saved_npc_seed < 0 or saved_npc_seed > 2147483646:
		return false
	var validated_life := TownLifeState.new()
	var validated_population := TownPopulation.new()
	var validated_economy := TownEconomy.new()
	var validated_justice := TownJustice.new()
	var validated_deaths := TownDeaths.new()
	if not NpcMindStore.is_valid_data(data.minds) or not validated_life.from_data(world.life) \
		or not validated_population.from_data(world.population) \
		or not validated_economy.from_data(world.economy) \
		or not validated_justice.from_data(world.justice) \
		or not validated_deaths.from_data(world.deaths):
		return false
	for id: String in validated_deaths.ids():
		if not id in validated:
			return false
	if not NpcMemoryStore.new().from_save_data(data.memory, validated_life.minute):
		return false
	minds.from_data(data.minds)
	life.from_data(world.life)
	memory.from_save_data(data.memory, life.minute)
	population.from_data(validated_population.to_data())
	economy.from_data(validated_economy.to_data())
	justice.from_data(validated_justice.to_data())
	deaths.from_data(validated_deaths.to_data())
	dead_npcs = validated
	region_seed = int(saved_seed)
	npc_seed = int(saved_npc_seed)
	migration = saved_migration
	return true

func save_file() -> Error:
	if not _writable:
		return ERR_FILE_CORRUPT
	return _write(to_data())

## Call only for an explicit new-world/reset action, with the running game stopped.
func reset(keep_region: bool = false, reroll_npcs: bool = false) -> Error:
	if FileAccess.file_exists(path):
		var backup: String = path + ".reset-%s.bak" % Time.get_unix_time_from_system()
		var backup_error: Error = DirAccess.copy_absolute(path, backup)
		if backup_error != OK:
			return backup_error
	var empty := NpcWorldSave.new()
	if keep_region:
		empty.region_seed = region_seed
	if reroll_npcs:
		empty.npc_seed = randi_range(1, 2147483646)
		while empty.npc_seed == get_npc_seed():
			empty.npc_seed = randi_range(1, 2147483646)
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

# Each resolution step only accepts the root format that belongs at its path.
static func _is_source_root(data: Dictionary, source_version: int) -> bool:
	var version: Variant = data.get("version")
	if not NpcMemory.is_integer(version):
		return false
	match source_version:
		SAVE_VERSION:
			return int(version) == SAVE_VERSION
		NpcSaveMigration.SOURCE_WORLD_V1:
			return int(version) == 1 and data.has("world")
		_:
			return int(version) == 1 and not data.has("world")

static func _has_exactly(data: Dictionary, keys: Array[String]) -> bool:
	if data.size() != keys.size():
		return false
	for key: String in keys:
		if not data.has(key):
			return false
	return true

# Returns the normalized migration record, or {} when invalid or from another revision.
static func _parse_migration(value: Variant) -> Dictionary:
	if not value is Dictionary or not _has_exactly(value, _MIGRATION_KEYS):
		return {}
	var source_version: Variant = value.source_version
	var source_digest: Variant = value.source_digest
	var revision: Variant = value.revision
	if not NpcMemory.is_integer(source_version) or not int(source_version) in [
		NpcSaveMigration.SOURCE_NEW_WORLD, NpcSaveMigration.SOURCE_WORLD_V1,
		NpcSaveMigration.SOURCE_MEMORY_ONLY]:
		return {}
	if not NpcMemory.is_integer(revision) or int(revision) != NpcSaveMigration.REVISION:
		return {}
	if not source_digest is String:
		return {}
	var digest: String = source_digest
	if int(source_version) == NpcSaveMigration.SOURCE_NEW_WORLD and not digest.is_empty():
		return {}
	if not digest.is_empty() and (digest.length() != 64 or not digest.is_valid_hex_number()):
		return {}
	return {"source_version": int(source_version), "source_digest": digest, "revision": int(revision)}
