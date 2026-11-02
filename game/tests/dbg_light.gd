extends SceneTree
func _initialize() -> void:
	var node = load("res://src/world/iso_playable.gd").new()
	root.add_child(node)
	await process_frame
	var lit = node.get_node_or_null("World/Lighting")
	print("Lighting node under World =", lit)
	if lit:
		print("  lights=", lit.lights.size(), " visible=", lit.visible,
			" z=", lit.z_index, " material=", lit.material,
			" blend=", lit.material.blend_mode if lit.material else "none")
		if lit.lights.size():
			print("  first light=", lit.lights[0])
	quit(0)
