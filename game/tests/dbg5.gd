extends SceneTree
func _initialize() -> void:
	var scene := load("res://scenes/iso_demo.tscn") as PackedScene
	var node := scene.instantiate()
	root.add_child(node)
	await process_frame
	var w = node.get_node_or_null("IsoWorld")
	var walls = w.get_node_or_null("Walls")
	var facades = []
	for c in walls.get_children():
		if c.region_rect.size.y > 100:
			facades.append(c)
	print("facades=", facades.size())
	for i in mini(3, facades.size()):
		var f = facades[i]
		print("  rect=", f.region_rect, " pos=", f.position, " z=", f.z_index,
			" visible=", f.visible, " tex=", f.texture != null)
	# bounding box of all facades
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for f in facades:
		mn.x = minf(mn.x, f.position.x); mn.y = minf(mn.y, f.position.y)
		mx.x = maxf(mx.x, f.position.x); mx.y = maxf(mx.y, f.position.y)
	print("facade bbox pos ", mn, " .. ", mx, " world at ", w.position)
	quit(0)
