class_name IsoHud
extends CanvasLayer
## The in-game HUD, laid out like the concept combat frame:
##
##   top-left     portrait + health bar + stamina bar + status pips
##   top-right    minimap plate
##   bottom-left  portrait + name + health bar
##   bottom-centre  ability bar (three ability icons)
##   bottom-right currency
##
## Every element is a Sprite2D sampling the generated HUD atlas, so the HUD is
## art, not engine rectangles. Labels use the pixel font with antialiasing off.

const ATLAS := "res://assets/ui/hud.json"
const FONT_PATH := "res://assets/fonts/pixel.ttf"

var data: Dictionary = {}
var root: Control
var _atlas: Dictionary = {}
var _tex: Texture2D

var _hp_bar: TextureRect
var _stam_bar: TextureRect
var _ram_bar: TextureRect
var _hp_bar_big: TextureRect
var _name_label: Label
var _cred_label: Label
var _objective_label: Label
var _minimap: TextureRect
var _slots: Array[TextureRect] = []
var _toast: Label
var _toast_t := 0.0
var _pips: Array[ColorRect] = []


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	if ResourceLoader.exists(ATLAS):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(ATLAS))
		if parsed is Dictionary:
			_atlas = parsed.get("tiles", {})
			var sheet := str(parsed.get("sheet", ""))
			if ResourceLoader.exists(sheet):
				_tex = load(sheet) as Texture2D
	_build()


func _tex_rect(tile: String) -> TextureRect:
	var r := TextureRect.new()
	if _atlas.has(tile) and _tex != null:
		var a: Array = _atlas[tile]
		var at := AtlasTexture.new()
		at.atlas = _tex
		at.region = Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
		r.texture = at
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.stretch_mode = TextureRect.STRETCH_KEEP
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _label(text: String, size: int = 10, color: Color = Color("#dce9f8")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if ResourceLoader.exists(FONT_PATH):
		l.add_theme_font_override("font", load(FONT_PATH))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build() -> void:
	# --- top left: portrait, health, stamina, pips
	var portrait := _tex_rect("portrait")
	portrait.position = Vector2(10, 8)
	root.add_child(portrait)

	_hp_bar = _tex_rect("bar_hp")
	_hp_bar.position = Vector2(60, 12)
	root.add_child(_hp_bar)

	_stam_bar = _tex_rect("bar_stam")
	_stam_bar.position = Vector2(60, 24)
	root.add_child(_stam_bar)

	_ram_bar = _tex_rect("bar_ram")
	_ram_bar.position = Vector2(60, 32)
	root.add_child(_ram_bar)

	for i in 5:
		var pip := ColorRect.new()
		pip.color = Color("#38d8ff")
		pip.size = Vector2(4, 4)
		pip.position = Vector2(60 + i * 7, 41)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(pip)
		_pips.append(pip)

	# --- top right: minimap
	_minimap = _tex_rect("minimap")
	_minimap.position = Vector2(960 - 68 - 10, 8)
	root.add_child(_minimap)

	# --- bottom left: portrait, name, health
	var portrait2 := _tex_rect("portrait")
	portrait2.position = Vector2(10, 540 - 44 - 14)
	root.add_child(portrait2)

	_name_label = _label("RIN", 11, Color("#38d8ff"))
	_name_label.position = Vector2(60, 540 - 44 - 12)
	root.add_child(_name_label)

	_hp_bar_big = _tex_rect("bar_hp")
	_hp_bar_big.position = Vector2(60, 540 - 44 + 2)
	root.add_child(_hp_bar_big)

	# --- bottom centre: ability bar
	var bar_plate := _tex_rect("plate_small")
	bar_plate.position = Vector2(960 * 0.5 - 60, 540 - 40)
	root.add_child(bar_plate)
	var kinds := ["slot_blades", "slot_swirl", "slot_slash"]
	for i in kinds.size():
		var s := _tex_rect(kinds[i])
		s.position = Vector2(960 * 0.5 - 54 + i * 34, 540 - 37)
		root.add_child(s)
		_slots.append(s)

	# --- bottom right: currency
	var coin := _tex_rect("coin")
	coin.position = Vector2(960 - 96, 540 - 26)
	root.add_child(coin)
	_cred_label = _label("0", 12, Color("#f0c850"))
	_cred_label.position = Vector2(960 - 80, 540 - 30)
	root.add_child(_cred_label)

	# --- objective chip under the top-left bar
	_objective_label = _label("", 9, Color("#8fb4d8"))
	_objective_label.position = Vector2(60, 52)
	root.add_child(_objective_label)

	# --- toast: briefly shows an event ("+1 CREDITS", "HACKED", ...)
	_toast = _label("", 12, Color("#a8f0ff"))
	_toast.position = Vector2(960 * 0.5 - 60, 96)
	_toast.visible = false
	root.add_child(_toast)


func set_values(v: Dictionary) -> void:
	data = v
	var hp := float(v.get("hp", 100.0))
	var hp_max := maxf(1.0, float(v.get("hp_max", 100.0)))
	var pct := clampf(hp / hp_max, 0.0, 1.0)
	if _hp_bar:
		_hp_bar.texture = _tex_for_hp(pct)
	if _hp_bar_big:
		_hp_bar_big.texture = _tex_for_hp(pct)
	if _cred_label:
		_cred_label.text = str(int(v.get("cred", 0)))
	if _objective_label:
		_objective_label.text = str(v.get("objective", ""))
	if _name_label:
		_name_label.text = str(v.get("name", "RIN"))
	var ram_pct := clampf(float(v.get("ram", 0.0)) / maxf(1.0, float(v.get("ram_max", 8.0))), 0.0, 1.0)
	if _ram_bar:
		_ram_bar.texture = _tex_for_bar("bar_ram", ram_pct)
	for i in _pips.size():
		if i < _pips.size():
			var on := i < int(v.get("status", 0))
			_pips[i].color = Color("#38d8ff") if on else Color("#22303f")


func _tex_for_hp(pct: float) -> Texture2D:
	# three authored states is enough; a runtime-tinted bar would break the palette
	if pct > 0.66:
		return _tex_rect("bar_hp").texture
	if pct > 0.33:
		return _tex_rect("bar_hp_half").texture
	return _tex_rect("bar_hp_half").texture


func _tex_for_bar(tile: String, pct: float) -> Texture2D:
	var t := _tex_rect(tile)
	if t.texture is AtlasTexture:
		var at := (t.texture as AtlasTexture).duplicate() as AtlasTexture
		var r := at.region
		at.region = Rect2(r.position, Vector2(maxf(2.0, r.size.x * pct), r.size.y))
		return at
	return t.texture


func show_toast(text: String, seconds: float = 1.4) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_t = seconds
	if _toast.text.length() > 0:
		_toast.position.x = 960 * 0.5 - float(_toast.text.length()) * 3.2


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast.visible = false


func visible_parts() -> int:
	var n := 0
	for c in root.get_children():
		if c.visible:
			n += 1
	return n
