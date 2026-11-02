extends SceneTree
## Boot the iso demo, let it settle, take one 1920x1080 screenshot, quit.

func _initialize() -> void:
	var scene := load("res://scenes/iso_demo.tscn") as PackedScene
	var node := scene.instantiate()
	root.add_child(node)
	await process_frame
	await process_frame
	await create_timer(0.6).timeout
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://evidence/iso_probe.png")
	print("SHOT saved %dx%d" % [img.get_width(), img.get_height()])
	quit(0)
