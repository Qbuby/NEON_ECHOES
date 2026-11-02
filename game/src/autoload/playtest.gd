extends Node
## Deterministic, scenario-driven playtest harness.
##
## It exists so an agent (or CI) can prove a build actually plays, without a
## human at the keyboard and without the Godot editor:
##
##     godot --path <project> -- --playtest=res://tests/playtest/smoke.json
##     godot --path <project> -- --playtest=res://tests/playtest/smoke.json --playtest-visual
##
## Steps drive real input actions through Input.parse_input_event (the same path
## a keyboard event takes), assert against a live state snapshot, and capture
## screenshots. Results are written to user://playtest/<name>/report.json and
## echoed to stdout as `PLAYTEST_RESULT {...}`.
##
## Games extend the snapshot with Playtest.register_state_provider(func(): ...).
##
## Step actions:
##   {"action":"wait","frames":30}
##   {"action":"press","input":"move_right"}          hold until release
##   {"action":"release","input":"move_right"}
##   {"action":"tap","input":"attack","frames":3}
##   {"action":"assert","path":"player.x","op":"gt","value":20}
##   {"action":"assert","path":"enemies.alive","op":"eq","value":0,"label":"boss dead"}
##   {"action":"screenshot","label":"after_move"}
##   {"action":"log_state","label":"checkpoint"}
##   {"action":"call","method":"spawn_boss"}          calls a registered hook
##   {"action":"quit","code":0}

signal finished(report: Dictionary)

const OUT_DIR := "user://playtest"

var active := false
var scenario: Dictionary = {}
var report: Dictionary = {}

var _steps: Array = []
var _index := 0
var _remaining := 0
var _frames := 0
var _timeout := 3600
var _results: Array = []
var _failures: Array = []
var _out_dir := ""
var _visual := false
var _state_providers: Array[Callable] = []
var _hooks: Dictionary = {}
var _started := false

# autoplay ("AI playtest") state
var _autoplay := false
var _autoplay_goal := "victory"
var _autoplay_frames := 0
var _autoplay_max := 3600
var _stuck_frames := 0
var _last_pos := Vector2.ZERO
var _detour_frames := 0
var _detour_dir := Vector2.ZERO
var _game_over_seen := false
var _victory := false
var _bot_log: Array = []
var _screenshot_every := 0
var _flee_left := 0
var _shot_index := 0
var _inside_wall_count := 0
var _level_root: Node = null
var _grid_w := 0
var _grid_h := 0
var _walkable: Dictionary = {}
var _tile_size := 16
var _grid_level: Node = null
var _path: Array = []
var _path_target := Vector2i(-9999, -9999)
var _path_index := 0
var _target_node: Node2D = null
var _target_age := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.game_over.connect(func(victory: bool):
		_game_over_seen = true
		_victory = victory
		Log.info("playtest.game_over", {"victory": victory})
	)
	var path := _cmdline_value("--playtest=")
	if path == "":
		set_physics_process(false)
		return
	_visual = _has_flag("--playtest-visual")
	_start(path)


func register_state_provider(provider: Callable) -> void:
	_state_providers.append(provider)


func register_hook(hook_name: String, fn: Callable) -> void:
	_hooks[hook_name] = fn


func is_active() -> bool:
	return active


func _cmdline_value(prefix: String) -> String:
	for arg in OS.get_cmdline_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return ""


func _has_flag(flag: String) -> bool:
	return flag in OS.get_cmdline_args() or flag in OS.get_cmdline_user_args()


func _start(path: String) -> void:
	var text := ""
	if path.begins_with("res://") or path.begins_with("user://"):
		if not FileAccess.file_exists(path):
			_fatal("scenario not found: " + path)
			return
		text = FileAccess.get_file_as_string(path)
	else:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			_fatal("scenario not readable: " + path)
			return
		text = f.get_as_text()
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		_fatal("scenario is not a JSON object: " + path)
		return
	scenario = parsed
	_steps = scenario.get("steps", [])
	_timeout = int(scenario.get("timeout_frames", 3600))
	var name := String(scenario.get("name", "playtest"))
	_out_dir = OUT_DIR + "/" + name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	active = true
	_started = true
	Log.info("playtest.start", {
		"name": name, "steps": _steps.size(), "timeout_frames": _timeout,
		"visual": _visual, "headless": DisplayServer.get_name() == "headless",
	})
	print("PLAYTEST_START ", JSON.stringify({"name": name, "steps": _steps.size()}))


