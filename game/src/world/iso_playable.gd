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
const ScreensScript := preload("res://src/ui/screens.gd")

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
var screens: Node
var secrets_taken: Array = []
var quests: Array = []
var _weapon_index := 0
var weapons: Array = []


func _ready() -> void:
	# Juice hosts effects on the level, so the level must be findable by group.
	# Without this every burst instantiated a node and leaked it.
	add_to_group("level")
	setup(district_id)


func setup(id: String) -> bool:
	if world != null:
		# already built (either by _ready or an earlier call); switching district
		# needs an explicit reload, not a silent rebuild on top of the old one
		if id == district_id:
			return true
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
	_make_screens()
	_load_content()
	_play_music(_music_for(id))
	_log("iso.ready", {"district": id, "enemies": enemies.size(),
		"walkable": walkable.size()})
	return true


## Juice is optional too: the scene works headless, where there is no viewport.
func _juice(method: String, a = null, b = null, c = null, d = null) -> void:
	var tree := get_tree()
	var j = tree.root.get_node_or_null("Juice") if tree != null else null
	if j == null:
		return
	if d != null:
		j.call(method, a, b, c, d)
	elif c != null:
		j.call(method, a, b, c)
	elif b != null:
		j.call(method, a, b)
	elif a != null:
		j.call(method, a)
	else:
		j.call(method)


## Audio is feedback, not a dependency: a missing file logs once, never throws.
func _sfx(name: String) -> void:
	var tree := get_tree()
	var a = tree.root.get_node_or_null("AudioManager") if tree != null else null
	if a != null:
		a.play_sfx(name)


func _play_music(track: String) -> void:
	var tree := get_tree()
	var a = tree.root.get_node_or_null("AudioManager") if tree != null else null
	if a != null:
		a.play_music(track)


func _music_for(id: String) -> String:
	if id.begins_with("night_row"):
		return "mus_combat"
	if id.begins_with("ind_belt"):
		return "mus_calm"
	return "mus_menu"


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
	# shadows take the district's colour rather than neutral black
	var tint := Color(0.04, 0.06, 0.11, 0.46)
	if district_id.begins_with("ind_belt"):
		tint = Color(0.10, 0.06, 0.03, 0.46)
	elif district_id.begins_with("night_row"):
		tint = Color(0.08, 0.04, 0.13, 0.46)
	world.set_shadow_tint(tint)
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
			"radius": 130.0 if id == "prop_lamp" else 96.0,
			"color": palette[id], "strength": 0.34 if id == "prop_lamp" else 0.26})
	# a wide low-strength wash so no part of the floor is the same value as any
	# other: the concept floors always have a light gradient across them
	for gy in range(6, int(level.get("h", 80)) - 6, 18):
		for gx in range(6, int(level.get("w", 80)) - 6, 22):
			var tint := Color("#1b3a66") if district_id.begins_with("corp_core") else (
				Color("#4a2c10") if district_id.begins_with("ind_belt") else Color("#401a52"))
			defs.append({"pos": world.cell_center(Vector2i(gx, gy)),
				"radius": 190.0, "color": tint, "strength": 0.10})
	var lighting: Node2D = IsoLightingScript.new()
	lighting.name = "Lighting"
	# the world sorts by child order; a light must sit above floors and props but
	# under actors, so add it to the world and let it draw after the prop pass
	world.add_child(lighting)
	lighting.setup(defs)
	# IsoWorld's sort re-appends its sprites after any node added later, so child
	# order alone cannot keep the light on top. Every managed sprite sits at
	# z_index 0, so a positive z here paints the pools last.
	lighting.z_index = 3800


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
	camera.zoom = Vector2(1.7, 1.7)
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
	if hud != null and is_instance_valid(hud):
		hud.queue_free()
		hud = null
	hud = IsoHudScript.new()
	add_child(hud)
	hud.set_values({
		"hp": hp, "hp_max": hp_max, "ram": ram, "ram_max": ram_max,
		"cred": cred, "name": "RIN", "status": 3,
		"objective": str(level.get("name", district_id)).to_upper(),
	})


## The 16 screens share one instance; open() rebuilds the shell for each.
func _make_screens() -> void:
	if screens != null and is_instance_valid(screens):
		screens.queue_free()
		screens = null
	screens = ScreensScript.new()
	screens.name = "Screens"
	add_child(screens)
	_prewarm_screens(screens)
	_prewarm_feedback()


## First use of a resource is what stalls a frame: the impact effect scene and
## its texture, and the first WAV of each sound. Load them during setup.
func _prewarm_feedback() -> void:
	var fx := "res://src/fx/impact.tscn"
	if ResourceLoader.exists(fx):
		var packed := load(fx)
		if packed is PackedScene:
			var probe = packed.instantiate()
			if probe != null:
				add_child(probe)
				# let it register its texture then drop it
				probe.queue_free()
	var tree := get_tree()
	var am = tree.root.get_node_or_null("AudioManager") if tree != null else null
	if am != null and am.has_method("preload_sounds"):
		am.preload_sounds(["gun_pistol", "melee_slash", "melee_hit", "int_door",
			"int_secret", "int_terminal", "ui_open", "mus_menu",
			"mus_combat", "mus_calm"])


