extends SceneTree
## Stage a combat frame: walk the player next to the nearest enemy, fire until a
## hit lands, and capture the frame while the hit-stop and damage number are up.
func _initialize() -> void:
	var scene := load("res://scenes/iso_playable.tscn") as PackedScene
	var node := scene.instantiate()
	root.add_child(node)
	await create_timer(0.3).timeout

	# Frame a fight: take the enemy nearest the player's spawn, then move the
	# player adjacent to it. Choosing by distance avoids teleporting into a wall.
	var target = null
	var best := 1e9
	for e in node.enemies:
		if e["ai"].is_dead():
			continue
		var c: Vector2i = node._cell_of_actor(e["node"])
		var d := Vector2(c - node.player_cell).length()
		if d < best:
			best = d
			target = e
	print("player=", node.player_cell, " nearest=", best, " target=", target != null)
	if target != null:
		var cell: Vector2i = node._cell_of_actor(target["node"])
		print("target cell=", cell, " spot walkable=", node.walkable.get(cell + Vector2i(-2, -1), false))
		var spot := cell
		for off in [Vector2i(-2, -1), Vector2i(-1, -2), Vector2i(-2, 0),
				Vector2i(0, -2), Vector2i(-1, 0), Vector2i(0, -1)]:
			var cand: Vector2i = cell + off
			if bool(node.walkable.get(cand, false)) and not node.blocks.has(cand):
				spot = cand
				break
		node.player_cell = spot
		node.move_target = spot
		node.player.position = node.world.cell_center(spot)
		node.facing = "e"
		var cam = root.get_viewport().get_camera_2d()
		if cam:
			cam.position_smoothing_enabled = false
			cam.global_position = node.player.position
		await process_frame
		# land real hits so the damage number, hit-stop and burst all fire
		target["ai"].hp = 60.0
		for i in 3:
			node._fire_cd = 0.0
			node.bullets.append({"pos": target["ai"].pos, "dir": Vector2(1, 0),
				"ttl": 0.5, "damage": 20.0})
			await process_frame
		await create_timer(0.04).timeout
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://evidence/iso_combat.png")
	print("COMBATSHOT")
	quit(0)
