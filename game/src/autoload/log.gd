extends Node
## Structured logging for humans and machines.
##
## Every record is written twice: a readable line to stdout (so the terminal and
## the Godot editor Output panel show it) and one JSON object per line to
## user://logs/session.jsonl (so an agent or a test can parse it).
##
## Use it instead of print() for anything an agent might need to diagnose:
##     Log.info("enemy.died", {"id": name, "wave": 3})
##     Log.error("pickup.missing_icon", {"item": "key"})

signal logged(record: Dictionary)

const LOG_DIR := "user://logs"
const LOG_FILE := "user://logs/session.jsonl"

var session_id := ""
var min_level := 0  # 0 debug, 1 info, 2 warn, 3 error

var _file: FileAccess
var _levels := {"debug": 0, "info": 1, "warn": 2, "error": 3}


func _ready() -> void:
	session_id = "%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_msec() % 1000]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))
	_file = FileAccess.open(LOG_FILE, FileAccess.WRITE)
	info("log.session_start", {
		"session": session_id,
		"godot": Engine.get_version_info().string,
		"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
		"headless": DisplayServer.get_name() == "headless",
	})


func _exit_tree() -> void:
	if _file:
		info("log.session_end", {"session": session_id})
		_file.flush()
		_file.close()
		_file = null


func debug(event: String, data: Dictionary = {}) -> void:
	_write("debug", event, data)


func info(event: String, data: Dictionary = {}) -> void:
	_write("info", event, data)


func warn(event: String, data: Dictionary = {}) -> void:
	_write("warn", event, data)


func error(event: String, data: Dictionary = {}) -> void:
	_write("error", event, data)


## Path of the JSONL file, for tests and for the agent to tail.
func log_path() -> String:
	return ProjectSettings.globalize_path(LOG_FILE)


func read_records(limit: int = 200) -> Array:
	## Returns the last `limit` records; used by the playtest harness.
	var path := log_path()
	if not FileAccess.file_exists(LOG_FILE):
		return []
	var f := FileAccess.open(LOG_FILE, FileAccess.READ)
	if f == null:
		return []
	var lines: Array = []
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() == "":
			continue
		var parsed = JSON.parse_string(line)
		if parsed is Dictionary:
			lines.append(parsed)
	f.close()
	if lines.size() > limit:
		lines = lines.slice(lines.size() - limit)
	return lines


func _write(level: String, event: String, data: Dictionary) -> void:
	if _levels.get(level, 1) < min_level:
		return
	var record := {
		"ts": Time.get_datetime_string_from_system(true),
		"unix": Time.get_unix_time_from_system(),
		"frame": Engine.get_process_frames(),
		"level": level,
		"event": event,
		"session": session_id,
	}
	for key in data:
		record[key] = data[key]
	if _file:
		_file.store_line(JSON.stringify(record))
		_file.flush()
	print("[%s] %s %s" % [level.to_upper(), event, JSON.stringify(data)])
	logged.emit(record)
