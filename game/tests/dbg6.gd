extends SceneTree
func _initialize() -> void:
	var scene := load("res://scenes/iso_demo.tscn") as PackedScene
	var node := scene.instantiate()
	root.add_child(node)
	await process_frame
	var w = node.get_node_or_null("IsoWorld")
	var walls = w.get_node_or_null("Walls")
	print("walls node=", walls, " child count=", walls.get_child_count() if walls else -1)
	var fac = []
	for c in w.get_children():
		if c is Sprite2D and c.region_rect.size.y > 100:
			fac.append(c)
	print("facade sprites under world=", fac.size())
	if fac.size():
		var f = fac[0]
		print("  pos=", f.position, " z=", f.z_index, " vis=", f.visible, " modulate=", f.modulate)
	quit(0)
