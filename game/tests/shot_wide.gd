extends SceneTree
func _initialize() -> void:
	var scene := load("res://scenes/iso_demo.tscn") as PackedScene
	var node := scene.instantiate()
	root.add_child(node)
	await process_frame
	var cam = root.get_viewport().get_camera_2d()
	if cam:
		cam.zoom = Vector2(0.34, 0.34)
		cam.position = Vector2(1088, 544)
	await create_timer(0.5).timeout
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://evidence/iso_wide.png")
	print("WIDE saved")
	quit(0)