func _physics_process(_delta: float) -> void:
	# Physics ticks are the game's fixed clock (60/s); counting render frames
	# instead would make waits non-deterministic, especially in headless runs.
	if not active:
		return
	_frames += 1
	if _frames > _timeout:
		_fail("timeout", {"frames": _frames})
		_finish(1)
		return
	if _index >= _steps.size():
		_finish(0)
		return
	if _autoplay:
		_autoplay_tick()
		if _autoplay:
			return
	if _remaining > 0:
		_remaining -= 1
		if _remaining == 0:
			_advance()
		return
	_run_step(_steps[_index])


func _run_step(step: Dictionary) -> void:
	var action := String(step.get("action", "wait"))
	match action:
		"wait":
			_remaining = maxi(1, int(step.get("frames", 1)))
			if _remaining == 1:
				_advance()
		"press":
			_set_action(String(step.get("input", "")), true)
			_advance()
		"release":
			_set_action(String(step.get("input", "")), false)
			_advance()
		"tap":
			var input := String(step.get("input", ""))
			_set_action(input, true)
			_remaining = maxi(1, int(step.get("frames", 3)))
			await get_tree().physics_frame
			_set_action(input, false)
		"assert":
			_do_assert(step)
			_advance()
		"screenshot":
			_do_screenshot(String(step.get("label", "shot_%d" % _index)))
			_advance()
		"log_state":
			var snap := get_state()
			_results.append({"step": _index, "action": "log_state", "label": step.get("label", ""), "state": snap})
			Log.info("playtest.state", {"label": step.get("label", ""), "state": snap})
			_advance()
		"teleport":
			# move the player to a cell centre: lets a screenshot scenario frame a
			# boss or a landmark instead of wherever the level happens to spawn
			var level := get_tree().get_first_node_in_group("level")
			var pl := _player_node()
			if level != null and pl != null:
				var cell: Array = step.get("cell", [0, 0])
				var ts := int(level.get("tile_size"))
				pl.global_position = Vector2((float(cell[0]) + 0.5) * ts, (float(cell[1]) + 0.5) * ts)
				_last_pos = pl.global_position
			_advance()
		"zoom":
			var cam := _player_camera()
			if cam != null:
				var z := float(step.get("value", 1.0))
				cam.zoom = Vector2(z, z)
			_advance()
		"call":
			var hook := String(step.get("method", ""))
			if _hooks.has(hook):
				_hooks[hook].call(step.get("args", {}))
				_results.append({"step": _index, "action": "call", "hook": hook, "ok": true})
			else:
				_fail("hook not registered: " + hook, {})
			_advance()
		"autoplay":
			_autoplay = true
			_autoplay_goal = String(step.get("goal", "victory"))
			_autoplay_max = int(step.get("max_frames", 3600))
			_screenshot_every = int(step.get("screenshot_every", 0))
			_autoplay_frames = 0
			_last_pos = _player_pos()
			Log.info("playtest.autoplay_start", {"goal": _autoplay_goal, "max_frames": _autoplay_max})
			_remaining = 1
		"quit":
			_finish(int(step.get("code", 0)))
		_:
			_fail("unknown action: " + action, {})
			_advance()


## --- autoplay: a scripted player that actually plays the game ---
##
## It reads only what a player could know from the screen: the player's own
## state and the groups the game publishes (enemies, pickups, doors). It walks,
## attacks, picks things up, walks through doors, and reports whether it won.

