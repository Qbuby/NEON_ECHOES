extends Node
## Global run state: health, inventory, story flags, current area, save/load.
##
## Rules of thumb:
##  - Gameplay nodes own their own local state; this autoload only holds what
##    must survive an area change or a save.
##  - Anything the playtest harness or the agent needs to observe should be
##    exposed through snapshot().

signal item_added(item_id: String, count: int)
signal item_removed(item_id: String, count: int)
signal flag_changed(flag: String, value: Variant)
signal hp_changed(current: int, maximum: int)
signal game_over(victory: bool)

const SAVE_PATH := "user://save.json"

var max_hp := 6
var hp := 6
var inventory: Dictionary = {}
var flags: Dictionary = {}
var current_area := ""
var checkpoint := ""
var play_time := 0.0
var kills := 0
var running := false

var _started_at := 0.0


func _process(delta: float) -> void:
	if running:
		play_time += delta


func reset() -> void:
	max_hp = 6
	hp = max_hp
	inventory.clear()
	flags.clear()
	current_area = ""
	checkpoint = ""
	play_time = 0.0
	kills = 0
	running = true
	_started_at = Time.get_ticks_msec()
	hp_changed.emit(hp, max_hp)
	Log.info("state.reset", {"max_hp": max_hp})


func set_hp(value: int) -> void:
	hp = clampi(value, 0, max_hp)
	hp_changed.emit(hp, max_hp)
	if hp <= 0:
		Log.info("state.player_died", {})
		game_over.emit(false)


func damage_player(amount: int) -> void:
	if not running or hp <= 0:
		return
	set_hp(hp - amount)
	Log.info("state.player_hurt", {"amount": amount, "hp": hp})


func heal_player(amount: int) -> void:
	set_hp(hp + amount)
	Log.info("state.player_heal", {"amount": amount, "hp": hp})


func add_item(item_id: String, count: int = 1) -> void:
	inventory[item_id] = int(inventory.get(item_id, 0)) + count
	item_added.emit(item_id, count)
	Log.info("state.item_added", {"item": item_id, "count": count, "total": inventory[item_id]})


func remove_item(item_id: String, count: int = 1) -> bool:
	var have := int(inventory.get(item_id, 0))
	if have < count:
		return false
	inventory[item_id] = have - count
	if inventory[item_id] <= 0:
		inventory.erase(item_id)
	item_removed.emit(item_id, count)
	Log.info("state.item_removed", {"item": item_id, "count": count})
	return true


func item_count(item_id: String) -> int:
	return int(inventory.get(item_id, 0))


func set_flag(flag: String, value: Variant = true) -> void:
	flags[flag] = value
	flag_changed.emit(flag, value)
	Log.info("state.flag", {"flag": flag, "value": value})


func get_flag(flag: String, fallback: Variant = false) -> Variant:
	return flags.get(flag, fallback)


func finish(victory: bool) -> void:
	running = false
	Log.info("state.finish", {"victory": victory, "play_time": snapped(play_time, 0.01)})
	game_over.emit(victory)


## Everything an external observer (playtest harness, agent, debug overlay) needs.
func snapshot() -> Dictionary:
	return {
		"hp": hp,
		"max_hp": max_hp,
		"inventory": inventory.duplicate(true),
		"flags": flags.duplicate(true),
		"area": current_area,
		"play_time": snapped(play_time, 0.01),
		"kills": kills,
		"running": running,
	}


func to_dict() -> Dictionary:
	var data := snapshot()
	data["version"] = 1
	return data


func from_dict(data: Dictionary) -> void:
	max_hp = int(data.get("max_hp", 6))
	hp = int(data.get("hp", max_hp))
	inventory = (data.get("inventory", {}) as Dictionary).duplicate(true)
	flags = (data.get("flags", {}) as Dictionary).duplicate(true)
	current_area = String(data.get("area", ""))
	play_time = float(data.get("play_time", 0.0))
	hp_changed.emit(hp, max_hp)


func save_game(path: String = SAVE_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		Log.error("state.save_failed", {"path": path, "err": FileAccess.get_open_error()})
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	Log.info("state.saved", {"path": path})
	return true


func load_game(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		Log.warn("state.load_missing", {"path": path})
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		Log.error("state.load_corrupt", {"path": path})
		return false
	from_dict(parsed)
	Log.info("state.loaded", {"path": path})
	return true
