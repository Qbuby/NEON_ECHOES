class_name IsoWorld
extends Node2D
## Isometric scene renderer: floor diamonds, extruded wall blocks, props and
## actors, all depth-sorted into one draw order.
##
## Why not TileMapLayer: Godot's tilemaps are square-grid. Isometric needs the
## 2:1 projection in IsoGrid, per-cell height, and one global draw order across
## floors, walls, props and characters. Doing that with a tilemap means fighting
## the engine's own sorting; here each chunk is a MultiMesh-free Sprite2D batch
## and the ordering is one sorted array we control.
##
## The world is drawn from a data description (see LEVEL_FORMAT.md):
##   { "w": 40, "h": 40,
##     "floor": [ "....####....", ... ],        one char per cell
##     "legend": { ".": {"floor": "asphalt"}, "#": {"floor": "concrete", "wall": 2.0} },
##     "props": [ {"id":"vending","cell":[4,7],"anchor":"south"} ],
##     "actors": [ {"id":"player","cell":[9,9]} ] }

signal cell_picked(cell: Vector2i)

const CELL_LAYER := 0
const ACTOR_LAYER := 0

## Wall height in tile units for a given legend entry; 0 means floor only.
var level: Dictionary = {}
var w: int = 0
var h: int = 0
var floor_chars: Array = []          # row strings
var legend: Dictionary = {}
var heights: Dictionary = {}          # Vector2i -> float, for mouse picking

var _sorted: Array = []              # [{node, key}] rebuilt on add
var _nodes: Array = []
var _dirty := true

var floor_root: Node2D
var wall_root: Node2D
var prop_root: Node2D
var actor_root: Node2D

var _atlas: Dictionary = {}          # tile name -> Rect2 in the sheet
var _sheet: Texture2D
var _sheet_path := ""
var _sheets: Dictionary = {}
var _sheet_by_tile: Dictionary = {}
var _facade_debug := 0


func load_level(data: Dictionary, atlas: Dictionary) -> void:
	level = data
	# The atlas file is {sheet, tile_w, tile_h, tiles:{name:[x,y,w,h]}}; the
	# renderer only needs the inner map and the sheet path.
	_atlas = atlas.get("tiles", atlas)
	w = int(data.get("w", 0))
	h = int(data.get("h", 0))
	floor_chars = data.get("floor", [])
	legend = data.get("legend", {})
	_sheet_path = str(atlas.get("sheet", ""))
	if _sheet_path != "" and ResourceLoader.exists(_sheet_path):
		_sheet = load(_sheet_path) as Texture2D
	# props may come from a second sheet
	if atlas.has("sheets"):
		for name in atlas["sheets"]:
			var p2 := str(atlas["sheets"][name])
			if ResourceLoader.exists(p2):
				_sheets[name] = load(p2) as Texture2D
	# Route each tile name to its owning sheet. The caller merges prop rects into
	# the same `tiles` map, so it must also declare which names came from where:
	# atlas.prop_tiles = [names...]. Without this every prop sampled the tile
	# sheet and rendered as a strip of floor pixels.
	_sheet_by_tile.clear()
	for tname in _atlas.keys():
		_sheet_by_tile[tname] = _sheet
	var prop_sheet: Texture2D = _sheets.get("props", _sheet)
	for tname in atlas.get("prop_tiles", []):
		_sheet_by_tile[str(tname)] = prop_sheet
	for child in get_children():
		child.queue_free()
	# A single container each for organisation, but all sprites are children of
	# the same node so the one sorted z_index list actually orders them. Separate
	# roots at equal z_index would be painted in child order instead.
	floor_root = self
	wall_root = self
	prop_root = self
	actor_root = self
	_nodes.clear()
	heights.clear()
	_build_floor()
	_build_walls()
	_build_props(data.get("props", []))
	_build_actors(data.get("actors", []))
	_dirty = true
	sort_now()


func _make_root(name: String, z: int) -> Node2D:
	var n := Node2D.new()
	n.name = name
	n.z_index = z
	n.y_sort_enabled = false     # we sort ourselves, globally
	add_child(n)
	return n


# ---- geometry -------------------------------------------------------------------

## Screen-space origin so the whole map fits a viewport of `view` pixels.
func fit_origin(view: Vector2) -> Vector2:
	var size: Vector2i = IsoGrid.block_size(w, h)
	return Vector2(view.x * 0.5, view.y * 0.5 - size.y * 0.5 + IsoGrid.HH * 2.0)


func cell_center(cell: Vector2i, z: float = 0.0) -> Vector2:
	var p: Vector2 = IsoGrid.project(float(cell.x), float(cell.y), z)
	return p + _origin()


func _origin() -> Vector2:
	# Centre the map on this node's own position.
	var size: Vector2i = IsoGrid.block_size(w, h)
	return Vector2(-size.x * 0.5, -size.y * 0.5)


func cell_at_screen(p: Vector2) -> Vector2i:
	return IsoGrid.pick_with_heights(p - _origin(), heights)


