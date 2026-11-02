extends SceneTree
func _initialize() -> void:
	var holder := Node.new(); root.add_child(holder)
	var sh = load("res://src/ui/screen_shell.gd").new()
	holder.add_child(sh)
	await process_frame
	sh.setup("INVENTORY", "Inventory", "subtitle here")
	print("list=", sh.list_box)
	sh.add_row("Stim", "x2", true)
	print("rows=", sh.list_box.get_child_count())
	quit(0)
