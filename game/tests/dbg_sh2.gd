extends SceneTree
func _initialize() -> void:
	var holder := Node.new(); root.add_child(holder)
	var screens = load("res://src/ui/screens.gd").new(); holder.add_child(screens)
	print("ok=", screens.open("inventory", {}))
	var sh = screens.shell
	print("sh=", sh, " list=", sh.list_box if sh else null)
	if sh and sh.list_box:
		print("rows=", sh.list_box.get_child_count())
	quit(0)
