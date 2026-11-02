extends SceneTree
func _initialize() -> void:
	var scene := load("res://scenes/iso_demo.tscn") as PackedScene
	var node := scene.instantiate()
	root.add_child(node)
	await process_frame
	var w = node.get_node_or_null("IsoWorld")
	var pr = w.get_node_or_null("Props")
	print("props=", pr.get_child_count())
	for i in mini(4, pr.get_child_count()):
		var s = pr.get_child(i)
		print("  child ", i, " tex=", s.texture.resource_path if s.texture else "null",
			" region=", s.region_rect, " pos=", s.position, " zi=", s.z_index)
	var cam = node.get_node_or_null("Rin/Camera")
	print("camera zoom=", cam.zoom if cam else "no cam")
	quit(0)
