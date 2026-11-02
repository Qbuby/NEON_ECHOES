extends SceneTree
var n
func _initialize() -> void:
	n = load("res://src/world/iso_playable.gd").new()
	root.add_child(n)
	await process_frame
	print("is_processing=", n.is_processing(), " inside=", n.is_inside_tree())
	n.move_target = Vector2i(10, 9)
	print("cell_center(10,9)=", n.world.cell_center(Vector2i(10,9)))
	print("player pos=", n.player.position)
	for i in 10:
		await process_frame
	print("after: cell=", n.player_cell, " pos=", n.player.position)
	quit(0)