# ---- floor ----------------------------------------------------------------------

func _build_floor() -> void:
	for y in mini(h, floor_chars.size()):
		var row := str(floor_chars[y])
		for x in mini(w, row.length()):
			var ch := row[x]
			if not legend.has(ch):
				continue
			var def: Dictionary = legend[ch]
			var tile := str(def.get("floor", ""))
			if tile == "" or not _atlas.has(tile):
				continue
			_add_floor_tile(Vector2i(x, y), tile, float(def.get("wall", 0.0)))


func _add_floor_tile(cell: Vector2i, tile: String, wall_h: float) -> void:
	var r: Array = _atlas[tile]
	var spr := Sprite2D.new()
	spr.texture = _sheet_by_tile.get(tile, _sheet)
	spr.region_enabled = true
	spr.region_rect = Rect2(float(r[0]), float(r[1]), float(IsoGrid.TILE_W), float(IsoGrid.TILE_H))
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.centered = false
	# A 64x32 diamond sprite's natural top-left is half a tile left of and half a
	# tile above the cell centre.
	spr.position = cell_center(cell) + Vector2(-IsoGrid.HW, -IsoGrid.HH)
	floor_root.add_child(spr)
	_nodes.append({"node": spr, "key": float(cell.x + cell.y) * 0.01})
	heights[cell] = wall_h


# ---- walls ----------------------------------------------------------------------

func _build_walls() -> void:
	# A building is a mass, not a pile of cubes: every solid cell gets one roof
	# diamond, and only its exposed edges get a facade.
	#
	# The lift is taken from the facade art itself, not from the legend's storey
	# count: the art is authored at fixed pixel heights (48/96/144 px of body),
	# and lifting by anything else leaves the roof floating above the facade.
	for y in mini(h, floor_chars.size()):
		var row := str(floor_chars[y])
		for x in mini(w, row.length()):
			var def: Dictionary = legend.get(row[x], {})
			var wh := float(def.get("wall", 0.0))
			if wh <= 0.0:
				continue
			var cell := Vector2i(x, y)
			var tile := _face_tile_for(wh, "s")
			if tile == "":
				continue
			var lift := float(_atlas[tile][3]) - float(IsoGrid.TILE_H)
			_add_roof(cell, lift)
			if not _solid(cell + Vector2i(0, 1)):
				_add_face(cell, lift, "s")
			if not _solid(cell + Vector2i(1, 0)):
				_add_face(cell, lift, "e")


## Pick the facade whose authored body height is closest to the requested storeys.
func _face_tile_for(storeys: float, which: String) -> String:
	var want := storeys * float(IsoGrid.TILE_H)
	var suffix := "s" if which == "s" else "e"
	var best := ""
	var best_d := 1e9
	for name in _atlas.keys():
		var n := str(name)
		# exact family: face_s, face_s_low, face_s_tall (never face_e*)
		if not (n == "face_" + suffix or n.begins_with("face_" + suffix + "_")):
			continue
		var body := float(_atlas[n][3]) - float(IsoGrid.TILE_H)
		if body <= 0.0:
			continue
		var d := absf(body - want)
		if d < best_d:
			best_d = d
			best = n
	return best


