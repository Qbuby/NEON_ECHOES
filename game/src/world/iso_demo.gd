extends Node2D
## Proof-of-renderer scene: builds a real isometric street block from the tile
## atlas, with extruded walls, props, an actor that walks the grid, and a camera
## that follows in screen space.
##
## This is the smallest thing that can answer the question the whole redesign
## turns on: does an isometric renderer at this camera scale actually look like
## the concept art? Everything else is built on the answer.

const IsoGridScript := preload("res://src/world/iso_grid.gd")
const IsoWorldScript := preload("res://src/world/iso_world.gd")
const IsoLightingScript := preload("res://src/world/iso_lighting.gd")
const IsoHudScript := preload("res://src/ui/iso_hud.gd")
const ATLAS := "res://assets/tiles/corp_iso/corp_iso.json"
const PROPS_ATLAS := "res://assets/tiles/corp_props/corp_props.json"
const DISTRICT := "res://data/districts/corp_core.iso.json"

var world: IsoWorld
var camera: Camera2D
var player: Node2D
var level_data: Dictionary
var player_cell := Vector2i(8, 12)
var move_target := Vector2i(8, 12)
var facing := "s"

var hud: IsoHud


func _ready() -> void:
	_build_level()
	world = IsoWorldScript.new()
	world.name = "IsoWorld"
	add_child(world)
	var atlas: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ATLAS))
	# props live on their own sheet; merge their rects in and let the renderer
	# resolve each rect against its own texture
	var props_atlas: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROPS_ATLAS))
	var merged: Dictionary = atlas.get("tiles", {}).duplicate()
	var prop_names: Array = []
	for k in props_atlas.get("tiles", {}):
		merged[k] = props_atlas["tiles"][k]
		prop_names.append(k)
	atlas["tiles"] = merged
	atlas["prop_tiles"] = prop_names
	atlas["sheets"] = {"tiles": atlas["sheet"], "props": props_atlas["sheet"]}
	level_data = JSON.parse_string(FileAccess.get_file_as_string(DISTRICT))
	# take the spawn from the level, not a hardcoded demo cell
	for a in level_data.get("actors", []):
		if str(a.get("id", "")) == "player":
			var c: Array = a.get("cell", [8, 12])
			player_cell = Vector2i(int(c[0]), int(c[1]))
			move_target = player_cell
	world.load_level(level_data, atlas)
	world.position = _map_center()
	_make_player()
	_make_lighting()
	_make_camera()
	_make_hud()
	print("ISO_DEMO ready cells=%d" % (level_data["w"] * level_data["h"]))


func _build_level() -> void:
	# A 20x20 block: a street running north-south, buildings either side, a
	# plaza pocket and two alleys. Enough variety to judge depth and shading.
	var w := 20
	var h := 20
	var rows := []
	for y in h:
		var row := ""
		for x in w:
			var ch := "."
			if x < 3 or x > 16:
				ch = "#"                       # side buildings
			elif y < 3 or y > 16:
				ch = "#"                       # end buildings
			elif (x == 3 or x == 16) and (y % 7 == 0):
				ch = "D"                       # doorway gap in the wall
			elif (x >= 8 and x <= 11) and (y >= 8 and y <= 11):
				ch = "P"                       # plaza marble
			row += ch
		rows.append(row)
	# punch a street through both ends so it reads as a through-route
	var lvl := {
		"w": w, "h": h, "floor": rows,
		"legend": {
			".": {"floor": "floor_a"},
			"#": {"floor": "floor_concrete", "wall": 2.0, "wall_tile": "wall_h32"},
			"B": {"floor": "floor_plaza", "wall": 3.0, "wall_tile": "wall_h48"},
			"D": {"floor": "floor_b"},
			"P": {"floor": "floor_marble"},
		},
		"props": [
			{"id": "prop_crate", "cell": [5, 7]},
			{"id": "prop_vend", "cell": [15, 9]},
			{"id": "prop_sign", "cell": [12, 3]},
			{"id": "prop_crate", "cell": [7, 14]},
		],
		"actors": [],
	}
	level_data = lvl


func _map_center() -> Vector2:
	var size: Vector2i = IsoGridScript.block_size(level_data["w"], level_data["h"])
	return Vector2(size.x * 0.5, size.y * 0.5)


