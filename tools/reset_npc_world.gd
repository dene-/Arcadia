extends SceneTree

## Stop the game, then run this script with -- --confirm to start a fresh NPC world.
func _initialize() -> void:
	if not "--confirm" in OS.get_cmdline_user_args():
		print("No changes made. Stop the game and pass -- --confirm to reset NPC deaths and memories.")
		quit(1)
		return
	var save := NpcWorldSave.new()
	var keep_region: bool = "--keep-region" in OS.get_cmdline_user_args()
	if keep_region and save.load_file() != OK:
		push_error("Cannot preserve the region seed: existing save could not be read.")
		quit(1)
		return
	var error: Error = save.reset(keep_region)
	if error != OK:
		push_error("NPC world reset failed: %s" % error)
		quit(1)
		return
	print("NPC deaths and memories reset. Existing combined save backed up beside npc_world.json.")
	if keep_region:
		print("Saved region seed preserved.")
	quit()
