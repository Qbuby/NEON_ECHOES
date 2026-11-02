extends SceneTree
func _initialize() -> void:
	var holder := Node.new(); root.add_child(holder)
	var screens = load("res://src/ui/screens.gd").new(); holder.add_child(screens)
	screens.open("inventory", {})
	screens.open("weapons", {})
	print("stack after 2 opens=", screens.stack)
	screens.close()
	print("stack after close1=", screens.stack, " current=", screens.current)
	screens.close()
	print("stack after close2=", screens.stack, " current=", screens.current, " shell=", screens.shell)
	quit(0)
