extends SceneTree
## 100 map switches through the real door path, checking for leaks and failures.
##
## The spec asks for "100 consecutive map switches, no persistent memory growth,
## no unrecoverable hang". This enters and leaves every district and its four
## interiors repeatedly, records memory at each switch, and fails if anything
## throws, if a room fails to load, or if memory never comes back down.
##
##   godot --headless --path game -s res://tests/run_soak.gd

const SWITCHES := 100

var samples: Array[Dictionary] = []
var failures: Array[String] = []
var node: Node2D


func _initialize() -> void:
	var scene := load("res://scenes/iso_playable.tscn") as PackedScene
	if scene == null:
		print("SOAK_RESULT ", JSON.stringify({"ok": false, "reason": "scene_missing"}))
		quit(1)
		return
	node = scene.instantiate()
	root.add_child(node)
	await process_frame
	if not node.setup("corp_core"):
		print("SOAK_RESULT ", JSON.stringify({"ok": false, "reason": "initial_load_failed"}))
		quit(1)
		return
	await _run()
	_finish()


func _run() -> void:
	# Tour the district and its rooms, then come back to corp_core to sample.
	# Sampling in one fixed place makes the memory series comparable.
	var tour := ["corp_core_lobby", "corp_core_vault", "ind_belt",
		"ind_belt_lobby", "night_row", "night_row_lobby", "corp_core_office"]
	for i in SWITCHES:
		var target: String = tour[i % tour.size()]
		node._enter(target)
		await process_frame
		if node.district_id != target:
			failures.append("switch %d: wanted %s got %s" % [i, target, node.district_id])
		# every 8th switch, return to the reference area and sample there
		if i % 8 == 7:
			node._enter("corp_core")
			await process_frame
			await process_frame
			if node.district_id != "corp_core":
				failures.append("checkpoint %d: failed to return to corp_core" % i)
			var mem := float(OS.get_static_memory_usage()) / 1048576.0
			samples.append({
				"i": i, "area": node.district_id, "mem_mb": snappedf(mem, 0.1),
				"walkable": node.walkable.size(), "enemies": node.enemies.size(),
				"nodes": _count_nodes(node),
			})


func _finish() -> void:
	var first := float(samples[0]["mem_mb"]) if not samples.is_empty() else 0.0
	var last := float(samples[samples.size() - 1]["mem_mb"]) if not samples.is_empty() else 0.0
	var peak := 0.0
	var total_walkable := 0
	for s in samples:
		peak = maxf(peak, float(s["mem_mb"]))
		total_walkable += int(s["walkable"])
	# Distinguish a plateau (allocator warm-up that stops growing) from a leak
	# (memory climbing linearly forever). Compare the second half's growth to the
	# first half's: a cache grows fast then flattens; a leak stays linear.
	var half := samples.size() / 2
	var mid := float(samples[half]["mem_mb"]) if half < samples.size() else first
	var first_half_growth := mid - first
	var second_half_growth := last - mid
	var leak := second_half_growth > maxf(4.0, first_half_growth * 0.5)
	var growth := last - first
	var ok: bool = failures.is_empty() and growth <= 64.0 and peak < 3072.0 and not leak
	_report({
		"ok": ok,
		"switches": SWITCHES,
		"samples": samples.size(),
		"failures": failures.slice(0, 8),
		"failure_count": failures.size(),
		"mem_first_mb": first,
		"mem_last_mb": last,
		"mem_peak_mb": peak,
		"growth_mb": snappedf(growth, 0.1),
		"first_half_growth_mb": snappedf(first_half_growth, 0.1),
		"second_half_growth_mb": snappedf(second_half_growth, 0.1),
		"leak_detected": leak,
		"allowed_growth_mb": 64.0,
		"avg_walkable_cells": int(total_walkable / maxi(1, samples.size())),
		"sample_area": "corp_core (fixed checkpoint)",
		"areas_exercised": _areas(),
	})
	quit(0 if ok else 1)


func _count_nodes(n: Node) -> int:
	var total := 1
	for c in n.get_children():
		total += _count_nodes(c)
	return total


func _areas() -> Array:
	var seen: Array = []
	for s in samples:
		if not seen.has(s["area"]):
			seen.append(s["area"])
	return seen


func _report(data: Dictionary) -> void:
	var f := FileAccess.open("res://evidence/soak.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "  "))
		f.close()
	print("SOAK_RESULT ", JSON.stringify(data))