## Building a screen's Control tree costs ~100 ms the first time. Do it during
## load, once, so opening the inventory mid-fight never stalls the frame.
func _prewarm_screens(target) -> void:
	var data := screen_data()
	for id in target.screen_ids():
		target.open(id, data)
	target.close()


## Advance the active quest stage for a given objective kind. Keeps the journal
## honest: a stage only moves when the matching action happened.
func advance_quest(kind: String, amount: int = 1) -> void:
	for q in quests:
		if str(q.get("status", "")) != "active":
			continue
		if str(q.get("objective", "")) != kind:
			continue
		q["progress"] = int(q.get("progress", 0)) + amount
		var need := int(q.get("need", 3))
		if int(q["progress"]) >= need:
			q["stage"] = int(q.get("stage", 1)) + 1
			q["progress"] = 0
			if int(q["stage"]) > int(q.get("stages", 3)):
				q["status"] = "complete"
				hud.show_toast("QUEST COMPLETE")
			else:
				hud.show_toast("OBJECTIVE COMPLETE")
		return


func _load_content() -> void:
	if not quests.is_empty() or not weapons.is_empty():
		# already loaded; content does not change when the player walks through a
		# door, so re-parsing and re-appending here was both wasteful and wrong
		return
	var w = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons.json"))
	weapons = w.get("weapons", []) if w is Dictionary else []
	var q = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests.json"))
	if q is Dictionary:
		for quest in q.get("main", []) + q.get("side", []):
			quest["status"] = "active" if quests.size() < 3 else "inactive"
			quests.append(quest)


## Everything the screens read. Built from live state each time a screen opens,
## so a screen never shows a stale number.
func screen_data() -> Dictionary:
	var items: Array = []
	for i in weapons.size():
		var w: Dictionary = weapons[i]
		items.append({"id": w.get("id", ""), "name": w.get("name", ""),
			"count": 1, "kind": "weapon"})
	for k in secrets_taken.size():
		items.append({"id": "secret_%d" % k, "name": "Data Cache", "count": 1,
			"kind": "quest"})
	return {
		"hp": int(hp), "hp_max": int(hp_max), "cred": cred, "level": 12,
		"ram": ram, "ram_max": ram_max, "has_save": true,
		"area": str(level.get("name", district_id)), "doors": level.get("doors", []).size(),
		"secrets": secrets_taken.size(), "weapons": weapons, "items": items,
		"quests": quests,
		"districts": [
			{"id": "corp_core", "name": "企业核心区  VANTAGE", "status": "unlocked"},
			{"id": "ind_belt", "name": "工业贫民区  KILNS", "status": "unlocked"},
			{"id": "night_row", "name": "娱乐地下区  NEON ROW", "status": "unlocked"},
		],
		"cyberware": [
			{"id": "optic_zoom", "name": "Optic Zoom", "slot": "eyes", "active": true},
			{"id": "subdermal", "name": "Subdermal Weave", "slot": "skin", "active": false},
			{"id": "leg_servo", "name": "Leg Servos", "slot": "legs", "active": true},
		],
		"combat": 4, "stealth": 2, "net": 3, "skill_points": 5,
		"stock": [
			{"id": "stim", "name": "Stim Pack", "value": 40},
			{"id": "ammo", "name": "Ammo Box", "value": 120},
			{"id": "deck", "name": "Cyberdeck Mk2", "value": 4000},
		],
		"sellable": [{"id": "scrap", "name": "Scrap Coil", "value": 30}],
		"dialogue": {"speaker": "CURATOR VOSS",
			"text": "You came for the ledger. Everyone does. Nobody leaves with it.",
			"choices": [
				{"id": "a", "text": "I am not here for the ledger."},
				{"id": "b", "text": "Then I will take it from you."},
				{"id": "c", "text": "[NETRUN] Your vault already opened."},
			]},
		"ops": [
			{"id": "camera_slice", "name": "Camera Slice", "ram": 2, "cooldown_left": 0.0},
			{"id": "device_toggle", "name": "Device Toggle", "ram": 1, "cooldown_left": 0.0},
			{"id": "optics_glitch", "name": "Optics Glitch", "ram": 3, "cooldown_left": 0.0},
		],
		"master": 0.8, "sfx": 0.9, "music": 0.6, "muted": false,
		"slot_1": "LV 12 · %s" % str(level.get("name", "")), "slot_2": "empty",
		"slot_3": "empty",
	}


func set_paused(paused: bool) -> void:
	# pausing the world while a screen is up keeps enemies from acting behind it
	set_process(not paused)


