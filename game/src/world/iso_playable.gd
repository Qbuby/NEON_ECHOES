class_name IsoPlayable
extends Node2D
## The playable isometric district: a scene built by IsoWorld, plus movement with
## collision, aiming, shooting with real projectiles, melee, interaction with
## devices, doors to interiors, and pickups.
##
## Movement is grid-based: the player walks cell to cell, which keeps the actor
## exactly on the 2:1 plane and makes collision a lookup rather than a physics
## query. Everything about combat and interaction reuses src/systems unchanged.

signal area_changed(area: String)
signal door_used(target: String)
signal device_used(kind: String)
signal enemy_killed(id: String)

const IsoGridScript := preload("res://src/world/iso_grid.gd")
const IsoWorldScript := preload("res://src/world/iso_world.gd")
const IsoLightingScript := preload("res://src/world/iso_lighting.gd")
const IsoHudScript := preload("res://src/ui/iso_hud.gd")

const MOVE_SPEED := 190.0
const TILE := Vector2i(64, 32)

@export var district_id := "corp_core"
var level: Dictionary = {}
var world: IsoWorld
var hud: IsoHud
var camera: Camera2D
var player: Node2D
var player_cell := Vector2i(0, 0)
var move_target := Vector2i(0, 0)
var facing := "s"

var enemies: Array = []          # [{node, ai, cell}]
var bullets: Array = []          # [{pos, dir, ttl, damage}]

var walkable: Dictionary = {}
var blocks: Dictionary = {}      # cell -> device kind

var hp := 100.0
var hp_max := 100.0
var cred := 1050
var ram := 8.0
var ram_max := 8.0
var kills := 0

var _fire_cd := 0.0
var _has_target := false


func _ready() -> void:
	setup(district_id)


func setup(id: String) -> bool:
	district_id = id
	var path := "res://data/districts/%s.iso.json" % id
	if not FileAccess.file_exists(path):
		_log("iso.district_missing", {"id": id})
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return false
	level = parsed
	_build_walkable()
	_build_world()
	_spawn_actors()
	_make_hud()
	_log("iso.ready", {"district": id, "enemies": enemies.size(),
		"walkable": walkable.size()})
	return true


func _log(event: String, data: Dictionary) -> void:
	# Log is an autoload; a SceneTree-driven test has no autoloads, so look it up
	# through the tree rather than the global name.
	var tree := get_tree()
	var l = tree.root.get_node_or_null("Log") if tree != null else null
	if l != null:
		l.info(event, data)
	else:
		print(event, " ", JSON.stringify(data))


# ---- world ---------------------------------------------------------------------

func _build_walkable() -> void:
	var rows: Array = level.get("floor", [])
	var legend: Dictionary = level.get("legend", {})
	for y in rows.size():
		var row := str(rows[y])
		for x in mini(int(level.get("w", 0)), row.length()):
			var def: Dictionary = legend.get(row[x], {})
			var solid := float(def.get("wall", 0.0)) > 0.0
			walkable[Vector2i(x, y)] = not solid
	for d in level.get("interactables", []):
		var c: Array = d.get("cell", [0, 0])
		blocks[Vector2i(int(c[0]), int(c[1]))] = str(d.get("kind", "device"))


func _build_world() -> void:
	world = IsoWorldScript.new()
	world.name = "World"
	add_child(world)
	var atlas := _merged_atlas()
	world.load_level(level, atlas)
	world.position = Vector2(0, 0)
	_add_lighting()


func _merged_atlas() -> Dictionary:
	var tiles_name: String = {"corp_core": "corp", "ind_belt": "ind",
		"night_row": "night"}.get(district_id, "corp")
	# interior districts inherit their parent's tiles
	for prefix in ["corp_core", "ind_belt", "night_row"]:
		if district_id.begins_with(prefix):
			tiles_name = {"corp_core": "corp", "ind_belt": "ind",
				"night_row": "night"}[prefix]
			break
	var base := "res://assets/tiles/%s_iso/%s_iso.json" % [tiles_name, tiles_name]
	var props := "res://assets/tiles/%s_props/%s_props.json" % [tiles_name, tiles_name]
	var atlas: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base))
	var merged: Dictionary = atlas.get("tiles", {}).duplicate()
	var prop_names: Array = []
	if FileAccess.file_exists(props):
		var pa: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(props))
		for k in pa.get("tiles", {}):
			merged[k] = pa["tiles"][k]
			prop_names.append(k)
		atlas["sheets"] = {"props": pa["sheet"]}
	atlas["tiles"] = merged
	atlas["prop_tiles"] = prop_names
	return atlas


