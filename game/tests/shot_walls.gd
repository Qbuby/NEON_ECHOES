extends SceneTree
## Render with floors hidden, so the building mass is unambiguous.
func _initialize() -> void:
	var scene := load("res://scenes/iso_demo.tscn") as PackedScene
	var node := scene.instantiate()
	root.add_child(node)
	await process_frame
	var w = node.get_node_or_null("IsoWorld")
	for c in w.get_children():
		if c is Sprite2D and c.region_rect.size.y == 32 and c.region_rect.size.x == 64:
			# floors and roofs share 64x32; roofs are lifted, floors are not
			if absf(c.position.y - round(c.position.y / 16) * 16) < 0.01:
				c.visible = false
	var cam = root.get_viewport().get_camera_2d()
	if cam:
		cam.zoom = Vector2(1.0, 1.0)
	await create_timer(0.4).timeout
	root.get_viewport().get_texture().get_image().save_png("res://evidence/iso_walls.png")
	print("WALLS saved")
	quit(0)
