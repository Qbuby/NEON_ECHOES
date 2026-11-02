extends SceneTree
func _initialize() -> void:
	var holder := Node.new(); root.add_child(holder)
	var screens = load("res://src/ui/screens.gd").new(); holder.add_child(screens)
	screens.open("inventory", {})
	screens.open("weapons", {})
	screens.close()
	print("after 1 close: current=", screens.current, " shell=", screens.shell)
	screens.close()
	print("after 2 close: current=", screens.current, " shell=", screens.shell)
	quit(0)
