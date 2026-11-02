class_name Player
extends CharacterBody2D
## Top-down player controller.
##
## Works with any 8-direction SpriteFrames that names animations
## `<anim>_<dir>` (idle_s, walk_ne, attack_w ...), which is what SpriteKiln
## exports. Missing directions fall back to the nearest cardinal, then to `s`.
##
## Input actions: move_left/right/up/down, attack, interact, pause.

signal attacked
signal interacted(target: Node)

@export var speed := 78.0
@export var acceleration := 900.0
@export var friction := 1100.0
@export var attack_time := 0.34
@export var attack_active_from := 0.08
@export var attack_active_to := 0.2
@export var attack_cooldown := 0.1
@export var foot_offset_px := 0.0
@export var camera_limits := Rect2i(0, 0, 0, 0)
@export var fx_scene := "res://src/fx/fx.tscn"

const DIR_VECTORS := {
	"s": Vector2.DOWN, "se": Vector2(1, 1), "e": Vector2.RIGHT, "ne": Vector2(1, -1),
	"n": Vector2.UP, "nw": Vector2(-1, -1), "w": Vector2.LEFT, "sw": Vector2(-1, 1),
}

var facing := "s"
var attacking := false
var can_move := true

var _attack_elapsed := 0.0
var _cooldown_left := 0.0
var _knockback := Vector2.ZERO
var _interact_target: Node = null

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var health: Health = $Health
@onready var camera: Camera2D = $Camera
@onready var interact_area: Area2D = $InteractArea


func _ready() -> void:
	add_to_group("player")
	_align_sprite()
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	hitbox.deactivate()
	interact_area.area_entered.connect(_on_interact_area_entered)
	interact_area.area_exited.connect(_on_interact_area_exited)
	_apply_camera_limits()
	_play("idle")


func _physics_process(delta: float) -> void:
	_tick_attack(delta)
	_tick_movement(delta)
	_tick_interact()


func _separation() -> Vector2:
	## Soft push away from enemies so bodies never merge into one blob.
	var push := Vector2.ZERO
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not e is Node2D:
			continue
		var offset: Vector2 = global_position - (e as Node2D).global_position
		var dist := offset.length()
		if dist > 0.01 and dist < 12.0:
			push += offset.normalized() * ((12.0 - dist) / 12.0) * 130.0
	return push


func _tick_movement(delta: float) -> void:
	var input := Vector2.ZERO
	if can_move and not attacking:
		input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var target := input * speed
	if input.length() > 0.01:
		velocity = velocity.move_toward(target, acceleration * delta)
		facing = _dir_name(input)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	if _knockback.length() > 1.0:
		velocity += _knockback
		_knockback = _knockback.move_toward(Vector2.ZERO, 900.0 * delta)
	velocity += _separation()
	move_and_slide()
	if not attacking:
		_play("walk" if velocity.length() > 8.0 else "idle")


