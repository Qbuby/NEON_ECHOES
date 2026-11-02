extends SceneTree
func _initialize() -> void:
	var node = load("res://src/world/iso_playable.gd").new()
	root.add_child(node)
	await process_frame
	await process_frame
	var lit = node.get_node_or_null("World/Lighting")
	if lit:
		print("in tree=", lit.is_inside_tree(), " lights=", lit.lights.size())
		print("material blend=", lit.material.blend_mode if lit.material else "none")
		# force a redraw and sample the framebuffer
		lit.queue_redraw()
		await process_frame
	var img = root.get_viewport().get_texture().get_image()
	img.save_png("res://evidence/_lit.png")
	print("saved")
	quit(0)
