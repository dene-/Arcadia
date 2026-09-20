extends SceneTree

## Import the selected PNGs from owned itch.io ZIP archives. No authenticated URLs are stored.
const DESTINATION: String = "res://assets/art/world_packs"
const PACKS: Dictionary = {
	"ForgottenPlains": ["Minifantasy_ForgottenPlainsProps.png", "Minifantasy_ForgottenPlainsPropsShadows.png",
		"Minifantasy_ForgottenPlainsRiver.png"],
	"SilentSwamp": ["Minifantasy_MurkySwampProps.png", "Minifantasy_MurkySwampPropsShadows.png",
		"Minifantasy_MurkySwampGrassToGrass.png"],
	"Towns_v": ["Minifantasy_TownsProps.png", "Minifantasy_TownsPropsShadows.png"],
	"Towns2": ["Minifantasy_TownsIIProps.png", "Minifantasy_TownsIIPropsShadows.png",
		"Minifantasy_TownsIIStoneBridgeTileset.png", "Minifantasy_TownsIIWindmillFrames.png"],
	"CraftingAndProfessions": ["Minifantasy_CraftingAndProfessionsBlacksmithProps.png",
		"Minifantasy_CraftingAndProfessionsWoodworkProps.png", "Minifantasy_CraftingAndProfessionsTailorProps.png"],
	"Farm": ["Minifantasy_FarmProps.png", "Minifantasy_FarmTileset.png"],
}

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Pass the directory containing your six purchased Minifantasy ZIPs after --.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(DESTINATION)
	var imported: int = 0
	for pack: String in PACKS:
		var archive_path: String = ""
		for filename: String in DirAccess.get_files_at(args[0]):
			if filename.contains(pack) and filename.ends_with(".zip"):
				archive_path = args[0].path_join(filename)
				break
		if archive_path.is_empty():
			push_error("Missing ZIP for %s" % pack)
			quit(1)
			return
		var archive := ZIPReader.new()
		if archive.open(archive_path) != OK:
			quit(1)
			return
		for desired: String in PACKS[pack]:
			var found: bool = false
			for entry: String in archive.get_files():
				if entry.get_file() == desired and not entry.contains("_Legacy"):
					var file := FileAccess.open(DESTINATION.path_join(desired), FileAccess.WRITE)
					if file == null:
						quit(1)
						return
					file.store_buffer(archive.read_file(entry))
					file.close()
					found = true
					imported += 1
					break
			if not found:
				push_error("Missing asset in archive: %s" % desired)
				quit(1)
				return
		archive.close()
	print("Imported %s licensed sheets locally. Reopen Godot to import textures." % imported)
	quit()