func _add_lighting() -> void:
	var palette := {
		"prop_lamp": Color("#9fe4ff"), "prop_vending": Color("#38d8ff"),
		"prop_terminal": Color("#38d8ff"), "prop_kiosk": Color("#ff2fb4"),
	}
	var defs: Array = []
	for p in level.get("props", []):
		var id := str(p.get("id", ""))
		if not palette.has(id):
			continue
		var c: Array = p.get("cell", [0, 0])
		defs.append({"pos": world.cell_center(Vector2i(int(c[0]), int(c[1]))) + Vector2(0, 6),
			"radius": 76.0 if id == "prop_lamp" else 58.0,
			"color": palette[id], "strength": 0.38 if id == "prop_lamp" else 0.30})
	var lighting: Node2D = IsoLightingScript.new()
	lighting.name = "Lighting"
	add_child(lighting)
	lighting.setup(defs)
	lighting.z_index = -1900


# ---- actors ---------------------------------------------------------------------

func _spawn_actors() -> void:
	for a in level.get("actors", []):
		if str(a.get("id", "")) == "player":
			var c: Array = a.get("cell", [0, 0])
			player_cell = Vector2i(int(c[0]), int(c[1]))
			move_target = player_cell
	player = world.spawn_actor("rin", player_cell)
	player.name = "Rin"
	camera = Camera2D.new()
	camera.name = "Camera"
	camera.zoom = Vector2(1.35, 1.35)
	player.add_child(camera)
	camera.make_current()

	for n in level.get("npcs", []):
		var c: Array = n.get("cell", [0, 0])
		world.spawn_actor(str(n.get("id", "npc_fixer")), Vector2i(int(c[0]), int(c[1])))

	# enemies from the district's spawn list; the district generator places six
	var defs := _load_enemies()
	var spawns: Array = level.get("enemies", [])
	if spawns.is_empty():
		spawns = _default_spawns()
	for i in spawns.size():
		var s: Dictionary = spawns[i]
		var cell: Array = s.get("cell", [0, 0])
		var id := str(s.get("id", "enemy_gunner"))
		var c := Vector2i(int(cell[0]), int(cell[1]))
		if not bool(walkable.get(c, false)):
			continue
		var node := world.spawn_actor(id, c)
		var def: Dictionary = {}
		for e in defs:
			if str(e.get("id", "")) == id.replace("enemy_", ""):
				def = e
				break
		var ai = load("res://src/systems/enemy_ai.gd").new(def)
		ai.pos = world.cell_center(c)
		enemies.append({"node": node, "ai": ai, "cell": c, "id": id})


func _load_enemies() -> Array:
	var p := "res://data/enemies.json"
	if not FileAccess.file_exists(p):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
	return parsed.get("enemies", []) if parsed is Dictionary else []


func _default_spawns() -> Array:
	# six enemies spread along the plaza, three cells apart
	var out: Array = []
	var kinds := ["enemy_gunner", "enemy_rusher", "enemy_heavy",
		"enemy_sniper", "enemy_netrunner", "enemy_drone"]
	for i in kinds.size():
		out.append({"id": kinds[i], "cell": [16 + i * 3, 22 + (i % 3) * 4]})
	return out


# ---- hud ------------------------------------------------------------------------

func _make_hud() -> void:
	hud = IsoHudScript.new()
	add_child(hud)
	hud.set_values({
		"hp": hp, "hp_max": hp_max, "ram": ram, "ram_max": ram_max,
		"cred": cred, "name": "RIN", "status": 3,
		"objective": str(level.get("name", district_id)).to_upper(),
	})


# ---- input and movement ----------------------------------------------------------

func _process(delta: float) -> void:
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_handle_input()
	_move_player(delta)
	_tick_enemies(delta)
	_tick_bullets(delta)


func _handle_input() -> void:
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
		var want := player_cell + dir.sign()
		if bool(walkable.get(want, false)) and not blocks.has(want):
			move_target = want
	if Input.is_action_just_pressed("interact"):
		_try_interact()
	if Input.is_action_pressed("attack"):
		_try_attack()