# ---- input and movement ----------------------------------------------------------

func _process(delta: float) -> void:
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_handle_input()
	_move_player(delta)
	_check_secrets()
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
	if Input.is_action_just_pressed("pause"):
		_toggle_screen("pause")
	if Input.is_action_just_pressed("inventory"):
		_toggle_screen("inventory")
	if Input.is_action_just_pressed("map"):
		_toggle_screen("map")


func _toggle_screen(id: String) -> void:
	if screens == null:
		return
	if screens.current != "":
		screens.close()
		set_paused(false)
	else:
		_sfx("ui_open")
		screens.open(id, screen_data())
		set_paused(true)


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
		_sfx("int_terminal")
		advance_quest("hack")
		hud.show_toast("USED " + best.to_upper().replace("_", " "))
		return
	for d in level.get("doors", []):
		var dc: Array = d.get("cell", [0, 0])
		var c := Vector2i(int(dc[0]), int(dc[1]))
		if absi(c.x - player_cell.x) + absi(c.y - player_cell.y) <= 2:
			var target := str(d.get("target", ""))
			door_used.emit(target)
			_sfx("int_door")
			advance_quest("reach")
			hud.show_toast("ENTERING " + str(d.get("prompt", "")).to_upper())
			_enter(target)
			return
	hud.show_toast("NOTHING WITHIN REACH")


## Walk through a door: tear down the current world and build the target area.
func _enter(target: String) -> void:
	if target == "" or target == district_id:
		return
	if not FileAccess.file_exists("res://data/districts/%s.iso.json" % target):
		hud.show_toast("DOOR SEALED")
		return
	# clear the built scene
	if world != null and is_instance_valid(world):
		world.queue_free()
		world = null
	enemies.clear()
	bullets.clear()
	walkable.clear()
	blocks.clear()
	secrets_taken.clear()
	if screens != null and screens.current != "":
		screens.close()
		set_paused(false)
	if setup(target):
		area_changed.emit(target)


## Secrets are collected by walking onto their cell.
func _check_secrets() -> void:
	for s2 in level.get("secrets", []):
		var sc: Array = s2.get("cell", [0, 0])
		var cell := Vector2i(int(sc[0]), int(sc[1]))
		var sid := str(s2.get("id", ""))
		if cell == player_cell and not secrets_taken.has(sid):
			secrets_taken.append(sid)
			cred += 150
			_sfx("int_secret")
			advance_quest("explore")
			hud.show_toast("DATA CACHE  +150 c")
			hud.set_values({"hp": hp, "hp_max": hp_max, "ram": ram,
				"ram_max": ram_max, "cred": cred, "name": "RIN", "status": 3,
				"objective": str(level.get("name", district_id)).to_upper()})


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
	_sfx("gun_pistol")
	_juice("shake", 1.6, 0.06)
	_juice("burst", player.position + aim * 22.0, "res://src/fx/impact.tscn", 0.0, 0.9)


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
				_sfx("melee_slash")
				# the feedback that makes a hit land: freeze, shake, burst,
				# number, and flash the struck body
				_juice("hit_stop", 0.045)
				_juice("shake", 2.6, 0.12)
				_juice("burst", ai.pos, "res://src/fx/impact.tscn", 0.0, 1.4)
				_juice("number", ai.pos + Vector2(0, -20), int(res["applied"]))
				var hit_node: Node2D = e["node"]
				if is_instance_valid(hit_node):
					_juice("flash", hit_node)
				if bool(res["dead"]):
					kills += 1
					_sfx("melee_hit")
					_juice("shake", 4.0, 0.18)
					_juice("burst", ai.pos, "res://src/fx/impact.tscn", 0.0, 2.2)
					advance_quest("kill")
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
		# keep the body inside the district and off solid cells: the AI has no
		# map of its own and will otherwise walk out of the world
		var cell: Vector2i = IsoGridScript.pick(ai.pos)
		if not bool(walkable.get(cell, false)) or blocks.has(cell):
			var back: Vector2i = e.get("cell", cell)
			ai.pos = world.cell_center(back)
			cell = back
		else:
			e["cell"] = cell
		var node: Node2D = e["node"]
		if is_instance_valid(node):
			node.position = ai.pos
			node.set_meta("cell", cell)


## The grid cell an actor currently stands on.
func _cell_of_actor(node: Node2D) -> Vector2i:
	if node == null or not is_instance_valid(node):
		return player_cell
	if node.has_meta("cell"):
		return node.get_meta("cell")
	return IsoGridScript.pick(node.position)


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
		"secrets": level.get("secrets", []).size() - secrets_taken.size(),
		"secrets_found": secrets_taken.duplicate(),
		"doors": level.get("doors", []).size(),
		"devices": blocks.size(),
		"cred": cred, "ram": ram,
		"quests": quests.size(),
	}