func _autoplay_tick() -> void:
	_autoplay_frames += 1
	if _game_over_seen:
		_release_all()
		_bot_log.append({"frame": _autoplay_frames, "event": "game_over", "victory": _victory})
		_results.append({"step": _index, "action": "autoplay", "frames": _autoplay_frames,
			"victory": _victory, "goal": _autoplay_goal, "inside_wall_frames": _inside_wall_count, "trace": _bot_log})
		if _autoplay_goal == "victory" and not _victory:
			_fail("autoplay: game ended in defeat", {"frames": _autoplay_frames})
		_autoplay = false
		_advance()
		return
	if _autoplay_frames > _autoplay_max:
		_release_all()
		_results.append({"step": _index, "action": "autoplay", "frames": _autoplay_frames,
			"victory": false, "goal": _autoplay_goal, "timeout": true, "trace": _bot_log})
		_fail("autoplay: timeout", {"frames": _autoplay_frames, "state": get_state()})
		_autoplay = false
		_advance()
		return

	# Goal "clear": the area is done when every enemy is gone.
	if _autoplay_goal == "clear" and _enemies_alive() == 0 and _autoplay_frames > 20:
		_release_all()
		_results.append({"step": _index, "action": "autoplay", "frames": _autoplay_frames,
			"victory": true, "goal": _autoplay_goal, "inside_wall_frames": _inside_wall_count, "trace": _bot_log})
		Log.info("playtest.autoplay_clear", {"frames": _autoplay_frames})
		_autoplay = false
		_advance()
		return

	var player := _player_node()
	if player == null:
		return
	var pos := player.global_position
	# stuck detection: a player that stops moving is walking into geometry
	if _autoplay_frames % 15 == 0:
		if pos.distance_to(_last_pos) < 2.0:
			_stuck_frames += 1
		else:
			_stuck_frames = 0
		_last_pos = pos

	var target: Node2D = null
	var want_attack := false
	_target_age += 1
	var keep := _target_node != null and is_instance_valid(_target_node) and _target_age < 25
	if keep:
		target = _target_node
	else:
		var enemy := _nearest_enemy(pos)
		var pickup := _best_pickup(pos)
		var door := _best_door(pos)
		var heal := _nearest_heal(pos)
		var threat := _nearest("enemies", pos, 44.0)
		if GameState.hp <= 3 and heal != null and pos.distance_to(heal.global_position) < 260.0:
			target = heal  # patch up first
		elif threat != null:
			target = threat  # something is on top of us: fight it
		elif enemy != null and pos.distance_to(enemy.global_position) < 150.0:
			target = enemy
		elif pickup != null:
			target = pickup
		else:
			target = door
		_target_node = target
		_target_age = 0
	if target != null and target.is_in_group("enemies"):
		want_attack = pos.distance_to(target.global_position) < 26.0

	if target == null:
		_clear_move()
		if _autoplay_frames % 60 == 0:
			_bot_log.append({"frame": _autoplay_frames, "event": "idle", "pos": [pos.x, pos.y]})
		return

	# Level-traversal invariant: a character must never occupy a solid cell.
	_ensure_grid()
	if _grid_w > 0 and not _walkable.get(_cell_of(pos), true):
		_inside_wall_count += 1
		if _inside_wall_count <= 3:
			_bot_log.append({"frame": _autoplay_frames, "event": "inside_wall",
				"cell": [_cell_of(pos).x, _cell_of(pos).y], "pos": [pos.x, pos.y]})

	var dir := _steer(pos, target)
	# Low health: back off to open ground instead of facetanking into a corner.
	# Only back off if there is something to back off *to*. Fleeing with no heal
	# available is just a slower death.
	var hurt := GameState.hp <= 2
	var heal_available := _nearest_heal(pos) != null
	if hurt and heal_available and _flee_left <= 0 and pos.distance_to(target.global_position) < 80.0:
		_flee_left = 100  # about 1.6 s of backing off, then fight again
	if _flee_left > 0:
		_flee_left -= 1
		if target.is_in_group("enemies"):
			dir = _steer_pos(pos, _flee_point(pos, target.global_position))
			want_attack = false
	# If the body has not moved for a while it is wedged on geometry: sidestep.
	if _stuck_frames >= 8 and _detour_frames <= 0:
		_detour_frames = 30
		var perp := Vector2(-dir.y, dir.x)
		_detour_dir = perp if randf() < 0.5 else -perp
		_stuck_frames = 0
		_bot_log.append({"frame": _autoplay_frames, "event": "detour", "pos": [pos.x, pos.y]})
	if _detour_frames > 0:
		_detour_frames -= 1
		dir = _detour_dir
	_move_towards(dir)
	if dir == Vector2.ZERO and _autoplay_frames % 60 == 0:
		_bot_log.append({"frame": _autoplay_frames, "event": "no_path", "target": String(target.name), "pos": [pos.x, pos.y]})
	if want_attack:
		_tap_action("attack")
	if _screenshot_every > 0 and _autoplay_frames % _screenshot_every == 0:
		_shot_index += 1
		_do_screenshot("auto_%03d" % _shot_index)
	if _autoplay_frames % 45 == 0:
		_bot_log.append({
			"frame": _autoplay_frames, "pos": [snapped(pos.x, 1.0), snapped(pos.y, 1.0)],
			"target": String(target.name), "target_class": target.get_class(), "hp": GameState.hp,
			"crystals": GameState.item_count("crystal"),
			"dir": [snapped(dir.x, 0.01), snapped(dir.y, 0.01)], "path": _path.size(),
			"grid": [_grid_w, _grid_h], "vel": [snapped(player.velocity.x, 0.1), snapped(player.velocity.y, 0.1)],
			"target_pos": [snapped(target.global_position.x, 1.0), snapped(target.global_position.y, 1.0)],
		})


