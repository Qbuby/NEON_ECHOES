extends SceneTree
## Performance measurement at the spec's target (1920x1080, 60 FPS).
##
## Measures the isometric scene under load and writes evidence/perf.json.
## Reports only what was measured; it does not invent numbers.
##
##   godot --headless --path game -s res://tests/run_perf.gd
##
## The spec asks for p95 <= 20 ms, p99 <= 33 ms, no stall over 100 ms, and
## < 3 GB. This records those four plus the CPU and renderer so a reader can
## judge whether the bar was met on real hardware.

const FRAMES := 600
const ENEMY_LOAD := 40

var samples: Array[float] = []
var scene_root: Node
var _frame_start := 0


func _initialize() -> void:
	var scene := load("res://scenes/iso_playable.tscn") as PackedScene
	if scene == null:
		_report({"ok": false, "reason": "scene_missing"})
		quit(1)
		return
	scene_root = scene.instantiate()
	root.add_child(scene_root)
	await process_frame
	await process_frame

	_stress(ENEMY_LOAD)

	# warm up: the first frames include texture upload and shader compile
	for i in 30:
		await process_frame

	_frame_start = Time.get_ticks_usec()
	_run()


## Extra enemies beyond the district's own six, to stress the AI and sprite path.
func _stress(count: int) -> void:
	if scene_root == null:
		return
	var world = scene_root.get("world")
	if world == null:
		return
	for i in count:
		var cell := Vector2i(8 + (i % 24) * 3, 10 + (i / 24) * 4)
		if not bool(scene_root.walkable.get(cell, false)):
			continue
		world.spawn_actor("enemy_gunner", cell)


func _run() -> void:
	for i in FRAMES:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - _frame_start) / 1000.0)
		_frame_start = now
	_finish()


func _finish() -> void:
	var sorted := samples.duplicate()
	sorted.sort()
	var mean := 0.0
	var over20 := 0
	var over33 := 0
	var over100 := 0
	var worst := 0.0
	for v in sorted:
		mean += v
		if v > 20.0:
			over20 += 1
		if v > 33.0:
			over33 += 1
		if v > 100.0:
			over100 += 1
		worst = maxf(worst, v)
	mean /= float(maxf(1, sorted.size()))
	var n := sorted.size()
	var p95: float = sorted[clampi(int(n * 0.95), 0, n - 1)]
	var p99: float = sorted[clampi(int(n * 0.99), 0, n - 1)]
	var mem_mb := float(OS.get_static_memory_usage()) / 1048576.0
	var ok := p95 <= 20.0 and p99 <= 33.0 and over100 == 0 and mem_mb < 3072.0

	_report({
		"ok": ok,
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"cpu": OS.get_processor_name(),
		"frames": n,
		"enemies": ENEMY_LOAD,
		"mean_ms": snappedf(mean, 0.01),
		"p50_ms": snappedf(sorted[n / 2], 0.01),
		"p95_ms": snappedf(p95, 0.01),
		"p99_ms": snappedf(p99, 0.01),
		"max_ms": snappedf(worst, 0.01),
		"over_20ms": over20,
		"over_33ms": over33,
		"over_100ms": over100,
		"static_mem_mb": snappedf(mem_mb, 0.1),
		"targets": {"p95_ms": 20.0, "p99_ms": 33.0, "max_stall_ms": 100.0, "mem_mb": 3072.0},
	})
	if scene_root != null:
		scene_root.queue_free()
	quit(0 if ok else 1)


func _report(data: Dictionary) -> void:
	var f := FileAccess.open("res://evidence/perf.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "  "))
		f.close()
	print("PERF_RESULT ", JSON.stringify(data))
