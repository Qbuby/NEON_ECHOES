extends SceneTree
## Unit test for the isometric projection. Runs headless with no window, so the
## maths is verified before any renderer is built on top of it.
##
##   godot --headless -s res://tests/test_iso_grid.gd

var passed := 0
var failed := 0


func _initialize() -> void:
	var G = load("res://src/world/iso_grid.gd")

	# --- axes ---------------------------------------------------------------
	# +x must move right and down by half a diamond; +y must move left and down.
	var o: Vector2 = G.project(0, 0)
	_eq(G.project(1, 0) - o, Vector2(32, 16), "x axis moves half a diamond down-right")
	_eq(G.project(0, 1) - o, Vector2(-32, 16), "y axis moves half a diamond down-left")
	_eq(G.project(1, 1) - o, Vector2(0, 32), "both axes move straight down a full diamond")
	_eq(G.project(0, 0, 1) - o, Vector2(0, -32), "one height unit lifts a full diamond")

	# --- round trip ---------------------------------------------------------
	var ok := true
	for x in [-7, -1, 0, 1, 5, 40]:
		for y in [-7, -1, 0, 1, 5, 40]:
			var p: Vector2 = G.project(float(x), float(y))
			var back: Vector2 = G.unproject(p)
			if absf(back.x - float(x)) > 0.001 or absf(back.y - float(y)) > 0.001:
				ok = false
				print("  round trip failed at ", x, ",", y, " -> ", back)
	_check(ok, "project/unproject round-trips on the integer lattice")

	# fractional round trip, which mouse picking depends on
	ok = true
	for gx in [0.25, 3.5, 12.75]:
		for gy in [0.1, 7.9, 23.33]:
			var back: Vector2 = G.unproject(G.project(gx, gy))
			if absf(back.x - gx) > 0.001 or absf(back.y - gy) > 0.001:
				ok = false
	_check(ok, "project/unproject round-trips on fractional coordinates")

	# --- diamond shape ------------------------------------------------------
	# A cell's four corners must be exactly one tile apart and form a 2:1 diamond.
	var n: Vector2 = G.cell_corner(Vector2i(0, 0), 0)
	var e: Vector2 = G.cell_corner(Vector2i(0, 0), 1)
	var s: Vector2 = G.cell_corner(Vector2i(0, 0), 2)
	var w: Vector2 = G.cell_corner(Vector2i(0, 0), 3)
	_eq(e - w, Vector2(64, 0), "diamond is 64 px wide")
	_eq(s - n, Vector2(0, 32), "diamond is 32 px tall")
	_check(absf((e - n).length() - (s - e).length()) < 0.001, "diamond is symmetric (2:1)")

	# --- picking ------------------------------------------------------------
	_eq(G.pick(G.project(3, 5)), Vector2i(3, 5), "picking the centre of a cell returns it")
	ok = true
	for cell in [Vector2i(0, 0), Vector2i(9, 2), Vector2i(31, 17)]:
		var centre: Vector2 = G.project(float(cell.x), float(cell.y))
		# a click 20px right of centre stays inside a 64x32 diamond
		if G.pick(centre + Vector2(20, 0)) != cell:
			ok = false
	_check(ok, "picking near a cell centre stays in that cell")

	_check(G.point_in_cell(G.project(4, 4), Vector2i(4, 4)), "cell centre is inside its diamond")
	_check(not G.point_in_cell(G.project(4, 4) + Vector2(0, 20), Vector2i(4, 4)),
		"a point below the diamond is outside it")

	# --- depth ordering -----------------------------------------------------
	# Painter's algorithm: a cell with a larger x+y is nearer the camera.
	_check(G.depth_key(Vector2i(1, 1)) > G.depth_key(Vector2i(0, 0)),
		"nearer cell sorts in front")
	_check(G.depth_key(Vector2i(5, 5)) > G.depth_key(Vector2i(0, 9)),
		"both diagonal axes contribute equally to depth")
	_check(G.depth_key(Vector2i(1, 1), 2.0) > G.depth_key(Vector2i(1, 1), 0.0),
		"a taller object at the same cell sorts in front")

	# --- block size ---------------------------------------------------------
	# A square block projects to a 2:1 rectangle in isometric: 4 tiles across and
	# 4 away give (4+4) half-widths and (4+4) half-heights.
	_eq(G.block_size(4, 4), Vector2i(256, 128), "a 4x4 block is 256x128 px (2:1)")
	_eq(G.block_size(1, 1), Vector2i(64, 32), "a 1x1 block is one diamond")

	_finish()


func _eq(actual, expected, label: String) -> void:
	if actual == expected:
		passed += 1
		print("PASS  ", label)
	else:
		failed += 1
		print("FAIL  ", label, "  expected=", expected, " actual=", actual)


func _check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("PASS  ", label)
	else:
		failed += 1
		print("FAIL  ", label)


func _finish() -> void:
	print("ISO_RESULT {\"passed\":%d,\"failed\":%d}" % [passed, failed])
	quit(1 if failed > 0 else 0)
