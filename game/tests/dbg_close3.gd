extends SceneTree
func _initialize() -> void:
	var holder := Node.new(); root.add_child(holder)
	var screens = load("res://src/ui/screens.gd").new(); holder.add_child(screens)
	var game := {}
	screens.open("inventory", game)
	screens.open("weapons", game)
	screens.close()
	print("c1 current=", screens.current, " stack=", screens.stack)
	screens.close()
	print("c2 current='", screens.current, "' stack=", screens.stack, " shell=", screens.shell)
	quit(0)
