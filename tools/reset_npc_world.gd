extends SceneTree

## Stop the game, then run this script with -- --confirm to start a fresh NPC world.
func _initialize() -> void:
	if not "--confirm" in OS.get_cmdline_user_args():
		print("No changes made. Stop the game and pass -- --confirm to reset NPC deaths and memories.")
		quit(1)
		return
	var save := NpcWorldSave.new()
	var error: Error = save.reset()
	if error != OK:
		push_error("NPC world reset failed: %s" % error)
		quit(1)
		return
	print("NPC deaths and memories reset. Existing combined save backed up beside npc_world.json.")
	quit()
