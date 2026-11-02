extends Node
## Sound effects and music with a small player pool.
##
## Files are looked up by name in res://assets/audio/sfx/<name>.wav and
## res://assets/audio/music/<name>.wav. Missing files log a warning once and
## never crash the game: audio is feedback, not a hard dependency.
##
##     AudioManager.play_sfx("hit")
##     AudioManager.play_music("field")

const SFX_DIR := "res://assets/audio"
const MUSIC_DIR := "res://assets/audio"
const POOL_SIZE := 8

var sfx_volume := 0.8
var music_volume := 0.5

var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _cache: Dictionary = {}
var _missing: Dictionary = {}
var _music: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("SFX")
	_ensure_bus("Music")
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music)


func play_sfx(name: String, pitch_jitter: float = 0.06) -> void:
	var stream := _load_stream(SFX_DIR + "/" + name + ".wav")
	if stream == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.volume_db = linear_to_db(maxf(sfx_volume, 0.0001))
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func play_music(name: String, loop: bool = true) -> void:
	var stream := _load_stream(MUSIC_DIR + "/" + name + ".wav")
	if stream == null:
		return
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	_music.stream = stream
	_music.volume_db = linear_to_db(maxf(music_volume, 0.0001))
	_music.play()
	Log.info("audio.music", {"name": name})


func stop_music() -> void:
	_music.stop()


func has_sfx(name: String) -> bool:
	return ResourceLoader.exists(SFX_DIR + "/" + name + ".wav")


func _load_stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		if not _missing.has(path):
			_missing[path] = true
			Log.warn("audio.missing", {"path": path})
		return null
	var stream := load(path) as AudioStream
	_cache[path] = stream
	return stream


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
