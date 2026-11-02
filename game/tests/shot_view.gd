extends SceneTree
func _initialize() -> void:
	var scene := load("res://scenes/iso_playable.tscn") as PackedScene
	var node := scene.instantiate()
	root.add_child(node)
	await create_timer(0.35).timeout
	var cam = root.get_viewport().get_camera_2d()
	print("cam global=", cam.global_position, " zoom=", cam.zoom)
	print("world visible=", node.world.visible, " pos=", node.world.position)
	print("world children=", node.world.get_child_count())
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://evidence/iso_combat.png")
	print("SHOT")
	quit(0)
