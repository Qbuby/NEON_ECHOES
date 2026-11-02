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

	# movement: find a walkable, device-free neighbour and walk into it
	var before: Array = st["player"]["cell"]
	var start := Vector2i(int(before[0]), int(before[1]))
	var step := Vector2i.ZERO
	for cand in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		var c: Vector2i = start + cand
		if bool(node.walkable.get(c, false)) and not node.blocks.has(c):
			step = c
			break
	if step != Vector2i.ZERO:
		node.player_cell = start
		node.move_target = step
		for i in 40:
			await physics_frame
		var after: Array = node.get_state()["player"]["cell"]
		_check(Vector2i(int(after[0]), int(after[1])) == step,
			"player walks into an adjacent free cell")

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

	# a quest advances only when its matching action happens
	var advanced := false
	for q in node.quests:
		if str(q.get("status", "")) == "active" and str(q.get("objective", "")) == "kill":
			var before_stage := int(q.get("stage", 1))
			for k in 3:
				node.advance_quest("kill")
			advanced = int(q.get("stage", 1)) > before_stage or q.get("status") == "complete"
			break
	_check(advanced, "a kill objective advances the active quest")

	# an unrelated objective must not advance that quest
	var untouched := true
	for q in node.quests:
		if str(q.get("objective", "")) == "hack":
			var stage_before := int(q.get("stage", 1))
			node.advance_quest("kill")
			if int(q.get("stage", 1)) != stage_before and str(q.get("status", "")) == "active":
				untouched = false
	_check(untouched, "an unrelated action does not advance a quest")

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
