extends AnimatedSprite2D
## One-shot sprite effect that plays once and frees itself.
##
## Spawn it from code:
##     Fx.spawn(self, "res://src/fx/fx.tscn", global_position, rotation)

@export var animation_name := "slash"
@export var auto_free := true
@export var free_delay := 0.0


func _ready() -> void:
	add_to_group("fx")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 5
	if sprite_frames == null:
		queue_free()
		return
	sprite_frames = sprite_frames.duplicate()
	var names := sprite_frames.get_animation_names()
	if names.is_empty():
		return
	var anim := animation_name if sprite_frames.has_animation(animation_name) else String(names[0])
	sprite_frames.set_animation_loop(anim, false)
	animation_finished.connect(_on_finished)
	play(anim)


func _on_finished() -> void:
	if not auto_free:
		return
	if free_delay > 0.0:
		await get_tree().create_timer(free_delay).timeout
	queue_free()


## Convenience spawner so gameplay code never repeats the instantiate dance.
static func spawn(parent: Node, scene_path: String, at: Vector2, rot: float = 0.0, anim: String = "") -> AnimatedSprite2D:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		Log.warn("fx.missing", {"scene": scene_path})
		return null
	var node := packed.instantiate() as AnimatedSprite2D
	if anim != "":
		node.animation_name = anim
	parent.add_child(node)
	node.global_position = at
	node.rotation = rot
	return node
