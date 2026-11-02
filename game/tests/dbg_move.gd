extends SceneTree
func _initialize() -> void:
	var n = load("res://src/world/iso_playable.gd").new()
	root.add_child(n)
	n.setup("corp_core")
	print("spawn cell=", n.player_cell, " walkable=", n.walkable.get(n.player_cell, false))
	for c in [Vector2i(10,9), Vector2i(9,10), Vector2i(8,9)]:
		print("  ", c, " walk=", n.walkable.get(c, false), " block=", n.blocks.has(c))
	n.move_target = Vector2i(10, 9)
	print("target set to 10,9; player pos=", n.player.position)
	for i in 30:
		await process_frame
	print("after 30 frames: cell=", n.player_cell, " pos=", n.player.position)
	quit(0)
