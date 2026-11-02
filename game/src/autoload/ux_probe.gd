extends Node
## Automated experience audit.
##
## Two kinds of measurement, both machine-checkable:
##
## 1. Per-frame geometry (every physics tick while enabled):
##      - solid_penetration_px : how deep the player's body sits inside solid tiles
##      - body_overlap_frames  : frames where the player and an enemy sprites overlap
##      - camera_shake_energy  : integral of |camera offset| (is juice firing?)
##      - time_scale_dips      : hit-stop activations
##
## 2. Per-event feedback coverage:
##      begin_event("hit_dealt") … channels note()'d within a short window … end_event()
##      A hit with no sound, no flash and no hit-stop is recorded as a failure.
##
## Output: user://ux/ux.json, plus a PASS/FAIL line per rule:
##      UX_RESULT {"ok":true,"rules":[…],"events":{…},"frame":{…}}
##
## Enabled with --ux-audit (add --playtest-visual for screenshots).

signal event_closed(record: Dictionary)

const OUT_DIR := "user://ux"
const EVENT_WINDOW_FRAMES := 14

## Channels each event type must show. Missing any of these is a failure.
const REQUIRED_CHANNELS := {
	"hit_dealt": ["sfx", "flash", "fx", "hitstop"],
	"hit_taken": ["sfx", "shake", "flash"],
	"pickup": ["sfx", "hud"],
	"death": ["sfx", "fx"],
}

var enabled := false
var _frame := 0
var _events: Array[Dictionary] = []
var _event_counts: Dictionary = {}
var _open_event: Dictionary = {}

var _penetration_frames := 0
var _max_penetration := 0.0
var _overlap_frames := 0
var _max_overlap := 0.0
var _shake_energy := 0.0
var _shake_frames := 0
var _hitstop_count := 0
var _low_hp_frames := 0
var _samples := 0

var _grid_built := false
var _grid_level: Node = null
var _level_root: Node = null
var _walkable: Dictionary = {}
var _tile := 16


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = "--ux-audit" in OS.get_cmdline_args() or "--ux-audit" in OS.get_cmdline_user_args()
	set_physics_process(enabled)
	if enabled:
		Log.info("ux.start", {})


## --- event API used by gameplay code -------------------------------------

func begin_event(kind: String, data: Dictionary = {}) -> void:
	if not enabled:
		return
	_open_event = {"kind": kind, "frame": _frame, "channels": {}, "data": data}
	_event_counts[kind] = int(_event_counts.get(kind, 0)) + 1


func note(channel: String) -> void:
	if not enabled or _open_event.is_empty():
		return
	_open_event["channels"][channel] = true


## A channel note that is not tied to the "current" event (e.g. a global shake).
func note_global(channel: String) -> void:
	if not enabled:
		return
	if channel == "hitstop":
		_hitstop_count += 1
	for rec in _events:
		if not rec.get("closed", false) and rec["frame"] >= _frame - EVENT_WINDOW_FRAMES:
			rec["channels"][channel] = true
	if not _open_event.is_empty():
		_open_event["channels"][channel] = true


func end_event() -> void:
	if not enabled or _open_event.is_empty():
		return
	_open_event["closed"] = true
	_events.append(_open_event)
	_open_event = {}


func count_channel(channel: String) -> void:
	if channel == "hitstop":
		_hitstop_count += 1


## --- per-frame sampling ---------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not enabled:
		return
	_frame += 1
	# Close events whose window elapsed so late channels cannot retroactively pass them.
	for rec in _events:
		if not rec.get("closed", false) and _frame - rec["frame"] > EVENT_WINDOW_FRAMES:
			rec["closed"] = true
			event_closed.emit(rec)
	if not _open_event.is_empty() and _frame - _open_event["frame"] > EVENT_WINDOW_FRAMES:
		_open_event["closed"] = true
		_events.append(_open_event)
		event_closed.emit(_events[-1])
		_open_event = {}

	var player := _player()
	if player == null:
		return
	_samples += 1
	_measure_penetration(player)
	_measure_overlap(player)
	_measure_camera()
	if GameState.hp <= 2:
		_low_hp_frames += 1


func _measure_penetration(player: Node2D) -> void:
	_ensure_grid()
	if not _grid_built:
		return
	var pos: Vector2 = player.global_position
	# Foot box is 8x6 centred 3 px above the origin (see player.tscn BodyShape).
	var half_w := 4.0
	var box_top := pos.y - 6.0
	var box_bottom := pos.y
	var deepest := 0.0
	for dx in [-half_w, 0.0, half_w]:
		for dy in [box_top, pos.y - 3.0, box_bottom]:
			var cell := Vector2i(int(floor((pos.x + dx) / _tile)), int(floor(dy / _tile)))
			if _walkable.get(cell, false):
				continue
			# how far into the solid tile the sample point is
			var cell_rect := Rect2(Vector2(cell) * _tile, Vector2(_tile, _tile))
			var p := Vector2(pos.x + dx, dy)
			var inside_x: float = minf(p.x - cell_rect.position.x, cell_rect.end.x - p.x)
			var inside_y: float = minf(p.y - cell_rect.position.y, cell_rect.end.y - p.y)
			deepest = maxf(deepest, minf(inside_x, inside_y))
	if deepest > 0.5:
		_penetration_frames += 1
		_max_penetration = maxf(_max_penetration, deepest)


