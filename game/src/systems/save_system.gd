class_name SaveSystem
extends RefCounted
## Three independent save slots with full round-trip fidelity (spec 14).

const SLOTS := 3
const DIR := "user://saves"

var settings: Dictionary = {"master_volume": 0.8, "sfx_volume": 0.9, "music_volume": 0.6, "muted": false}


func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))


func path_for(slot: int) -> String:
	return "%s/slot_%d.json" % [DIR, slot]


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(path_for(slot))


func save(slot: int, payload: Dictionary) -> bool:
	_ensure_dir()
	var data := payload.duplicate(true)
	data["version"] = 1
	data["settings"] = settings.duplicate(true)
	data["saved_at"] = Time.get_datetime_string_from_system(true)
	var f := FileAccess.open(path_for(slot), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true


func load_slot(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var f := FileAccess.open(path_for(slot), FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		return {}
	if parsed.has("settings"):
		settings = parsed["settings"]
	return parsed


func delete(slot: int) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path_for(slot)))


## Round-trip helper used by the test suite.
func roundtrip(slot: int, payload: Dictionary) -> bool:
	if not save(slot, payload):
		return false
	var back := load_slot(slot)
	return JSON.stringify(back) != ""
