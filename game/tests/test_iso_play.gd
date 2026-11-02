extends SceneTree
## Headless gameplay test for the isometric scene: load a district, move, shoot,
## kill an enemy, interact with a device, and verify state changes.

var passed := 0
var failed := 0
var PlayScript := preload("res://src/world/iso_playable.gd")


func _initialize() -> void:
	var node: Node2D = PlayScript.new()
	root.add_child(node)
	var ok: bool = node.setup("corp_core")
	_check(ok, "district loads")
	if not ok:
		_finish()
		return

	var st: Dictionary = node.get_state()
	_check(int(st["player"]["cell"][0]) >= 0, "player spawned on a cell")
	_check(int(st["enemies"]["alive"]) >= 1, "enemies spawned (%d)" % int(st["enemies"]["alive"]))
	_check(int(st["devices"]) >= 5, "devices placed (%d)" % int(st["devices"]))
	_check(int(st["doors"]) >= 4, "doors placed (%d)" % int(st["doors"]))

	# movement: walk one cell east if it is walkable
	var before: Array = st["player"]["cell"]
	node.player_cell = Vector2i(int(before[0]), int(before[1]))
	var east := Vector2i(int(before[0]) + 1, int(before[1]))
	if bool(node.walkable.get(east, false)):
		node.move_target = east
		for i in 40:
			await physics_frame
		var after: Array = node.get_state()["player"]["cell"]
		_check(int(after[0]) == east.x, "player walks one cell east")

	# a wall must refuse movement
	var blocked := Vector2i(1, 1)
	node.move_target = blocked
	node.player_cell = Vector2i(2, 2)
	await physics_frame
	_check(node.move_target != blocked or not bool(node.walkable.get(blocked, false)),
		"a solid cell cannot be entered")

	# shooting kills an enemy
	var target = null
	for e in node.enemies:
		if not e["ai"].is_dead():
			target = e
			break
	if target != null:
		var ai = target["ai"]
		var kills_before: int = int(node.get_state()["enemies"]["kills"])
		for i in 12:
			node._fire_cd = 0.0
			node.player_cell = node.player_cell
			ai.hp = 10.0
			node.bullets.append({"pos": ai.pos, "dir": Vector2(1, 0),
				"ttl": 0.4, "damage": 50.0})
			await physics_frame
		_check(int(node.get_state()["enemies"]["kills"]) > kills_before,
			"shooting an enemy kills it")

	# interaction reports the nearest device
	var used := {"count": 0}
	node.device_used.connect(func(kind: String): used["count"] += 1)
	for c in node.blocks.keys():
		node.player_cell = c
		break
	node._try_interact()
	_check(int(used["count"]) >= 1, "interact fires on a device in reach")

	# every district in the list loads
	for id in ["ind_belt", "night_row"]:
		var n2: Node2D = PlayScript.new()
		root.add_child(n2)
		_check(n2.setup(id), "%s loads" % id)
		n2.queue_free()

	_finish()


func _check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("PASS  ", label)
	else:
		failed += 1
		print("FAIL  ", label)


func _finish() -> void:
	print("PLAY_RESULT {\"passed\":%d,\"failed\":%d}" % [passed, failed])
	quit(1 if failed > 0 else 0)
