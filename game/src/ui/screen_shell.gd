class_name ScreenShell
extends CanvasLayer
## The frame every full-screen UI shares, matching the concept UI mockup:
##
##   left rail    the game wordmark, then Inventory / Cyberware / Weapons /
##                Skills / Character, with the active entry highlighted
##   top bar      level chip, currency chip, a secondary counter, close button
##   content      two columns: a body panel and a list panel
##   bottom hint  the input legend
##
## Screens fill `content` with their own rows; the shell owns everything else so
## the eight data screens cannot drift apart visually.

const ATLAS := "res://assets/ui/hud.json"
const FONT := "res://assets/fonts/pixel.ttf"

const RAIL := ["Inventory", "Cyberware", "Weapons", "Skills", "Character"]
const W := 960
const H := 540

var title: String = ""
var active: String = ""
var root: Control
var content: Control
var list_box: VBoxContainer
var detail_box: VBoxContainer
var _atlas: Dictionary = {}
var _tex: Texture2D
var _rail_buttons: Array[Button] = []


func setup(screen_title: String, active_entry: String, subtitle: String = "") -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	title = screen_title
	active = active_entry
	_ensure_atlas()
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# dim the game behind the panel without hiding it
	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.03, 0.05, 0.62)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(scrim)

	var bg := _panel(Rect2(14, 12, W - 28, H - 24))
	root.add_child(bg)

	# --- left rail
	_rail_buttons.clear()
	var wordmark := _label("NEON ECHOES", 13, Color("#ffffff"))
	wordmark.position = Vector2(26, 22)
	root.add_child(wordmark)
	var tm := _label("TM", 6, Color("#8fb4d8"))
	tm.position = Vector2(26 + 82, 20)
	root.add_child(tm)
	for i in RAIL.size():
		var b := Button.new()
		b.text = "  " + RAIL[i]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.position = Vector2(22, 48 + i * 24)
		b.size = Vector2(132, 22)
		b.add_theme_font_size_override("font_size", 10)
		var is_active: bool = RAIL[i] == active
		b.add_theme_color_override("font_color",
			Color("#ffffff") if is_active else Color("#7e93ad"))
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.30, 0.16, 0.38, 0.85) if is_active else Color(0, 0, 0, 0)
		st.border_color = Color("#ff2fb4") if is_active else Color(0, 0, 0, 0)
		st.border_width_left = 2 if is_active else 0
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("hover", st)
		root.add_child(b)
		_rail_buttons.append(b)

	# --- top bar
	var chip_lvl := _chip(Vector2(176, 16), "LV 12", Color("#ff2fb4"))
	root.add_child(chip_lvl)
	var chip_cred := _chip(Vector2(250, 16), "1050", Color("#f0c850"))
	root.add_child(chip_cred)
	var sub := _label(subtitle, 9, Color("#8fb4d8"))
	sub.position = Vector2(340, 20)
	root.add_child(sub)
	var close := _label("[ESC] CLOSE", 9, Color("#7e93ad"))
	close.position = Vector2(W - 120, 20)
	root.add_child(close)

	# --- section title
	var t := _label(title.to_upper(), 15, Color("#38d8ff"))
	t.position = Vector2(176, 46)
	root.add_child(t)
	var rule := ColorRect.new()
	rule.color = Color("#1e2a3a")
	rule.position = Vector2(176, 66)
	rule.size = Vector2(W - 176 - 26, 1)
	root.add_child(rule)

	# --- content: list column + detail column
	var body := Control.new()
	body.position = Vector2(176, 76)
	body.size = Vector2(W - 176 - 26, H - 76 - 40)
	root.add_child(body)
	content = body

	list_box = VBoxContainer.new()
	list_box.position = Vector2(0, 0)
	list_box.size = Vector2(392, body.size.y)
	list_box.add_theme_constant_override("separation", 3)
	body.add_child(list_box)

	detail_box = VBoxContainer.new()
	detail_box.position = Vector2(408, 0)
	detail_box.size = Vector2(body.size.x - 408, body.size.y)
	detail_box.add_theme_constant_override("separation", 3)
	body.add_child(detail_box)

	# --- bottom hint
	var hint := _label("↑↓ SELECT    ENTER CONFIRM    ESC BACK", 8, Color("#5c6f88"))
	hint.position = Vector2(176, H - 30)
	root.add_child(hint)