func _move_player(delta: float) -> void:
	var target: Vector2 = world.cell_center(move_target)
	var to_target: Vector2 = target - player.position
	var spr: ActorSprite = player.get_meta("sprite", null)
	if to_target.length() > 1.0:
		player.position += to_target.normalized() * minf(to_target.length(), MOVE_SPEED * delta)
		if absf(to_target.x) > absf(to_target.y) * 0.5:
			facing = "e" if to_target.x > 0 else "w"
		else:
			facing = "s" if to_target.y > 0 else "n"
		if spr:
			spr.play("walk_" + facing)
	else:
		player.position = target
		player_cell = move_target
		world.update_actor_cell(player, player_cell)
		if spr:
			spr.play("idle_" + facing)


func _try_interact() -> void:
	# nearest device or door within two cells
	var best := ""
	var best_d := 99
	var best_cell := Vector2i.ZERO
	for c in blocks:
		var d: int = absi(c.x - player_cell.x) + absi(c.y - player_cell.y)
		if d < best_d:
			best_d = d
			best = str(blocks[c])
			best_cell = c
	if best != "" and best_d <= 2:
		device_used.emit(best)
		hud.show_toast("USED " + best.to_upper().replace("_", " "))
		return
	for d in level.get("doors", []):
		var dc: Array = d.get("cell", [0, 0])
		var c := Vector2i(int(dc[0]), int(dc[1]))
		if absi(c.x - player_cell.x) + absi(c.y - player_cell.y) <= 2:
			door_used.emit(str(d.get("target", "")))
			hud.show_toast("ENTERING " + str(d.get("prompt", "")).to_upper())
			return
	hud.show_toast("NOTHING WITHIN REACH")


func _try_attack() -> void:
	if _fire_cd > 0.0:
		return
	_fire_cd = 0.35
	var aim: Vector2 = _aim_vector()
	var spr: ActorSprite = player.get_meta("sprite", null)
	if spr:
		spr.play("attack_" + facing, true)
	bullets.append({"pos": player.position + Vector2(0, -18), "dir": aim,
		"ttl": 0.55, "damage": 18.0})


func _aim_vector() -> Vector2:
	# aim in grid space, then project so a shot down a diagonal looks right
	match facing:
		"e":
			return Vector2(1, 0.5).normalized()
		"w":
			return Vector2(-1, -0.5).normalized()
		"n":
			return Vector2(0, -1)
		_:
			return Vector2(0, 1)


func _tick_bullets(delta: float) -> void:
	var keep: Array = []
	for b in bullets:
		b["ttl"] = float(b["ttl"]) - delta
		b["pos"] = b["pos"] + b["dir"] * 420.0 * delta
		if float(b["ttl"]) <= 0.0:
			continue
		var hit := false
		for e in enemies:
			var ai = e["ai"]
			if ai.is_dead():
				continue
			if (ai.pos as Vector2).distance_to(b["pos"]) < 26.0:
				var res: Dictionary = ai.take_damage(float(b["damage"]))
				hit = true
				if bool(res["dead"]):
					kills += 1
					enemy_killed.emit(str(e["id"]))
					hud.show_toast("TARGET DOWN")
					var node: Node2D = e["node"]
					if is_instance_valid(node):
						node.visible = false
				break
		if not hit:
			keep.append(b)
	bullets = keep


func _tick_enemies(delta: float) -> void:
	for e in enemies:
		var ai = e["ai"]
		if ai.is_dead():
			continue
		var to_player: Vector2 = world.cell_center(player_cell) - ai.pos
		var sees := to_player.length() < 420.0
		ai.tick(delta, world.cell_center(player_cell), sees)
		var node: Node2D = e["node"]
		if is_instance_valid(node):
			node.position = ai.pos
			var cell: Vector2i = IsoGridScript.pick(ai.pos)
			node.set_meta("cell", cell)


# ---- state for tests and the playtest harness ------------------------------------

func get_state() -> Dictionary:
	var alive := 0
	var list: Array = []
	for e in enemies:
		var ai = e["ai"]
		if not ai.is_dead():
			alive += 1
		list.append({"id": e["id"], "hp": ai.hp, "dead": ai.is_dead()})
	return {
		"area": district_id,
		"player": {"cell": [player_cell.x, player_cell.y], "facing": facing,
			"hp": hp, "hp_max": hp_max},
		"enemies": {"alive": alive, "list": list, "kills": kills},
		"secrets": level.get("secrets", []).size(),
		"doors": level.get("doors", []).size(),
		"devices": blocks.size(),
		"cred": cred, "ram": ram,
	}
