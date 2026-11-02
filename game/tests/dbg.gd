extends SceneTree
func _initialize() -> void:
	var scene := load("res://scenes/iso_demo.tscn") as PackedScene
	var node := scene.instantiate()
	root.add_child(node)
	await process_frame
	var w = node.get_node_or_null("IsoWorld")
	print("world=", w, " children=", w.get_child_count() if w else -1)
	if w:
		for c in w.get_children():
			print("  root ", c.name, " children=", c.get_child_count(), " zi=", c.z_index)
		var fr = w.get_node_or_null("Floor")
		if fr and fr.get_child_count() > 0:
			var s = fr.get_child(0)
			print("  first floor sprite pos=", s.position, " region=", s.region_rect, " tex=", s.texture)
		print("  world pos=", w.position, " heights=", w.heights.size())
	quit(0)