func _ensure_atlas() -> void:
	if not _atlas.is_empty():
		return
	if not ResourceLoader.exists(ATLAS):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(ATLAS))
	if parsed is Dictionary:
		_atlas = parsed.get("tiles", {})
		var sheet := str(parsed.get("sheet", ""))
		if ResourceLoader.exists(sheet):
			_tex = load(sheet) as Texture2D


func _panel(r: Rect2) -> Control:
	# a plate stretched to the given rect, drawn with a StyleBox so it scales
	var p := Panel.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#0b0f18")
	st.border_color = Color("#22303f")
	st.set_border_width_all(1)
	st.corner_radius_top_left = 3
	st.corner_radius_top_right = 3
	st.corner_radius_bottom_left = 3
	st.corner_radius_bottom_right = 3
	p.add_theme_stylebox_override("panel", st)
	p.position = r.position
	p.size = r.size
	return p


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if ResourceLoader.exists(FONT):
		var f := load(FONT)
		l.add_theme_font_override("font", f)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _chip(pos: Vector2, text: String, accent: Color) -> Control:
	var holder := Control.new()
	holder.position = pos
	var bg := Panel.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#121722")
	st.border_color = accent
	st.set_border_width_all(1)
	st.content_margin_left = 6
	st.content_margin_right = 6
	bg.add_theme_stylebox_override("panel", st)
	bg.size = Vector2(66, 18)
	holder.add_child(bg)
	var l := _label(text, 10, accent)
	l.position = Vector2(6, 2)
	holder.add_child(l)
	return holder


## Add one selectable row to the list column.
func add_row(text: String, value: String = "", selected: bool = false,
		enabled: bool = true) -> Button:
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 22)
	b.add_theme_font_size_override("font_size", 10)
	if ResourceLoader.exists(FONT):
		b.add_theme_font_override("font", load(FONT))
	b.text = "  " + text + ("        " + value if value != "" else "")
	b.disabled = not enabled
	b.add_theme_color_override("font_color",
		Color("#ffffff") if selected else Color("#93a7bd"))
	b.add_theme_color_override("font_disabled_color", Color("#43536a"))
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.22, 0.12, 0.30, 0.9) if selected else Color(0.06, 0.08, 0.12, 0.75)
	st.border_color = Color("#ff2fb4") if selected else Color("#161f2c")
	st.border_width_left = 2
	st.content_margin_left = 4
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", st)
	b.add_theme_stylebox_override("pressed", st)
	b.add_theme_stylebox_override("disabled", st)
	list_box.add_child(b)
	return b


## Add a line of read-only detail text to the right column.
func add_detail(text: String, color: Color = Color("#c8d8ec"), size: int = 10) -> Label:
	var l := _label(text, size, color)
	l.custom_minimum_size = Vector2(0, 14)
	detail_box.add_child(l)
	return l


func add_divider() -> void:
	var r := ColorRect.new()
	r.color = Color("#1a2432")
	r.custom_minimum_size = Vector2(0, 1)
	detail_box.add_child(r)


func row_count() -> int:
	return list_box.get_child_count()


func click_row(index: int) -> bool:
	if index < 0 or index >= list_box.get_child_count():
		return false
	var b := list_box.get_child(index)
	if b is Button and not b.disabled:
		b.emit_signal("pressed")
		return true
	return false


func visible_rows() -> int:
	var n := 0
	for c in list_box.get_children():
		if c.visible:
			n += 1
	return n
