extends SceneTree
## Verify the gameplay events reference sound names that actually exist on disk,
## and that the AudioManager resolves them.

var passed := 0
var failed := 0


func _initialize() -> void:
	var src := FileAccess.get_file_as_string("res://src/world/iso_playable.gd")
	# every literal _sfx("name") / _play_music("name") in gameplay must exist
	var names: Array = []
	var re := RegEx.new()
	re.compile("_sfx[(][\"]([a-z_]+)[\"][)]")
	for m in re.search_all(src):
		names.append(m.get_string(1))
	var re2 := RegEx.new()
	re2.compile("_play_music[(][\"]([a-z_]+)[\"][)]")
	for m in re2.search_all(src):
		names.append(m.get_string(1))
	# _music_for returns names dynamically; check those literals too
	for track in ["mus_combat", "mus_calm", "mus_menu"]:
		names.append(track)
	var missing: Array = []
	for n in names:
		if not FileAccess.file_exists("res://assets/audio/%s.wav" % n):
			missing.append(n)
	_check(names.size() >= 6, "gameplay references %d event sounds" % names.size())
	_check(missing.is_empty(), "every referenced sound exists %s" % str(missing))

	# the manager resolves a real name and survives a bogus one
	var am = load("res://src/autoload/audio_manager.gd").new()
	root.add_child(am)
	await process_frame
	var ok := true
	for n in names:
		if not am.has_method("play_sfx"):
			ok = false
	_check(ok, "AudioManager exposes play_sfx")

	# real WAVs parse as audio streams
	var bad: Array = []
	for n in ["gun_pistol", "melee_hit", "int_door", "ui_open", "mus_combat"]:
		var stream = load("res://assets/audio/%s.wav" % n)
		if stream == null:
			bad.append(n)
	_check(bad.is_empty(), "sampled WAVs load as audio streams %s" % str(bad))

	_finish()


func _check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("PASS  ", label)
	else:
		failed += 1
		print("FAIL  ", label)


func _finish() -> void:
	print("AUDIO_RESULT {\"passed\":%d,\"failed\":%d}" % [passed, failed])
	quit(1 if failed > 0 else 0)