func _level_data() -> Dictionary:
	if _level_root == null or not is_instance_valid(_level_root):
		_level_root = get_tree().get_first_node_in_group("level")
	if _level_root != null and "data" in _level_root:
		return _level_root.data
	return {}


func _ensure_grid() -> void:
	var data := _level_data()
	# Rebuild when the level changes: the cached grid belongs to one map.
	if _grid_w > 0 and _grid_level == _level_root:
		return
	_grid_w = 0
	_grid_h = 0
	_walkable.clear()
	_path = []
	_path_target = Vector2i(-9999, -9999)
	_path_index = 0
	_target_node = null
	_grid_level = _level_root
	if data.is_empty():
		return
	var rows: Array = data.get("map", [])
	if rows.is_empty():
		return
	_tile_size = int(data.get("tile_size", 16))
	var legend: Dictionary = data.get("legend", {".": "ground", "#": "wall"})
	_grid_h = rows.size()
	_grid_w = String(rows[0]).length()
	for y in _grid_h:
		var row := String(rows[y])
		for x in _grid_w:
			var ch := row[x] if x < row.length() else "#"
			_walkable[Vector2i(x, y)] = String(legend.get(ch, "wall")) == "ground"


func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / _tile_size)), int(floor(pos.y / _tile_size)))


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * _tile_size, (cell.y + 0.5) * _tile_size)


func _nearest_walkable(cell: Vector2i) -> Vector2i:
	if _walkable.get(cell, false):
		return cell
	for radius in range(1, 6):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var c := cell + Vector2i(dx, dy)
				if _walkable.get(c, false):
					return c
	return cell


## Breadth-first search over walkable cells. Maps are small (a few hundred
## cells), so plain BFS is instant and has no tuning knobs.
func _find_path(from: Vector2i, to: Vector2i) -> Array:
	_ensure_grid()
	if _grid_w == 0:
		return []
	from = _nearest_walkable(from)
	to = _nearest_walkable(to)
	if from == to:
		return [to]
	var queue: Array[Vector2i] = [from]
	var came: Dictionary = {from: from}
	var head := 0
	var found := false
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		if current == to:
			found = true
			break
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = current + step
			if came.has(next) or not _walkable.get(next, false):
				continue
			came[next] = current
			queue.append(next)
	if not found:
		return []
	var path: Array = [to]
	var node: Vector2i = to
	while node != from:
		node = came[node]
		path.push_front(node)
	return path


## Direction to walk: follow a persistent grid path, advancing waypoints as
## they are reached. Recomputing the path every frame makes the bot oscillate
## between two equally good targets, so the path only changes when the goal
## cell changes.
func _steer(pos: Vector2, target: Node2D) -> Vector2:
	return _steer_pos(pos, target.global_position)


func _steer_pos(pos: Vector2, target_pos: Vector2) -> Vector2:
	var distance := pos.distance_to(target_pos)
	if distance < 34.0:
		return (target_pos - pos).normalized()
	var target_cell := _cell_of(target_pos)
	if target_cell != _path_target or _path.is_empty():
		_path_target = target_cell
		_path = _find_path(_cell_of(pos), target_cell)
		_path_index = 0
	if _path.is_empty():
		return (target_pos - pos).normalized()
	while _path_index < _path.size() - 1 and pos.distance_to(_cell_center(_path[_path_index])) < 7.0:
		_path_index += 1
	var waypoint := _cell_center(_path[_path_index])
	if waypoint.distance_to(pos) < 1.0 and _path_index < _path.size() - 1:
		_path_index += 1
		waypoint = _cell_center(_path[_path_index])
	return (waypoint - pos).normalized()


