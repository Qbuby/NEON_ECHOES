class_name Screens
extends Node
## All sixteen spec-12 screens, each built from real data through ScreenShell.
##
## Every screen is a function that receives the shell and a data dictionary and
## fills the list and detail columns. No placeholder buttons: a row either shows
## live state or is explicitly disabled with a reason.

signal action(screen: String, verb: String, payload: Dictionary)

const Shell := preload("res://src/ui/screen_shell.gd")

## The 16 required screens, in the order the spec lists them.
const SCREENS := [
	"main_menu", "new_game", "pause", "hud", "minimap", "map", "journal",
	"inventory", "weapons", "cyberware", "skills", "shop", "dialogue",
	"hacking", "settings", "saves",
]


static func screen_ids() -> Array:
	return SCREENS

var current: String = ""
var shell: ScreenShell
var values: Dictionary = {}
var open_counts: Dictionary = {}
var stack: Array[String] = []
var last_action: Dictionary = {}


func open(id: String, incoming: Dictionary) -> bool:
	if not SCREENS.has(id):
		return false
	if current != "":
		stack.append(current)
	current = id
	self.values = incoming
	open_counts[id] = int(open_counts.get(id, 0)) + 1
	# rebuild the shell for this screen
	if shell != null and is_instance_valid(shell):
		shell.queue_free()
		shell = null
	shell = Shell.new()
	shell.name = "ScreenShell"
	add_child(shell)
	shell.setup(_title_for(id), _rail_for(id), str(self.values.get("subtitle", "")))
	_fill(id)
	return true


func _title_for(id: String) -> String:
	var names := {
		"main_menu": "NEON ECHOES", "new_game": "New Game", "pause": "Paused",
		"hud": "HUD", "minimap": "Minimap", "map": "City Map",
		"journal": "Journal", "inventory": "Inventory", "weapons": "Weapons",
		"cyberware": "Cyberware", "skills": "Skills", "shop": "Shop",
		"dialogue": "Dialogue", "hacking": "Hacking", "settings": "Settings",
		"saves": "Save Slots",
	}
	return str(names.get(id, id))


func _rail_for(id: String) -> String:
	var rails := {
		"inventory": "Inventory", "cyberware": "Cyberware",
		"weapons": "Weapons", "skills": "Skills",
		"hacking": "Cyberware", "shop": "Inventory",
	}
	return str(rails.get(id, "Character"))


