extends SceneTree

## Copy owned source layers locally. Raw licensed art stays under the ignored pack directory.
func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Pass a directory containing A Myriad Of NPCs and True Heroes ZIPs after --.")
		quit(1)
		return
	var destination: String = "res://assets/art/world_packs/residents"
	DirAccess.make_dir_recursive_absolute(destination)
	for pack: String in ["AMyriadOfNPCs", "TrueHeroes"]:
		var path: String = ""
		for filename: String in DirAccess.get_files_at(args[0]):
			if filename.contains(pack) and filename.ends_with(".zip"):
				path = args[0].path_join(filename)
				break
		var archive := ZIPReader.new()
		if path.is_empty() or archive.open(path) != OK:
			push_error("Missing owned ZIP for " + pack)
			quit(1)
			return
		var count: int = 0
		for entry: String in archive.get_files():
			var selected: bool = entry.contains("/Generic_NPCs/") or entry.contains("/Rogue/General_Animations/")
			if entry.ends_with("CommercialLicense.txt"):
				var license_file := FileAccess.open(destination.path_join(pack + "-License.txt"), FileAccess.WRITE)
				license_file.store_buffer(archive.read_file(entry))
			if not selected or not entry.ends_with(".png") or entry.contains("Shadow"):
				continue
			var file := FileAccess.open(destination.path_join(entry.get_file()), FileAccess.WRITE)
			if file == null:
				quit(1)
				return
			file.store_buffer(archive.read_file(entry))
			count += 1
		archive.close()
		print("Imported %d resident sheets from %s." % [count, pack])
	quit()