func _tick_attack(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left -= delta
	if Input.is_action_just_pressed("attack") and not attacking and _cooldown_left <= 0.0:
		_start_attack()
	if not attacking:
		return
	_attack_elapsed += delta
	if _attack_elapsed >= attack_active_from and _attack_elapsed < attack_active_to:
		if not hitbox.active:
			hitbox.activate()
	elif hitbox.active:
		hitbox.deactivate()
	if _attack_elapsed >= attack_time:
		attacking = false
		hitbox.deactivate()
		_cooldown_left = attack_cooldown
		_play("idle")


func _start_attack() -> void:
	attacking = true
	_attack_elapsed = 0.0
	_play("attack")
	var dir: Vector2 = DIR_VECTORS.get(facing, Vector2.DOWN)
	hitbox.position = dir.normalized() * 12.0 + Vector2(0, -6)
	_spawn_attack_fx(dir)
	AudioManager.play_sfx("swing")
	UxProbe.begin_event("player_attack", {"dir": facing})
	UxProbe.note("sfx")
	UxProbe.note("fx")
	UxProbe.end_event()
	attacked.emit()
	Log.info("player.attack", {"dir": facing, "at": [snapped(global_position.x, 0.1), snapped(global_position.y, 0.1)]})


func _spawn_attack_fx(dir: Vector2) -> void:
	if fx_scene == "":
		return
	var fx := load(fx_scene) as PackedScene
	if fx == null:
		return
	var node := fx.instantiate() as Node2D
	get_parent().add_child(node)
	node.global_position = global_position + dir.normalized() * 10.0 + Vector2(0, -8)
	node.rotation = dir.angle()
	node.scale = Vector2(1.0, -1.0) if dir.x < 0 else Vector2.ONE


func _tick_interact() -> void:
	if Input.is_action_just_pressed("interact") and _interact_target != null:
		if _interact_target.has_method("interact"):
			_interact_target.interact(self)
			interacted.emit(_interact_target)


func apply_knockback(push: Vector2) -> void:
	_knockback = push


func set_can_move(value: bool) -> void:
	can_move = value


func _on_damaged(_amount: int, _info: Dictionary) -> void:
	UxProbe.begin_event("hit_taken", {"amount": _amount, "hp": health.hp})
	AudioManager.play_sfx("hurt")
	UxProbe.note("sfx")
	_flash()
	Juice.shake(5.0, 0.26)
	Juice.hit_stop(0.07, 0.05)
	Juice.vignette(0.5, 0.12)
	Juice.number(global_position + Vector2(0, -18), -_amount, Color("#ff6b6b"), true)
	_start_invuln_blink()
	Log.info("player.damaged", {"hp": health.hp})
	GameState.set_hp(health.hp)


func _on_died(_info: Dictionary) -> void:
	Log.info("player.died", {})
	can_move = false
	_play("idle")
	GameState.finish(false)


func _start_invuln_blink() -> void:
	var tween := create_tween()
	tween.set_loops(5)
	tween.tween_property(sprite, "modulate:a", 0.35, 0.07)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.07)


func _flash() -> void:
	UxProbe.note("flash")
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1.0, 0.45, 0.45), 0.06)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.12)


func _on_interact_area_entered(area: Area2D) -> void:
	if area.has_method("interact"):
		_interact_target = area


func _on_interact_area_exited(area: Area2D) -> void:
	if area == _interact_target:
		_interact_target = null


func _dir_name(v: Vector2) -> String:
	if v.length() < 0.01:
		return facing
	var angle := rad_to_deg(v.angle())
	if angle >= -22.5 and angle < 22.5:
		return "e"
	if angle >= 22.5 and angle < 67.5:
		return "se"
	if angle >= 67.5 and angle < 112.5:
		return "s"
	if angle >= 112.5 and angle < 157.5:
		return "sw"
	if angle >= 157.5 or angle < -157.5:
		return "w"
	if angle >= -157.5 and angle < -112.5:
		return "nw"
	if angle >= -112.5 and angle < -67.5:
		return "n"
	return "ne"


func _play(anim: String) -> void:
	var name := _resolve_animation(anim, facing)
	if name == "":
		return
	if sprite.animation != name:
		sprite.play(name)


func _resolve_animation(anim: String, dir: String) -> String:
	var frames := sprite.sprite_frames
	if frames == null:
		return ""
	var candidates: Array[String] = ["%s_%s" % [anim, dir]]
	var fallbacks := {
		"ne": ["e", "n"], "nw": ["w", "n"], "se": ["e", "s"], "sw": ["w", "s"],
	}
	for fb in fallbacks.get(dir, []):
		candidates.append("%s_%s" % [anim, fb])
	candidates.append("%s_s" % anim)
	candidates.append(anim)
	for candidate in candidates:
		if frames.has_animation(candidate):
			return candidate
	return ""


func _align_sprite() -> void:
	## Bottom-centre of the frame sits on the node origin, so the character's
	## feet match its collision shape whatever size the generator produced.
	var frames := sprite.sprite_frames
	if frames == null or frames.get_animation_names().is_empty():
		return
	var first := String(frames.get_animation_names()[0])
	if frames.get_frame_count(first) == 0:
		return
	var tex := frames.get_frame_texture(first, 0)
	if tex == null:
		return
	var size := tex.get_size()
	sprite.centered = false
	sprite.offset = Vector2(-size.x * 0.5, -size.y + foot_offset_px)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _apply_camera_limits() -> void:
	if camera == null:
		return
	if camera_limits.size.x > 0 and camera_limits.size.y > 0:
		camera.limit_left = camera_limits.position.x
		camera.limit_top = camera_limits.position.y
		camera.limit_right = camera_limits.position.x + camera_limits.size.x
		camera.limit_bottom = camera_limits.position.y + camera_limits.size.y
