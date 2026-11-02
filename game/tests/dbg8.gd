extends SceneTree
func _initialize() -> void:
	var scene := load("res://scenes/iso_demo.tscn") as PackedScene
	var node := scene.instantiate()
	root.add_child(node)
	await process_frame
	var w = node.get_node_or_null("IsoWorld")
	# where do roofs and facades land on screen relative to the world origin?
	var cam = root.get_viewport().get_camera_2d()
	var roofs := 0
	var faces := 0
	for c in w.get_children():
		if not (c is Sprite2D):
			continue
		if c.region_rect.size.y == 32:
			roofs += 1
		elif c.region_rect.size.y > 100:
			faces += 1
	print("roof-like=", roofs, " face-like=", faces, " total=", w.get_child_count())
	# count floor tiles (32 high, exactly 64 wide, y aligned to 32 grid)
	var floors := 0
	for c in w.get_children():
		if c is Sprite2D and c.region_rect.size.y == 32 and c.region_rect.size.x == 64:
			floors += 1
	print("floors(64x32)=", floors)
	quit(0)
