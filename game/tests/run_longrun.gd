extends SceneTree
## 30-minute continuous run at the delivery resolution, sampling memory and
## frame times throughout.
##
## The spec asks for a 30-minute run with no persistent memory growth, no crash,
## no black screen, no unrecoverable hang. This records the trend.
##
##   godot --headless --resolution 1920x1080 --path game -s res://tests/run_longrun.gd
##
## Minutes are configurable so a shorter smoke run is possible:
##   --longrun-minutes=2

const DEFAULT_MINUTES := 30

var samples: Array[Dictionary] = []
var node: Node2D
var minutes := DEFAULT_MINUTES
var worst_frame := 0.0
var frames := 0
var crashes: Array[String] = []
var load_times: Array[float] = []
var warm_load := 0.0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if str(arg).begins_with("--longrun-minutes="):
			minutes = int(str(arg).split("=")[1])
	minutes = clampi(minutes, 1, 120)
	var scene := load("res://scenes/iso_playable.tscn") as PackedScene
	if scene == null:
		print("LONGRUN_RESULT ", JSON.stringify({"ok": false, "reason": "scene_missing"}))
		quit(1)
		return
	node = scene.instantiate()
	root.add_child(node)
	await process_frame
	if not node.setup("corp_core"):
		print("LONGRUN_RESULT ", JSON.stringify({"ok": false, "reason": "load_failed"}))
		quit(1)
		return
	# pay the one-off cost of a load + the allocator's retention before baseline
	var lt0 := Time.get_ticks_usec()
	node._enter("corp_core_lobby")
	await process_frame
	node._enter("corp_core")
	for k in 4:
		await process_frame
	var warm_load := float(Time.get_ticks_usec() - lt0) / 1000.0
	await _run(warm_load)


## Keep the game busy the way a player would: move, fire, switch areas, open
## screens. A run that just idles would not exercise anything.
func _run(warm_load: float) -> void:
	var end_ms := Time.get_ticks_msec() + minutes * 60000
	var last_sample := 0
	var tick := 0
	var areas := ["corp_core_lobby", "corp_core", "ind_belt", "corp_core_vault",
		"night_row", "corp_core"]
	while Time.get_ticks_msec() < end_ms:
		tick += 1
		var t0 := Time.get_ticks_usec()
		# movement through the real move_target path
		var step := Vector2i(1, 0) if (tick % 4) < 2 else Vector2i(0, 1)
		var want: Vector2i = node.player_cell + step
		if bool(node.walkable.get(want, false)):
			node.move_target = want
		# combat: fire often enough to exercise projectiles and juice
		if tick % 6 == 0:
			await process_frame
			node._fire_cd = 0.0
			node._try_attack()
		# one more switch mid-run, timed: a load may take up to 5 s by the spec,
		# a gameplay frame may not. Exhaustive switching is covered by run_soak.
		if tick == 1200:
			var lt0 := Time.get_ticks_usec()
			node._enter("corp_core_lobby")
			await process_frame
			node._enter("corp_core")
			for k in 4:
				await process_frame
			load_times.append(float(Time.get_ticks_usec() - lt0) / 1000.0)
			continue
		# screens open and close, which rebuilds the UI tree
		if tick % 900 == 0:
			node._toggle_screen("inventory")
		elif tick % 900 == 30:
			node._toggle_screen("inventory")
		await process_frame
		var dt := float(Time.get_ticks_usec() - t0) / 1000.0
		frames += 1
		worst_frame = maxf(worst_frame, dt)
		var now := Time.get_ticks_msec()
		if now - last_sample >= 30000:
			last_sample = now
			_sample(now, dt)
	_finish()


func _count_nodes(n: Node) -> int:
	var total := 1
	for c in n.get_children():
		total += _count_nodes(c)
	return total


func _sample(now_ms: int, last_dt: float) -> void:
	var mem := float(OS.get_static_memory_usage()) / 1048576.0
	var st: Dictionary = node.get_state()
	samples.append({
		"t_s": (now_ms - _start_ms()) / 1000,
		"mem_mb": snappedf(mem, 0.1),
		"area": str(st.get("area", "")),
		"frames": frames,
		"last_ms": snappedf(last_dt, 0.01),
		"nodes": _count_nodes(node),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
	})


var _t0_ms := 0
func _start_ms() -> int:
	return _t0_ms


func _finish() -> void:
	if _t0_ms == 0:
		_t0_ms = Time.get_ticks_msec()
	# Only compare samples taken in the same area: a 30x20 interior and an 80x80
	# district have different working sets, so mixing them reports a phantom leak.
	var same_area: Array = []
	for s in samples:
		if str(s.get("area", "")) == "corp_core":
			same_area.append(float(s["mem_mb"]))
	if same_area.is_empty():
		same_area = samples.map(func(s): return float(s["mem_mb"]))
	var first: float = same_area[0] if not same_area.is_empty() else 0.0
	var last: float = same_area[same_area.size() - 1] if not same_area.is_empty() else 0.0
	var peak: float = 0.0
	for s in samples:
		peak = maxf(peak, float(s["mem_mb"]))
	# same plateau test as the soak: late growth must not exceed early growth
	var half := same_area.size() / 2
	var mid: float = same_area[half] if half > 0 and half < same_area.size() else first
	var early: float = mid - first
	var late: float = last - mid
	var leak := late > maxf(8.0, early * 0.5)
	var worst_load: float = warm_load
	for v in load_times:
		worst_load = maxf(worst_load, v)
	var ok: bool = crashes.is_empty() and not leak and peak < 3072.0 \
		and worst_frame <= 100.0 and worst_load <= 5000.0 and last < 3072.0
	_report({
		"ok": ok,
		"minutes": minutes,
		"frames": frames,
		"avg_fps": snappedf(float(frames) / float(maxi(1, minutes * 60)), 0.1),
		"worst_gameplay_frame_ms": snappedf(worst_frame, 0.01),
		"area_loads": load_times.size(),
		"worst_load_ms": snappedf(worst_load, 0.01),
		"mem_first_mb": first,
		"samples_same_area": same_area.size(),
		"mem_last_mb": last,
		"mem_peak_mb": peak,
		"early_growth_mb": snappedf(early, 0.1),
		"late_growth_mb": snappedf(late, 0.1),
		"leak_detected": leak,
		"crashes": crashes,
		"samples": samples,
	})
	quit(0 if ok else 1)


func _report(data: Dictionary) -> void:
	var f := FileAccess.open("res://evidence/longrun.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "  "))
		f.close()
	var brief := data.duplicate()
	brief.erase("samples")
	print("LONGRUN_RESULT ", JSON.stringify(brief))
