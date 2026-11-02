extends SceneTree
func _initialize() -> void:
	var scene := load("res://scenes/iso_demo.tscn") as PackedScene
	var node := scene.instantiate()
	root.add_child(node)
	await process_frame
	var w = node.get_node_or_null("IsoWorld")
	var walls = w.get_node_or_null("Walls")
	print("wall sprites=", walls.get_child_count())
	var regions := {}
	for c in walls.get_children():
		var rr = c.region_rect
		var k = str(int(rr.size.y))
		regions[k] = regions.get(k, 0) + 1
	print("region heights:", regions)
	quit(0)
