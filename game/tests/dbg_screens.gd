extends SceneTree
func _initialize() -> void:
	var holder := Node.new(); root.add_child(holder)
	var screens = load("res://src/ui/screens.gd").new(); holder.add_child(screens)
	var ok = screens.open("inventory", {"items":[{"name":"Stim","count":2}]})
	print("open=", ok, " shell=", screens.shell, " current=", screens.current)
	var sh = screens.shell
	if sh:
		print("shell valid=", is_instance_valid(sh), " layer=", sh.layer)
		print("list_box=", sh.list_box, " rows=", sh.list_box.get_child_count() if sh.list_box else -1)
	quit(0)
