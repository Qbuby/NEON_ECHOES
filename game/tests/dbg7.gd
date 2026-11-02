extends SceneTree
func _initialize() -> void:
	var scene := load("res://scenes/iso_demo.tscn") as PackedScene
	var node := scene.instantiate()
	root.add_child(node)
	await process_frame
	var w = node.get_node_or_null("IsoWorld")
	# find a cell that has both a roof and a facade and report their z
	var by_cell := {}
	for c in w.get_children():
		if not (c is Sprite2D):
			continue
		var h = int(c.region_rect.size.y)
		var kind = "floor" if h == 32 and c.region_rect.size.x == 64 and abs(c.position.y - round(c.position.y/32)*32) < 1 else ("roof" if h == 32 else "face")
		print("") if false else null
	# simpler: print the 6 sprites with the smallest y (top of the image)
	var sprites := []
	for c in w.get_children():
		if c is Sprite2D:
			sprites.append(c)
	sprites.sort_custom(func(a,b): return a.position.y < b.position.y)
	for i in mini(8, sprites.size()):
		var s = sprites[i]
		print("y=%7.1f x=%7.1f h=%3d z=%5d" % [s.position.y, s.position.x, s.region_rect.size.y, s.z_index])
	quit(0)
