extends Node
## Hit feedback in one place: hit-stop, screen shake, flashes, damage numbers,
## impact bursts, rumble and the low-health vignette.
##
## Every effect here also tells the UX audit which channel fired, so "a hit
## happened but nothing indicated it" becomes a test failure instead of a
## subjective complaint.
##
##     Juice.hit_stop()
##     Juice.shake(3.0, 0.16)
##     Juice.flash(target_sprite, Color(2,2,2,1))
##     Juice.number(pos, 2, Color("#ffe08a"))
##     Juice.burst(pos, "res://src/fx/impact.tscn", 0.0, 2.0)

const FX_LAYER := 5   # under the HUD (10): feedback must not tint the UI
const IMPACT_SCENE := "res://src/fx/impact.tscn"

var shake_enabled := true
var hit_stop_enabled := true

var _canvas: CanvasLayer
var _numbers: Control
var _vignette: ColorRect
var _vignette_material: ShaderMaterial
var _shake_left := 0.0
var _shake_total := 0.0
var _shake_amount := 0.0
var _hitstop_until := 0
var _hitstop_running := false
var _flash_tweens: Dictionary = {}
var _rng := RandomNumberGenerator.new()

const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.30, 0.02, 0.06, 1.0);
void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv * vec2(1.0, 1.25)) * 1.7;
	float a = smoothstep(0.42, 1.0, d) * strength;
	// Quantised to 4 steps: pixel art banding, not a photographic gradient.
	a = floor(a * 4.0 + 0.5) / 4.0;
	COLOR = vec4(tint.rgb, a);
}
"""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1234
	_canvas = CanvasLayer.new()
	_canvas.layer = FX_LAYER
	_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_canvas)

	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	_vignette_material.shader = shader
	_vignette.material = _vignette_material
	_canvas.add_child(_vignette)

	_numbers = Control.new()
	_numbers.set_anchors_preset(Control.PRESET_FULL_RECT)
	_numbers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_numbers)


func _process(delta: float) -> void:
	_tick_shake(delta)


## --- shake ---------------------------------------------------------------

func shake(amount: float = 3.0, duration: float = 0.18) -> void:
	if not shake_enabled or amount <= 0.0:
		return
	_shake_amount = maxf(_shake_amount, amount)
	_shake_left = maxf(_shake_left, duration)
	_shake_total = maxf(_shake_total, duration)
	UxProbe.note_global("shake")


func _tick_shake(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	if _shake_left <= 0.0:
		if cam.offset != Vector2.ZERO:
			cam.offset = Vector2.ZERO
		return
	_shake_left = maxf(0.0, _shake_left - delta)
	var falloff := _shake_left / maxf(_shake_total, 0.001)
	var a := _shake_amount * falloff
	cam.offset = Vector2(_rng.randf_range(-a, a), _rng.randf_range(-a, a))


## --- hit-stop ------------------------------------------------------------

## Freezes the game briefly on impact. Uses ignore_time_scale so the pause
## itself is not slowed down.
func hit_stop(duration: float = 0.055, scale: float = 0.06) -> void:
	if not hit_stop_enabled or duration <= 0.0:
		return
	UxProbe.note_global("hitstop")
	var now := Time.get_ticks_msec()
	_hitstop_until = maxi(_hitstop_until, now + int(duration * 1000.0))
	if _hitstop_running:
		return
	_hitstop_running = true
	Engine.time_scale = scale
	while Time.get_ticks_msec() < _hitstop_until:
		await get_tree().create_timer(0.012, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstop_running = false


## --- flash ---------------------------------------------------------------

## Briefly tints a sprite. Repeated calls on the same node replace each other.
func flash(node: CanvasItem, color: Color = Color(2.0, 1.6, 1.6, 1.0), time: float = 0.12) -> void:
	if node == null or not is_instance_valid(node):
		return
	var id := node.get_instance_id()
	if _flash_tweens.has(id):
		var old: Tween = _flash_tweens[id]
		if old and old.is_valid():
			old.kill()
	var tween := create_tween()
	_flash_tweens[id] = tween
	tween.tween_property(node, "modulate", color, time * 0.3)
	tween.tween_property(node, "modulate", Color.WHITE, time * 0.7)
	UxProbe.note_global("flash")


## --- damage numbers ------------------------------------------------------

func number(world_pos: Vector2, amount: int, color: Color = Color("#ffe08a"), big: bool = false) -> void:
	if _numbers == null:
		return
	var label := Label.new()
	label.text = str(amount)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("#16121f"))
	label.add_theme_constant_override("outline_size", 2 if big else 1)
	label.add_theme_font_size_override("font_size", 16 if big else 8)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var screen := get_viewport().get_canvas_transform() * world_pos
	label.position = screen - Vector2(6, 14)
	_numbers.add_child(label)
	var drift := -18.0 if big else -12.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + drift, 0.55).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.55).set_delay(0.18)
	tween.chain().tween_callback(label.queue_free)
	UxProbe.note_global("number")


## --- world bursts --------------------------------------------------------

func burst(world_pos: Vector2, scene_path: String = IMPACT_SCENE, rot: float = 0.0, scale_mul: float = 2.0) -> void:
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return
	var node := scene.instantiate()
	var host := get_tree().current_scene
	if host == null:
		return
	host.add_child(node)
	node.global_position = world_pos
	node.rotation = rot
	node.scale = Vector2(scale_mul, scale_mul)
	UxProbe.note_global("fx")


## --- vignette / low health ----------------------------------------------

func vignette(strength: float, time: float = 0.25) -> void:
	if _vignette_material == null:
		return
	var tween := create_tween()
	tween.tween_method(func(v: float): _vignette_material.set_shader_parameter("strength", v),
		_vignette_material.get_shader_parameter("strength"), strength, time)


## --- rumble --------------------------------------------------------------

func rumble(weak: float = 0.35, strong: float = 0.6, time: float = 0.15) -> void:
	if Input.get_connected_joypads().is_empty():
		return
	Input.start_joy_vibration(0, weak, strong, time)


## --- HUD punch -----------------------------------------------------------

func punch(control: Control, amount: float = 1.25, time: float = 0.18) -> void:
	if control == null:
		return
	control.pivot_offset = control.size * 0.5
	var tween := create_tween()
	tween.tween_property(control, "scale", Vector2(amount, amount), time * 0.35)
	tween.tween_property(control, "scale", Vector2.ONE, time * 0.65).set_trans(Tween.TRANS_BACK)
	UxProbe.note_global("hud")


## Punch whatever HUD element represents the collected item.
func punch_hud() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("punch_objective"):
		hud.punch_objective()


## One call for "the player hit something".
func on_hit(target: Node2D, sprite: CanvasItem, damage: int, strong: bool) -> void:
	var at := target.global_position + Vector2(0, -10)
	flash(sprite, Color(2.4, 2.2, 2.2, 1.0), 0.1)
	burst(at, IMPACT_SCENE, _rng.randf_range(0, TAU), 2.0 if strong else 1.5)
	number(at, damage, Color("#ffe08a") if not strong else Color("#ff9a8a"), strong)
	shake(3.5 if strong else 2.0, 0.16 if strong else 0.11)
	hit_stop(0.07 if strong else 0.04)
	rumble(0.3, 0.5, 0.12)