func _char_at(cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= floor_chars.size():
		return ""
	var row := str(floor_chars[cell.y])
	if cell.x < 0 or cell.x >= row.length():
		return ""
	return row[cell.x]


func _solid(cell: Vector2i) -> bool:
	if cell.y < 0 or cell.y >= floor_chars.size():
		return false
	var row := str(floor_chars[cell.y])
	if cell.x < 0 or cell.x >= row.length():
		return false
	var def: Dictionary = legend.get(row[cell.x], {})
	return float(def.get("wall", 0.0)) > 0.0


func _add_roof(cell: Vector2i, lift_px: float) -> void:
	var tile := "roof"
	if not _atlas.has(tile):
		return
	var r: Array = _atlas[tile]
	var spr := Sprite2D.new()
	spr.texture = _sheet_by_tile.get(tile, _sheet)
	spr.region_enabled = true
	spr.region_rect = Rect2(float(r[0]), float(r[1]), float(IsoGrid.TILE_W), float(IsoGrid.TILE_H))
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.centered = false
	# lift the roof by the storey height so it caps the facades
	spr.position = cell_center(cell) + Vector2(-IsoGrid.HW, -IsoGrid.HH - lift_px)
	wall_root.add_child(spr)
	_nodes.append({"node": spr, "key": IsoGrid.depth_key(cell, lift_px / IsoGrid.TILE_H) + 0.002})


func _add_face(cell: Vector2i, lift_px: float, which: String) -> void:
	var tile := _face_tile_for(lift_px / float(IsoGrid.TILE_H), which)
	if tile == "":
		return
	var r: Array = _atlas[tile]
	var spr := Sprite2D.new()
	spr.texture = _sheet_by_tile.get(tile, _sheet)
	spr.region_enabled = true
	spr.region_rect = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.centered = false
	# The face art already includes the top half of the diamond, so it aligns to
	# the cell centre - half the face height, exactly like a prism.
	spr.position = cell_center(cell) + Vector2(-IsoGrid.HW, -IsoGrid.HH - lift_px)
	wall_root.add_child(spr)
	_nodes.append({"node": spr, "key": IsoGrid.depth_key(cell, lift_px / IsoGrid.TILE_H) + 0.004})


# ---- props and actors -----------------------------------------------------------

func _build_props(list: Array) -> void:
	for p in list:
		var cell: Array = p.get("cell", [0, 0])
		var id := str(p.get("id", ""))
		if not _atlas.has(id):
			continue
		var r: Array = _atlas[id]
		var tw := float(r[2]) if r.size() > 2 else float(IsoGrid.TILE_W)
		var th := float(r[3]) if r.size() > 3 else float(IsoGrid.TILE_H)
		var spr := Sprite2D.new()
		spr.texture = _sheet_by_tile.get(id, _sheet)
		spr.region_enabled = true
		spr.region_rect = Rect2(float(r[0]), float(r[1]), tw, th)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.centered = false
		var c := Vector2i(int(cell[0]), int(cell[1]))
		var at := cell_center(c)
		# Anchor decides where the sprite's own bottom edge sits relative to the
		# tile. "ground" rests on the diamond's south corner (crates, bins);
		# "mount" lifts the sprite so it hangs on a facade above the tile
		# (signs, AC units); "center" centres it on the tile.
		var anchor := str(p.get("anchor", "ground"))
		var lift := float(p.get("lift", 0.0))
		match anchor:
			"center":
				spr.position = at + Vector2(-tw * 0.5, -th * 0.5)
			"mount":
				# bottom edge sits one tile up, so the sign hangs over the street
				spr.position = at + Vector2(-tw * 0.5, -th - IsoGrid.HH - lift)
			"roof":
				# rest on the roof plane, which is the block height above the cell
				var block_h := 0.0
				var def2: Dictionary = legend.get(_char_at(c), {})
				block_h = float(def2.get("wall", 0.0)) * float(IsoGrid.TILE_H)
				var face := _face_tile_for(float(def2.get("wall", 0.0)), "s")
				if face != "":
					block_h = float(_atlas[face][3]) - float(IsoGrid.TILE_H)
				spr.position = at + Vector2(-tw * 0.5, -th + IsoGrid.HH - block_h)
			_:
				spr.position = at + Vector2(-tw * 0.5, -th + IsoGrid.HH)
		prop_root.add_child(spr)
		_nodes.append({"node": spr, "key": IsoGrid.depth_key(c, 0.0) + 0.001})
		if bool(p.get("solid", false)):
			heights[c] = maxf(float(heights.get(c, 0.0)), 0.0)


func _build_actors(list: Array) -> void:
	for a in list:
		var cell: Array = a.get("cell", [0, 0])
		var id := str(a.get("id", ""))
		var node := Node2D.new()
		node.name = id
		node.set_meta("cell", Vector2i(int(cell[0]), int(cell[1])))
		node.position = cell_center(Vector2i(int(cell[0]), int(cell[1])))
		actor_root.add_child(node)
		register_actor(node)


## Called by gameplay code after an actor moves; resorts that actor's depth key.
func register_actor(node: Node2D) -> void:
	node.set_meta("iso_registered", true)
	_nodes.append({"node": node, "key": 0.0, "actor": true})
	_dirty = true


func update_actor_cell(node: Node2D, cell: Vector2i) -> void:
	node.set_meta("cell", cell)
	node.position = cell_center(cell)
	_dirty = true


func _process(_delta: float) -> void:
	if not _dirty:
		return
	_dirty = false
	sort_now()


## One global painter's-algorithm pass. Actors get their key from the cell they
## stand on, so a character walks behind a wall when its cell is behind it and in
## front when it is nearer, without any per-scene configuration.
func sort_now() -> void:
	for entry in _nodes:
		if entry.get("actor", false):
			var node: Node2D = entry["node"]
			if is_instance_valid(node):
				var cell: Vector2i = node.get_meta("cell", Vector2i.ZERO)
				entry["key"] = IsoGrid.depth_key(cell, 0.0) + 0.002
	_nodes.sort_custom(func(a, b): return float(a["key"]) < float(b["key"]))
	# Painters order: assign drawn order through z_index on a single layer so
	# the engine honours it inside each root.
	# Godot's z_index range is +-4096. Floors share a cell's depth key with the
	# wall on it, so assign each sprite its rank directly: 2,000 sorted items map
	# to 2,000 distinct z values, which is well inside the range.
	for i in _nodes.size():
		var node = _nodes[i].get("node")
		if is_instance_valid(node):
			node.z_index = i - 2000


func actor_count() -> int:
	var n := 0
	for e in _nodes:
		if e.get("actor", false):
			n += 1
	return n
