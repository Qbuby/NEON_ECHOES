extends SceneTree
func _initialize() -> void:
	var holder := Node.new(); root.add_child(holder)
	var sh = load("res://src/ui/screen_shell.gd").new()
	holder.add_child(sh)
	sh.setup("INVENTORY", "Inventory", "sub")
	print("root=", sh.root, " list_box=", sh.list_box)
	if sh.list_box:
		sh.add_row("Stim", "x2", true)
		print("rows=", sh.list_box.get_child_count())
	quit(0)
