extends SceneTree
func _initialize() -> void:
	var scene := load("res://scenes/iso_demo.tscn") as PackedScene
	var node := scene.instantiate()
	root.add_child(node)
	await process_frame
	await process_frame
	var cam = root.get_viewport().get_camera_2d()
	if cam:
		print("viewport cam zoom=", cam.zoom, " pos=", cam.global_position)
	else:
		print("viewport cam=NONE")
	quit(0)
