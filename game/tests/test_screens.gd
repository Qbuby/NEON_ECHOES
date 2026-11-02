extends SceneTree
## Open all sixteen screens, verify each builds rows from real data, and save a
## screenshot of the two most representative ones.
##
##   godot --headless -s res://tests/test_screens.gd      (structure only)
##   godot -s res://tests/test_screens.gd                 (also screenshots)

var passed := 0
var failed := 0
var ScreensScript := preload("res://src/ui/screens.gd")


func _initialize() -> void:
	var holder := Node.new()
	root.add_child(holder)
	var screens = ScreensScript.new()
	holder.add_child(screens)

	# the data every screen reads; in the game this comes from GameState
	var game := {
		"hp": 74, "hp_max": 100, "cred": 1050, "level": 12, "ram": 5.5, "ram_max": 8.0,
		"has_save": true, "area": "CORP CORE", "doors": 4, "secrets": 2,
		"districts": [
			{"id": "corp_core", "name": "企业核心区  VANTAGE", "status": "unlocked"},
			{"id": "ind_belt", "name": "工业贫民区  KILNS", "status": "locked"},
			{"id": "night_row", "name": "娱乐地下区  NEON ROW", "status": "locked"},
		],
		"quests": [
			{"id": "q1", "name": "Ghost in the Vault", "status": "active",
			 "desc": "Find who emptied the Spire vault.", "stage": 2, "stages": 3},
			{"id": "q2", "name": "Cold Storage", "status": "active",
			 "desc": "Recover the curators ledger.", "stage": 1, "stages": 3},
			{"id": "q3", "name": "Neon Debt", "status": "inactive",
			 "desc": "A fixer wants a favour.", "stage": 0, "stages": 2},
		],
		"items": [
			{"id": "stim", "name": "Stim Pack", "count": 4},
			{"id": "chip", "name": "Data Chip", "count": 2},
			{"id": "key", "name": "Vault Key", "count": 1},
		],
		"weapons": [
			{"id": "w1", "name": "Mono Katana", "damage": 34, "mag": 0},
			{"id": "w2", "name": "Arasaka Sidearm", "damage": 12, "mag": 12},
			{"id": "w3", "name": "Street Sweeper", "damage": 8, "mag": 24},
		],
		"cyberware": [
			{"id": "c1", "name": "Optic Zoom", "slot": "eyes", "active": true},
			{"id": "c2", "name": "Subdermal Weave", "slot": "skin", "active": false},
		],
		"combat": 4, "stealth": 2, "net": 3, "skill_points": 5,
		"stock": [
			{"id": "s1", "name": "Stim Pack", "value": 40},
			{"id": "s2", "name": "Ammo Box", "value": 120},
			{"id": "s3", "name": "Cyberdeck Mk2", "value": 4000},
		],
		"sellable": [{"id": "x1", "name": "Scrap Coil", "value": 30}],
		"dialogue": {"speaker": "CURATOR VOSS",
			"text": "You came for the ledger. Everyone does. Nobody leaves with it.",
			"choices": [
				{"id": "a", "text": "I am not here for the ledger."},
				{"id": "b", "text": "Then I will take it from you."},
				{"id": "c", "text": "[NETRUN] Your vault already opened."},
			]},
		"ops": [
			{"id": "camera_slice", "name": "Camera Slice", "ram": 2, "cooldown_left": 0.0},
			{"id": "device_toggle", "name": "Device Toggle", "ram": 1, "cooldown_left": 3.2},
			{"id": "optics_glitch", "name": "Optics Glitch", "ram": 3, "cooldown_left": 0.0},
		],
		"master": 0.8, "sfx": 0.9, "music": 0.6, "muted": false,
		"slot_1": "LV 12 · CORP CORE · 4h12m", "slot_2": "empty", "slot_3": "empty",
	}

	# --- every screen opens and builds rows
	for id in screens.screen_ids():
		var ok: bool = screens.open(id, game)
		var rows: int = screens.shell.row_count() if screens.shell != null else 0
		_check(ok and rows > 0, "%s opens with %d rows" % [id, rows])

	# --- close/back returns to the previous screen, then hides.
	# reset first: the 16 opens above each pushed onto the stack
	screens.stack.clear()
	screens.current = ""
	screens.open("inventory", game)
	screens.open("weapons", game)
	_check(screens.current == "weapons", "opening a second screen stacks it")
	screens.close()
	_check(screens.current == "inventory", "closing returns to the previous screen")
	screens.close()
	_check(screens.current == "" and (screens.shell == null or not is_instance_valid(screens.shell)),
		"closing the root clears the shell")

	# --- a disabled row must refuse
	screens.open("shop", game)
	game["cred"] = 10
	screens.open("shop", game)
	var disabled_clicked: bool = false
	for i in screens.shell.row_count():
		var b = screens.shell.list_box.get_child(i)
		if b is Button and b.disabled:
			disabled_clicked = screens.shell.click_row(i)
			break
	_check(not disabled_clicked, "a disabled (unaffordable) row refuses the click")

	# --- screenshots of the two richest screens
	if DisplayServer.get_name() != "headless":
		for id in ["inventory", "dialogue", "hacking"]:
			screens.open(id, game)
			await create_timer(0.25).timeout
			var img := root.get_viewport().get_texture().get_image()
			img.save_png("res://evidence/screen_%s.png" % id)
			print("SHOT screen_", id)

	_finish()


func _check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("PASS  ", label)
	else:
		failed += 1
		print("FAIL  ", label)


func _finish() -> void:
	print("SCREENS_RESULT {\"passed\":%d,\"failed\":%d}" % [passed, failed])
	quit(1 if failed > 0 else 0)
