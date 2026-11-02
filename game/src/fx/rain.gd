extends CanvasLayer
## Rain over the district: falling streaks, a wet tint, and splashes where drops
## land. Screen-space so it covers the whole frame at any camera position, and
## deterministic so the rain screenshot is reproducible.
##
##     Rain.start(0.8)      # intensity 0..1
##     Rain.stop()

const LAYER := 6   # above the world, below the HUD (10)
const DROPS := 240

var intensity: float = 0.0
var _drops: Array = []          # [x, y, speed, length, alpha]
var _splashes: Array = []       # [x, y, age]
var _draw_node: Node2D
var _tint: ColorRect
var _rng := RandomNumberGenerator.new()
var _size := Vector2(960, 540)


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 90210
	_size = Vector2(float(ProjectSettings.get_setting("display/window/size/viewport_width", 960)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 540)))
	_tint = ColorRect.new()
	_tint.color = Color(0.16, 0.26, 0.42, 0.0)
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tint)
	_draw_node = Node2D.new()
	_draw_node.draw.connect(_on_draw)
	add_child(_draw_node)
	visible = false


func start(strength: float = 1.0) -> void:
	intensity = clampf(strength, 0.0, 1.0)
	visible = intensity > 0.0
	_tint.color.a = 0.10 * intensity
	_drops.clear()
	var count := int(DROPS * intensity)
	for i in count:
		_drops.append([
			_rng.randf() * _size.x,
			_rng.randf() * _size.y,
			520.0 + _rng.randf() * 260.0,
			10.0 + _rng.randf() * 10.0,
			0.18 + _rng.randf() * 0.26,
		])
	_splashes.clear()
	_draw_node.queue_redraw()


func stop() -> void:
	intensity = 0.0
	visible = false
	_drops.clear()
	_splashes.clear()
	_tint.color.a = 0.0
	_draw_node.queue_redraw()


func _process(delta: float) -> void:
	if intensity <= 0.0:
		return
	var h := _size.y
	var w := _size.x
	for d in _drops:
		d[1] += float(d[2]) * delta
		d[0] -= 60.0 * delta          # the wind is blowing left
		if d[1] > h:
			if _splashes.size() < 40:
				_splashes.append([d[0], h - 2.0 - _rng.randf() * 24.0, 0.0])
			d[1] = -float(d[3]) - _rng.randf() * 40.0
			d[0] = _rng.randf() * w + 60.0
		if d[0] < -20.0:
			d[0] = w + 20.0
	var keep := []
	for s in _splashes:
		s[2] = float(s[2]) + delta
		if float(s[2]) < 0.32:
			keep.append(s)
	_splashes = keep
	_draw_node.queue_redraw()


func _on_draw() -> void:
	if intensity <= 0.0:
		return
	var streak := Color(0.62, 0.78, 0.95, 0.0)
	for d in _drops:
		streak.a = float(d[4]) * intensity
		_draw_node.draw_line(Vector2(float(d[0]), float(d[1])),
			Vector2(float(d[0]) + 3.0, float(d[1]) + float(d[3])), streak, 1.0)
	for s in _splashes:
		var t := float(s[2]) / 0.32
		var col := Color(0.72, 0.86, 1.0, (1.0 - t) * 0.45)
		var r := 2.0 + t * 5.0
		_draw_node.draw_line(Vector2(float(s[0]) - r, float(s[1])),
			Vector2(float(s[0]) + r, float(s[1])), col, 1.0)


func drop_count() -> int:
	return _drops.size()


func is_raining() -> bool:
	return intensity > 0.0