func _measure_overlap(player: Node2D) -> void:
	var worst := 0.0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		var h := enemy.get_node_or_null("Health")
		if h and "hp" in h and int(h.hp) <= 0:
			continue
		var d: float = player.global_position.distance_to((enemy as Node2D).global_position)
		# sprite half-heights are roughly 14-20 px; below 11 px the two sprites read as one blob
		if d < 11.0:
			worst = maxf(worst, 11.0 - d)
	if worst > 0.0:
		_overlap_frames += 1
		_max_overlap = maxf(_max_overlap, worst)


func _measure_camera() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var mag := cam.offset.length()
	if mag > 0.1:
		_shake_frames += 1
		_shake_energy += mag


func _ensure_grid() -> void:
	var current := get_tree().get_first_node_in_group("level")
	if _grid_built and current == _grid_level:
		return
	_level_root = current
	_grid_level = current
	_grid_built = false
	_walkable.clear()
	if _level_root == null or not ("data" in _level_root):
		return
	var data: Dictionary = _level_root.data
	var rows: Array = data.get("map", [])
	if rows.is_empty():
		return
	_tile = int(data.get("tile_size", 16))
	var legend: Dictionary = data.get("legend", {".": "ground", "#": "wall"})
	for y in rows.size():
		var row := String(rows[y])
		for x in row.length():
			var ch := row[x]
			_walkable[Vector2i(x, y)] = String(legend.get(ch, "wall")) == "ground"
	_grid_built = true


func _player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node2D


## --- report ---------------------------------------------------------------

func build_report() -> Dictionary:
	var missing := {}
	for rec in _events:
		if not rec.get("closed", false):
			continue
		var kind := String(rec["kind"])
		var required: Array = REQUIRED_CHANNELS.get(kind, [])
		if required.is_empty():
			continue
		var gaps: Array = []
		for ch in required:
			if not rec["channels"].has(ch):
				gaps.append(ch)
		if not gaps.is_empty():
			if not missing.has(kind):
				missing[kind] = []
			missing[kind].append({"frame": rec["frame"], "missing": gaps, "data": rec["data"]})

	var coverage := {}
	for kind in REQUIRED_CHANNELS.keys():
		var total := int(_event_counts.get(kind, 0))
		var bad := (missing.get(kind, []) as Array).size()
		coverage[kind] = {"events": total, "incomplete": bad,
			"percent": 100.0 if total == 0 else roundf(100.0 * float(total - bad) / float(total))}

	var rules: Array = []
	_add_rule(rules, "no_solid_penetration", _penetration_frames == 0,
		"%d frames inside walls, max depth %.1f px" % [_penetration_frames, _max_penetration])
	_add_rule(rules, "bodies_do_not_merge", _samples == 0 or float(_overlap_frames) / float(_samples) < 0.05,
		"%d/%d frames overlapping an enemy (max %.1f px)" % [_overlap_frames, _samples, _max_overlap])
	_add_rule(rules, "hitstop_fires", _hitstop_count > 0, "%d hit-stops" % _hitstop_count)
	_add_rule(rules, "camera_shake_fires", _shake_frames > 0,
		"%d frames of shake, energy %.1f" % [_shake_frames, _shake_energy])
	for kind in coverage:
		var c: Dictionary = coverage[kind]
		if int(c["events"]) > 0:
			_add_rule(rules, "feedback_complete:%s" % kind, int(c["percent"]) >= 100,
				"%d/%d complete" % [int(c["events"]) - int(c["incomplete"]), int(c["events"])])

	var ok := true
	for r in rules:
		if not r["ok"]:
			ok = false
	var report := {
		"ok": ok,
		"frames": _samples,
		"rules": rules,
		"coverage": coverage,
		"missing": missing,
		"counts": _event_counts,
		"hitstop": _hitstop_count,
		"shake_frames": _shake_frames,
		"shake_energy": roundf(_shake_energy),
		"low_hp_frames": _low_hp_frames,
		"events": _events.size(),
	}
	return report


func _add_rule(rules: Array, id: String, ok: bool, detail: String) -> void:
	rules.append({"id": id, "ok": ok, "detail": detail})


func write_report() -> void:
	if not enabled:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var report := build_report()
	var path := OUT_DIR + "/ux.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
	report["report_path"] = ProjectSettings.globalize_path(path)
	Log.info("ux.report", {"ok": report["ok"]})
	print("UX_RESULT ", JSON.stringify({
		"ok": report["ok"],
		"rules": report["rules"],
		"coverage": report["coverage"],
		"report": report["report_path"],
	}))


func _exit_tree() -> void:
	write_report()