extends SceneTree
func _initialize() -> void:
	var holder := Node.new(); root.add_child(holder)
	var screens = load("res://src/ui/screens.gd").new(); holder.add_child(screens)
	screens.open("inventory", {"items":[{"name":"Stim","count":2}]})
	print("rows after open =", screens.shell.list_box.get_child_count())
	quit(0)
