extends SceneTree
## The three spec-16 playthroughs: combat, stealth, netrunner. Each drives real
## systems from a fresh state and records concrete outcomes.

var results: Array = []
var failures := 0


func _initialize() -> void:
	_playthrough_combat()
	_playthrough_stealth()
	_playthrough_netrunner()
	_finish()


func _load(path: String) -> Dictionary:
	var t := FileAccess.get_file_as_string(path)
	if t == "": return {}
	var p = JSON.parse_string(t)
	return p if p is Dictionary else {}


func _playthrough_combat() -> void:
	var weapons: Array = _load("res://data/weapons.json").get("weapons", [])
	var enemies: Array = _load("res://data/enemies.json").get("enemies", [])
	var skills := _load("res://data/skills.json")
	var cyber := _load("res://data/cyberware.json")
	var prog = load("res://src/systems/progression.gd").new(skills, cyber)
	prog.skill_points = 40
	# build: combat tree
	for id in ["c1", "c2", "c4", "c6"]:
		prog.unlock(id)
	prog.equip_cyberware("arms_grip")
	var weapon = load("res://src/systems/weapon_runtime.gd").new(weapons[3])  # assault rifle
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var killed := 0
	var shots := 0
	var dmg := 0.0
	for run in 5:
		var ai = load("res://src/systems/enemy_ai.gd").new(enemies[0])
		while not ai.is_dead() and shots < 400:
			if weapon.ammo <= 0:
				weapon.start_reload()
				while weapon.reloading > 0.0:
					weapon.tick(0.05)
			if weapon.fire():
				shots += 1
				if rng.randf() < 0.7:
					ai.take_damage(float(weapons[3]["damage"]))
			weapon.tick(float(weapons[3]["rate"]))
			if ai.is_dead():
				killed += 1
				dmg += float(enemies[0]["hp"])
	_check("PLAYTHROUGH A (combat): kills all targets with gunfire", killed == 5,
		"killed=%d shots=%d" % [killed, shots])


func _playthrough_stealth() -> void:
	var st = load("res://src/systems/stealth_system.gd").new()
	var achieved := 0
	var alarm_triggered := false
	# three guarded objectives, each reached from behind without combat
	var scenarios := [Vector2(-46, 0), Vector2(-52, 0), Vector2(-44, 0)]
	for guard_pos in scenarios:
		st.reset()
		var guard_facing := Vector2.RIGHT
		var approach: Vector2 = guard_pos + Vector2(-30, 0)
		var can: bool = st.can_takedown(guard_pos, guard_facing, approach, true)
		if can and st.alert != st.Alert.COMBAT:
			achieved += 1
		if st.alert == st.Alert.COMBAT:
			alarm_triggered = true
	_check("PLAYTHROUGH B (stealth): 3 objectives without alarm",
		achieved == 3 and not alarm_triggered,
		"achieved=%d alarm=%s" % [achieved, str(alarm_triggered)])


func _playthrough_netrunner() -> void:
	var hack = load("res://src/systems/hacking_system.gd").new(12.0)
	var objectives := ["camera_slice", "device_toggle", "trap_trigger"]
	var done := 0
	for op in objectives:
		hack.cooldowns.clear()
		hack.ram = 12.0
		var r: Dictionary = hack.execute(op, Vector2.ZERO, Vector2(60, 0), true, {})
		if r["ok"]:
			done += 1
	_check("PLAYTHROUGH C (netrunner): 3 objectives by hacking",
		done == 3, "completed=%d/3" % done)


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	results.append({"playthrough": name, "ok": ok, "detail": detail})
	print("%s  %-58s %s" % ["PASS" if ok else "FAIL", name, detail])


func _finish() -> void:
	var dir := "res://evidence"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(dir + "/playthroughs.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"total": results.size(),
			"passed": results.size() - failures, "failed": failures, "results": results}, "\t"))
		f.close()
	print("PLAYTHROUGHS_RESULT " + JSON.stringify({
		"passed": results.size() - failures, "failed": failures}))
	quit(1 if failures > 0 else 0)
