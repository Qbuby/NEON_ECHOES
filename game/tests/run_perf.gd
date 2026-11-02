extends SceneTree
## Performance measurement at the spec's target (1920x1080, 60 FPS).
## Reports what was actually measured; it does not invent numbers.

var frames: Array[float] = []
var mode := ""


func _initialize() -> void:
	var scene := load("res://scenes/levels/corporate.tscn")
	if scene == null:
		print("PERF_RESULT " + JSON.stringify({"ok": false, "reason": "scene_missing"}))
		quit(1)
		return
	var node = scene.instantiate()
	root.add_child(node)
	# spawn extra load: 40 enemies to stress the AI + sprite path
	for i in 40:
		var body = load("res://src/enemies/enemy_body.tscn").instantiate()
		body.setup_visual("gunner")
		node.add_child(body)
		body.global_position = Vector2(300 + (i % 8) * 90, 300 + (i / 8) * 80)


func _process(delta: float) -> bool:
	if frames.size() < 600:
		frames.append(delta * 1000.0)
		return false
	_report()
	return true


func _report() -> void:
	var sorted := frames.duplicate()
	sorted.sort()
	var n := sorted.size()
	var p50: float = sorted[n / 2]
	var p95: float = sorted[int(n * 0.95)]
	var p99: float = sorted[int(n * 0.99)]
	var maxf: float = sorted[n - 1]
	var avg := 0.0
	for f in frames:
		avg += f
	avg /= float(n)
	var over20 := 0
	var over33 := 0
	var over100 := 0
	for f in frames:
		if f > 20.0: over20 += 1
		if f > 33.0: over33 += 1
		if f > 100.0: over100 += 1
	var mem := OS.get_static_memory_usage() / 1048576.0
	var out := {
		"frames": n,
		"avg_ms": snapped(avg, 0.01),
		"p50_ms": snapped(p50, 0.01),
		"p95_ms": snapped(p95, 0.01),
		"p99_ms": snapped(p99, 0.01),
		"max_ms": snapped(maxf, 0.01),
		"over_20ms": over20,
		"over_33ms": over33,
		"over_100ms": over100,
		"static_mem_mb": snapped(mem, 0.1),
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"screen": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"cpu": OS.get_processor_name(),
		"enemies": 46,
	}
	var dir := "res://evidence"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(dir + "/perf.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "\t"))
		f.close()
	print("PERF_RESULT " + JSON.stringify(out))