## A retreat point: away from the threat, clamped onto a walkable cell.
func _flee_point(pos: Vector2, threat: Vector2) -> Vector2:
	_ensure_grid()
	var away := (pos - threat)
	if away.length() < 0.001:
		away = Vector2.RIGHT
	away = away.normalized()
	var best := pos
	var best_score := -1e9
	for radius: float in [3.0, 4.0, 5.0]:
		for angle_step in range(0, 360, 30):
			var angle := deg_to_rad(float(angle_step))
			var candidate: Vector2 = pos + (away.rotated(angle * 0.5) * radius * _tile_size * 0.5)
			var cell := _cell_of(candidate)
			if not _walkable.get(cell, false):
				continue
			var score: float = candidate.distance_to(threat)
			if score > best_score:
				best_score = score
				best = _cell_center(cell)
	return best


func _enemies_alive() -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(node) and _enemy_hp(node) > 0:
			n += 1
	return n


func _nearest_enemy(from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := 1e9
	for node in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node) or not node is Node2D:
			continue
		if _enemy_hp(node) <= 0:
			continue
		var d := from.distance_to((node as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = node
	return best


## Doors are goals too: take the most forward one that is open, nearest first.
func _best_door(from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_key := -1e9
	for node in get_tree().get_nodes_in_group("doors"):
		if not is_instance_valid(node) or not node is Node2D:
			continue
		var prio := 0.0
		if "door_priority" in node:
			prio = float(node.door_priority)
		if node.has_method("is_unlocked") and not node.is_unlocked():
			continue
		var d := from.distance_to((node as Node2D).global_position)
		var key := prio * 10000.0 - d
		if key > best_key:
			best_key = key
			best = node
	return best


func _nearest_heal(from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := 1e9
	for node in get_tree().get_nodes_in_group("pickups"):
		if not is_instance_valid(node) or not node is Node2D:
			continue
		if not ("heal_amount" in node) or int(node.heal_amount) <= 0:
			continue
		var d := from.distance_to((node as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = node
	return best


## Pickups, objective first: a crystal beats a coin at the same distance.
func _best_pickup(from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_score := 1e9
	for node in get_tree().get_nodes_in_group("pickups"):
		if not is_instance_valid(node) or not node is Node2D:
			continue
		var d := from.distance_to((node as Node2D).global_position)
		var priority := 0.0
		if "item_id" in node:
			match String(node.item_id):
				"crystal": priority = 0.0
				"bloom": priority = 200.0
				_: priority = 500.0
		var score := d + priority
		if score < best_score:
			best_score = score
			best = node
	return best


func _nearest(group: String, from: Vector2, max_dist: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_dist
	for node in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(node) or not node is Node2D:
			continue
		var d := from.distance_to((node as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = node
	return best


func _enemy_hp(enemy: Node) -> int:
	var h := enemy.get_node_or_null("Health")
	if h and "hp" in h:
		return int(h.hp)
	return 1


func _player_node() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node2D


func _player_pos() -> Vector2:
	var p := _player_node()
	return p.global_position if p else Vector2.ZERO


func _move_towards(dir: Vector2) -> void:
	_set_action("move_right", dir.x > 0.35)
	_set_action("move_left", dir.x < -0.35)
	_set_action("move_down", dir.y > 0.35)
	_set_action("move_up", dir.y < -0.35)


func _clear_move() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		_set_action(a, false)


func _release_all() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down", "attack", "interact"]:
		_set_action(a, false)


func _tap_action(action_name: String) -> void:
	# Attack is edge-triggered, so press one frame and release the next.
	if _autoplay_frames % 12 == 0:
		_set_action(action_name, true)
	elif _autoplay_frames % 12 == 1:
		_set_action(action_name, false)


func _advance() -> void:
	_index += 1
	_remaining = 0


func _set_action(action_name: String, pressed: bool) -> void:
	if action_name == "":
		return
	if not InputMap.has_action(action_name):
		_fail("unknown input action: " + action_name, {})
		return
	var ev := InputEventAction.new()
	ev.action = action_name
	ev.pressed = pressed
	ev.strength = 1.0
	Input.parse_input_event(ev)


func _do_assert(step: Dictionary) -> void:
	var path := String(step.get("path", ""))
	var op := String(step.get("op", "eq"))
	var expected = step.get("value", null)
	var label := String(step.get("label", path))
	var snap := get_state()
	var actual = _lookup(snap, path)
	var ok := _compare(actual, op, expected)
	var entry := {
		"step": _index, "action": "assert", "label": label, "path": path,
		"op": op, "expected": expected, "actual": actual, "ok": ok,
	}
	_results.append(entry)
	if ok:
		Log.info("playtest.assert", entry)
	else:
		_failures.append(entry)
		Log.error("playtest.assert_failed", entry)
		print("PLAYTEST_ASSERT_FAIL ", JSON.stringify(entry))


func _player_camera() -> Camera2D:
	var level := get_tree().get_first_node_in_group("level")
	if level == null:
		return null
	for child in level.get_children():
		if child is Camera2D:
			return child
		if child is Node2D:
			for sub in child.get_children():
				if sub is Camera2D:
					return sub
	return null


func _do_screenshot(label: String) -> void:
	if DisplayServer.get_name() == "headless" or not _visual:
		_results.append({"step": _index, "action": "screenshot", "label": label, "skipped": true, "reason": "headless or --playtest-visual not set"})
		return
	var img := get_viewport().get_texture().get_image()
	# Capture at the canvas resolution and upscale by a whole factor. Grabbing
	# the window instead gives whatever size the desktop granted (1875x1055 on
	# this machine), which both misses the 1920x1080 delivery size and resamples
	# the pixel art at a fractional scale.
	var canvas := Vector2i(int(ProjectSettings.get_setting("display/window/size/viewport_width", 960)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 540)))
	if img.get_width() != canvas.x or img.get_height() != canvas.y:
		img.resize(canvas.x, canvas.y, Image.INTERPOLATE_NEAREST)
	var out := Image.new()
	out.copy_from(img)
	if canvas.x * 2 <= 1920 and canvas.y * 2 <= 1080:
		out.resize(canvas.x * 2, canvas.y * 2, Image.INTERPOLATE_NEAREST)
	var rel := _out_dir + "/" + label + ".png"
	var abs_path := ProjectSettings.globalize_path(rel)
	var err := out.save_png(abs_path)
	_write_shot_meta(label, rel + ".json", abs_path)
	_results.append({"step": _index, "action": "screenshot", "label": label, "path": abs_path, "ok": err == OK, "size": [out.get_width(), out.get_height()]})
	Log.info("playtest.screenshot", {"label": label, "path": abs_path, "ok": err == OK, "size": [out.get_width(), out.get_height()]})


## Geometry a visual checker needs: where the player is on screen, which HUD
## panels cover it, and the frame size in both spaces.
func _write_shot_meta(label: String, rel_path: String, abs_png: String) -> void:
	var meta := {
		"label": label,
		"png": abs_png,
		"area": GameState.current_area,
		"hp": GameState.hp,
		"paused": get_tree().paused,
		"fx": get_tree().get_nodes_in_group("fx").size(),
		"viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
	}
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		var player := players[0] as Node2D
		var sprite := player.get_node_or_null("Sprite") as AnimatedSprite2D
		var screen_pos: Vector2 = get_viewport().get_canvas_transform() * player.global_position
		var size := Vector2(16, 24)
		if sprite and sprite.sprite_frames:
			var names := sprite.sprite_frames.get_animation_names()
			if not names.is_empty():
				var tex := sprite.sprite_frames.get_frame_texture(String(names[0]), 0)
				if tex:
					size = tex.get_size() * sprite.scale
		meta["player_screen"] = [screen_pos.x - size.x * 0.5, screen_pos.y - size.y, size.x, size.y]
		meta["player_world"] = [player.global_position.x, player.global_position.y]
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		var rects := []
		for path in ["Root/HealthPanel", "Root/ObjectivePanel", "Root/BossPanel", "Root/Toast", "Root/Hint"]:
			var node := hud.get_node_or_null(path) as Control
			if node and node.visible:
				rects.append({"name": path, "rect": [node.global_position.x, node.global_position.y, node.size.x, node.size.y],
					"alpha": node.modulate.a})
		meta["hud_rects"] = rects
	var f := FileAccess.open(rel_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(meta, "	"))
		f.close()


func _lookup(snapshot: Dictionary, path: String) -> Variant:
	if path == "":
		return null
	var cur: Variant = snapshot
	for part in path.split("."):
		if cur is Dictionary:
			if not cur.has(part):
				return null
			cur = cur[part]
		elif cur is Array:
			var idx := int(part)
			if idx < 0 or idx >= (cur as Array).size():
				return null
			cur = cur[idx]
		else:
			return null
	return cur


func _compare(actual: Variant, op: String, expected: Variant) -> bool:
	match op:
		"eq": return _num_or_eq(actual, expected)
		"ne": return not _num_or_eq(actual, expected)
		"gt": return _num(actual) > _num(expected)
		"gte": return _num(actual) >= _num(expected)
		"lt": return _num(actual) < _num(expected)
		"lte": return _num(actual) <= _num(expected)
		"truthy": return _is_truthy(actual)
		"falsy": return not _is_truthy(actual)
		"exists": return actual != null
		"contains":
			if actual is Array: return expected in actual
			if actual is String: return String(expected) in actual
			if actual is Dictionary: return actual.has(expected)
			return false
		"not_contains":
			if actual is Array: return not (expected in actual)
			if actual is String: return not (String(expected) in actual)
			if actual is Dictionary: return not actual.has(expected)
			return true
		_: return false


func _is_truthy(v: Variant) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int or v is float:
		return float(v) != 0.0
	if v is String:
		return v != ""
	if v is Array or v is Dictionary:
		return not (v as Variant).is_empty()
	return true


func _num(v: Variant) -> float:
	if v is int or v is float: return float(v)
	if v is bool: return 1.0 if v else 0.0
	return 0.0


func _num_or_eq(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	if a is bool and b is bool:
		return a == b
	if a is String and b is String:
		return a == b
	return a == b


## Live state used by asserts. Base keys: game, player, enemies, area, frame.
func get_state() -> Dictionary:
	var state := {
		"game": GameState.snapshot(),
		"area": GameState.current_area,
		"frame": _frames,
		"enemies": _enemy_state(),
		"player": _player_state(),
	}
	for provider in _state_providers:
		var extra = provider.call()
		if extra is Dictionary:
			state.merge(extra, true)
	return state


func _player_state() -> Dictionary:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return {"alive": false, "x": 0.0, "y": 0.0}
	var p := players[0] as Node2D
	var hp := -1
	var h := p.get_node_or_null("Health")
	if h and "hp" in h:
		hp = int(h.hp)
	return {
		"alive": is_instance_valid(p) and p.is_inside_tree(),
		"x": snapped(p.global_position.x, 0.01),
		"y": snapped(p.global_position.y, 0.01),
		"hp": hp,
		"name": p.name,
	}


func _enemy_state() -> Dictionary:
	var nodes := get_tree().get_nodes_in_group("enemies")
	var alive := 0
	var list: Array = []
	for n in nodes:
		if not is_instance_valid(n) or not n.is_inside_tree():
			continue
		var hp := 1
		var h := n.get_node_or_null("Health")
		if h and "hp" in h:
			hp = int(h.hp)
		if hp > 0:
			alive += 1
		var pos := (n as Node2D).global_position
		list.append({"name": String(n.name), "x": snapped(pos.x, 0.01), "y": snapped(pos.y, 0.01), "hp": hp})
	return {"alive": alive, "total": nodes.size(), "list": list}


func _fail(reason: String, data: Dictionary) -> void:
	var entry := {"step": _index, "action": "error", "reason": reason, "data": data}
	_failures.append(entry)
	Log.error("playtest.error", entry)
	print("PLAYTEST_ERROR ", JSON.stringify(entry))


func _fatal(reason: String) -> void:
	printerr("playtest: " + reason)
	print("PLAYTEST_RESULT ", JSON.stringify({"ok": false, "error": reason}))
	get_tree().quit(2)


func _finish(code: int) -> void:
	if not active:
		return
	active = false
	set_physics_process(false)
	var ok := code == 0 and _failures.is_empty()
	report = {
		"ok": ok,
		"name": scenario.get("name", "playtest"),
		"frames": _frames,
		"steps_run": _index,
		"failures": _failures,
		"results": _results,
		"final_state": get_state(),
		"log": Log.log_path(),
		"visual": _visual,
	}
	var out := _out_dir + "/report.json"
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
	report["report_path"] = ProjectSettings.globalize_path(out)
	var ux := get_node_or_null("/root/UxProbe")
	if ux:
		ux.write_report()
	Log.info("playtest.finish", {"ok": ok, "failures": _failures.size(), "frames": _frames})
	print("PLAYTEST_RESULT ", JSON.stringify({"ok": ok, "failures": _failures.size(), "frames": _frames, "report": report["report_path"]}))
	finished.emit(report)
	await get_tree().physics_frame
	get_tree().quit(0 if ok else 1)
