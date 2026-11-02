extends SceneTree
## Boot the playable district, walk toward the enemies, shoot, and capture a
## combat frame at 1920x1080.
func _initialize() -> void:
	var scene := load("res://scenes/iso_playable.tscn") as PackedScene
	var node := scene.instantiate()
	root.add_child(node)
	await create_timer(0.4).timeout
	# walk toward the enemies for a moment so the frame is not the spawn point
	for i in 60:
		node.move_target = node.player_cell + Vector2i(1, 0) if i % 2 == 0 else node.move_target
		await process_frame
	for i in 6:
		node._fire_cd = 0.0
		node._try_attack()
		await process_frame
	await create_timer(0.2).timeout
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://evidence/iso_play.png")
	print("PLAYSHOT %dx%d" % [img.get_width(), img.get_height()])
	quit(0)
