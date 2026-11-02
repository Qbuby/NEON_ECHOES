extends SceneTree
func _initialize() -> void:
	var holder := Node.new(); root.add_child(holder)
	var screens = load("res://src/ui/screens.gd").new(); holder.add_child(screens)
	screens.open("inventory", {"items":[{"name":"Stim","count":2}]})
	var sh = screens.shell
	print("sh.list_box=", sh.list_box)
	print("sh.root children=", sh.root.get_child_count() if sh.root else -1)
	print("sh.get_child_count=", sh.get_child_count())
	quit(0)