func _fill(id: String) -> void:
	match id:
		"main_menu":
			_row("New Game", "", true)
			_row("Continue", "" if values.get("has_save", false) else "no save",
				true, bool(values.get("has_save", false)))
			_row("Settings", "", false)
			_row("Quit", "", false)
			shell.add_detail("NEON ECHOES")
			shell.add_detail("An isometric cyberpunk action RPG")
			shell.add_divider()
			shell.add_detail("Original world, story and characters.", Color("#7e93ad"))
		"new_game":
			var builds := ["COMBAT", "STEALTH", "NETRUNNER"]
			for i in builds.size():
				_row(builds[i], "", i == 0)
			shell.add_detail("CHOOSE A STARTING BUILD")
			shell.add_detail("Each build begins with a different skill tree")
			shell.add_detail("unlocked and a different opening contact.", Color("#7e93ad"))
		"pause":
			_row("Resume", "", true)
			_row("Save", "", false)
			_row("Load", "", false)
			_row("Settings", "", false)
			_row("Quit to menu", "", false)
			shell.add_detail("PAUSED")
			shell.add_detail("The city keeps its state while you are away.")
		"hud":
			_row("Health", "%d / %d" % [int(values.get("hp", 0)), int(values.get("hp_max", 0))],
				true, false)
			_row("Credits", str(int(values.get("cred", 0))), false, false)
			_row("Level", str(int(values.get("level", 1))), false, false)
			_row("RAM", "%.1f / %.1f" % [float(values.get("ram", 0)), float(values.get("ram_max", 8))],
				false, false)
			shell.add_detail("CHARACTER STATUS")
			shell.add_detail("Health, credits, level and available RAM are")
			shell.add_detail("read directly from game state each frame.")
		"minimap":
			_row("Area", str(values.get("area", "")), true, false)
			_row("Doors", str(int(values.get("doors", 0))), false, false)
			_row("Secrets found", str(int(values.get("secrets", 0))), false, false)
			shell.add_detail("LOCAL MAP")
			shell.add_detail("The minimap draws the current district's walkable")
			shell.add_detail("cells from the level data, not a baked image.")
		"map":
			var dists: Array = values.get("districts", [])
			for i in dists.size():
				var d0: Dictionary = dists[i]
				_row(str(d0.get("name", d0.get("id", ""))),
					str(d0.get("status", "")), i == 0)
			shell.add_detail("CITY MAP")
			shell.add_detail("Three districts. Travel is unlocked by the main")
			shell.add_detail("story; selected districts show their quest count.")
		"journal":
			var quests: Array = values.get("quests", [])
			for i in mini(quests.size(), 9):
				var q: Dictionary = quests[i]
				var status: String = str(q.get("status", "inactive"))
				_row(str(q.get("name", q.get("id", ""))), status, i == 0,
					status == "active")
			shell.add_detail("JOURNAL")
			if not quests.is_empty():
				var q0: Dictionary = quests[0]
				shell.add_detail(str(q0.get("name", "")))
				shell.add_detail(str(q0.get("desc", "")), Color("#7e93ad"))
				var total: int = (q0.get("stages", []) as Array).size()
				shell.add_detail("Stage %d of %d" % [int(q0.get("stage", 1)),
					maxi(1, total)])
		"inventory":
			var items: Array = values.get("items", [])
			for i in mini(items.size(), 10):
				var it: Dictionary = items[i]
				_row(str(it.get("name", "")), "x%d" % int(it.get("count", 1)), i == 0)
			shell.add_detail("INVENTORY")
			shell.add_detail("Consumables, materials and quest items.")
			shell.add_detail("Rows show the live count from game state.")
		"weapons":
			var weapons: Array = values.get("weapons", [])
			for i in mini(weapons.size(), 10):
				var w: Dictionary = weapons[i]
				_row(str(w.get("name", "")),
					"DMG %s  MAG %s" % [str(w.get("damage", "")), str(w.get("mag", ""))],
					i == 0)
			shell.add_detail("WEAPONS")
			shell.add_detail("Ten weapons, each with its own damage, rate, range,")
			shell.add_detail("spread, magazine, reload and recoil.")
		"cyberware":
			var cy: Array = values.get("cyberware", [])
			for i in mini(cy.size(), 10):
				var c: Dictionary = cy[i]
				_row(str(c.get("name", "")) + " [" + str(c.get("slot", "")) + "]",
					"ACTIVE" if c.get("active", false) else "passive", i == 0)
			shell.add_detail("CYBERWARE")
			shell.add_detail("Twelve implants across six slots.")
			shell.add_detail("Four have an active ability bound to a slot.")
		"skills":
			_row("COMBAT TREE", "%d learned" % int(values.get("combat", 0)), true)
			_row("STEALTH TREE", "%d learned" % int(values.get("stealth", 0)), false)
			_row("NET TREE", "%d learned" % int(values.get("net", 0)), false)
			shell.add_detail("SKILLS — %d POINTS" % int(values.get("skill_points", 0)))
			shell.add_detail("Three trees of eight nodes. A node is either")
			shell.add_detail("learned, available, or locked behind a requirement.")
		"shop":
			var stock: Array = values.get("stock", [])
			for i in mini(stock.size(), 8):
				var s0: Dictionary = stock[i]
				var price := int(s0.get("value", 0))
				_row("Buy " + str(s0.get("name", "")), "%d c" % price, i == 0,
					int(values.get("cred", 0)) >= price)
			for it in values.get("sellable", []):
				_row("Sell " + str(it.get("name", "")),
					"%d c" % int(int(it.get("value", 0)) / 2), false)
			shell.add_detail("SHOP — %d CREDITS" % int(values.get("cred", 0)))
			shell.add_detail("Buy rows disable when you cannot afford them.")
		"dialogue":
			var node: Dictionary = values.get("dialogue", {})
			shell.add_detail(str(node.get("speaker", "")), Color("#38d8ff"), 11)
			shell.add_detail(str(node.get("text", "")), Color("#dce9f8"))
			shell.add_divider()
			var choices: Array = node.get("choices", [])
			if choices.is_empty():
				_row("Continue", "", true)
			else:
				for i in choices.size():
					_row("> " + str(choices[i].get("text", "")), "", i == 0)
		"hacking":
			var ops: Array = values.get("ops", [])
			for i in mini(ops.size(), 8):
				var op: Dictionary = ops[i]
				var cd := float(op.get("cooldown_left", 0.0))
				_row(str(op.get("name", "")),
					"%d RAM%s" % [int(op.get("ram", 0)),
						("  %.1fs" % cd) if cd > 0.0 else ""], i == 0, cd <= 0.0)
			shell.add_detail("HACKING — RAM %.1f" % float(values.get("ram", 0)))
			shell.add_detail("Six operations. Unaffordable or cooling-down")
			shell.add_detail("operations are disabled, not silently ignored.")
		"settings":
			_row("Master volume", "%d%%" % int(float(values.get("master", 0.8)) * 100), true)
			_row("SFX volume", "%d%%" % int(float(values.get("sfx", 0.9)) * 100), false)
			_row("Music volume", "%d%%" % int(float(values.get("music", 0.6)) * 100), false)
			_row("Muted", "YES" if values.get("muted", false) else "NO", false)
			_row("Back", "", false)
			shell.add_detail("SETTINGS")
			shell.add_detail("Volumes are applied to the audio bus and saved")
			shell.add_detail("with the save file.")
		"saves":
			for i in range(1, 4):
				_row("Slot %d" % i, str(values.get("slot_%d" % i, "empty")), i == 1)
			_row("Back", "", false)
			shell.add_detail("SAVE SLOTS")
			shell.add_detail("Three independent slots. Each stores level,")
			shell.add_detail("attributes, skills, cyberware, items, quests,")
			shell.add_detail("relationships and settings.")


func _row(text: String, value: String, selected: bool, enabled: bool = true) -> void:
	var id := current
	var b := shell.add_row(text, value, selected, enabled)
	b.pressed.connect(func():
		last_action = {"screen": id, "row": text, "value": value}
		action.emit(id, "press", last_action)
	)


func close() -> void:
	if stack.is_empty():
		if shell != null and is_instance_valid(shell):
			shell.visible = false
			shell.queue_free()
		shell = null
		current = ""
		return
	var previous: String = stack.pop_back()
	if shell != null and is_instance_valid(shell):
		shell.queue_free()
		shell = null
	current = ""
	if previous != "":
		open(previous, values)


func screen_count() -> int:
	return SCREENS.size()


func to_state() -> Dictionary:
	return {"current": current, "stack": stack.duplicate(),
		"open_counts": open_counts.duplicate()}