func _make_player() -> void:
	player = Node2D.new()
	player.name = "Rin"
	var spr := ActorSprite.new()
	if spr.setup("res://assets/actors/rin/rin.json"):
		spr.play("idle_s")
	player.add_child(spr)
	player.set_meta("sprite", spr)
	# a soft contact shadow so she does not float
	var shadow := Sprite2D.new()
	var img := Image.create(24, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 8:
		for x in 24:
			var dx := (x - 11.5) / 12.0
			var dy := (y - 3.5) / 4.0
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0.42))
	shadow.texture = ImageTexture.create_from_image(img)
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	player.add_child(shadow)
	player.position = world.cell_center(player_cell)
	world.actor_root.add_child(player)
	world.register_actor(player)


## Neon light pools under every lamp, vending machine, sign and the plaza.
## Positions come from the level's own props so the light follows the furniture.
func _make_lighting() -> void:
	var defs: Array = []
	var palette := {
		"prop_lamp": Color("#9fe4ff"),
		"prop_vending": Color("#38d8ff"),
		"prop_terminal": Color("#38d8ff"),
		"prop_kiosk": Color("#ff2fb4"),
		"prop_barrier": Color("#ffd24a"),
	}
	for p in level_data.get("props", []):
		var id := str(p.get("id", ""))
		if not palette.has(id):
			continue
		var cell: Array = p.get("cell", [0, 0])
		var c := Vector2i(int(cell[0]), int(cell[1]))
		var at: Vector2 = world.cell_center(c) + Vector2(0, 6)
		var radius := 74.0 if id == "prop_lamp" else 58.0
		defs.append({"pos": at, "radius": radius, "color": palette[id],
			"strength": 0.40 if id == "prop_lamp" else 0.30})
	# a wide magenta wash over the junction, like the concept street
	var mid := Vector2i(level_data["w"] / 2, level_data["h"] / 2)
	defs.append({"pos": world.cell_center(mid), "radius": 150.0,
		"color": Color("#ff2fb4"), "strength": 0.16})
	var lighting: Node2D = IsoLightingScript.new()
	lighting.name = "Lighting"
	add_child(lighting)
	lighting.setup(defs)
	# behind actors and props, above the floor
	lighting.z_index = -900


func _make_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera"
	camera.zoom = Vector2(1.35, 1.35)
	# a camera on a Node2D child needs its own position reset to the player
	camera.position = Vector2.ZERO
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 9.0
	player.add_child(camera)
	camera.make_current()


func _make_hud() -> void:
	hud = IsoHudScript.new()
	add_child(hud)
	hud.set_values({
		"hp": 78.0, "hp_max": 100.0, "ram": 6.0, "ram_max": 8.0,
		"cred": 1050, "name": "RIN", "status": 3,
		"objective": "FIND THE CURATOR — SPIRE LOBBY",
	})
	hud.show_toast("SECTOR 07 · NEON ROW", 2.4)



func _process(delta: float) -> void:
	var step := 0.0
	var dir := Vector2i.ZERO
	if Input.is_action_pressed("move_left"):
		dir += Vector2i(-1, 0)
	if Input.is_action_pressed("move_right"):
		dir += Vector2i(1, 0)
	if Input.is_action_pressed("move_up"):
		dir += Vector2i(0, -1)
	if Input.is_action_pressed("move_down"):
		dir += Vector2i(0, 1)
	if dir != Vector2i.ZERO:
		move_target = player_cell + dir.sign()
	# slide toward the target cell in screen space; the actor's depth key follows
	# its own cell so it passes behind and in front of walls correctly
	var target: Vector2 = world.cell_center(move_target)
	var to_target: Vector2 = target - player.position
	var spr: ActorSprite = player.get_meta("sprite", null)
	if to_target.length() > 1.0:
		player.position += to_target.normalized() * minf(to_target.length(), 190.0 * delta)
		# On a 2:1 screen, screen-space direction maps to a grid direction: moving
		# down-right in pixels is +x in the grid. Face along the dominant screen axis.
		if absf(to_target.x) > absf(to_target.y) * 0.5:
			facing = "e" if to_target.x > 0 else "w"
		else:
			facing = "s" if to_target.y > 0 else "n"
		if spr:
			spr.play("walk_" + facing)
	else:
		player.position = target
		if player_cell != move_target:
			player_cell = move_target
			world.update_actor_cell(player, player_cell)
		if spr:
			spr.play("idle_" + facing)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local: Vector2 = world.to_local(get_global_mouse_position())
		var cell: Vector2i = world.cell_at_screen(local)
		if _walkable(cell):
			move_target = cell


func _walkable(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= level_data["w"] or cell.y >= level_data["h"]:
		return false
	var row: String = level_data["floor"][cell.y]
	var ch := row[cell.x]
	return ch == "." or ch == "P" or ch == "D"
