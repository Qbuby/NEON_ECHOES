class_name ActorSprite
extends Sprite2D
## An animated 2:1 isometric actor: a SpriteFrames-style strip driven from a
## small JSON definition, anchored at the feet so it stands on its tile.
##
##     var a := ActorSprite.new()
##     a.setup("res://assets/actors/rin/rin.json")
##     a.play("walk_s")

var def: Dictionary = {}
var frames: Dictionary = {}            # name -> {x,y,w,h,duration}
var animations: Dictionary = {}        # "walk_s" -> [frame names]
var current := ""
var _t := 0.0
var _i := 0
var _texture: Texture2D


func setup(json_path: String) -> bool:
	if not ResourceLoader.exists(json_path):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if not (parsed is Dictionary):
		return false
	def = parsed
	frames = def.get("frames", {})
	animations = def.get("animations", {})
	var tex_path := str(def.get("sheet", ""))
	if tex_path != "" and ResourceLoader.exists(tex_path):
		_texture = load(tex_path) as Texture2D
	texture = _texture
	region_enabled = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	centered = false
	var anchor: Array = def.get("anchor", [0, 0])
	# offset so the sprite's anchor pixel sits on this node's origin
	offset = Vector2(-float(anchor[0]), -float(anchor[1]))
	return true


func play(anim: String, restart: bool = false) -> void:
	if anim == current and not restart:
		return
	if not animations.has(anim):
		return
	current = anim
	_t = 0.0
	_i = 0
	_apply()


func _apply() -> void:
	if current == "":
		return
	var list: Array = animations.get(current, [])
	if list.is_empty():
		return
	var name := str(list[_i % list.size()])
	var f: Dictionary = frames.get(name, {})
	if f.is_empty():
		return
	var w := float(f.get("w", 48))
	var h := float(f.get("h", 64))
	region_rect = Rect2(float(f.get("x", 0)), float(f.get("y", 0)), w, h)


func _process(delta: float) -> void:
	if current == "":
		return
	var list: Array = animations.get(current, [])
	if list.size() <= 1:
		return
	var name := str(list[_i % list.size()])
	var dur := float(frames.get(name, {}).get("duration", 120)) / 1000.0
	_t += delta
	if _t >= dur:
		_t -= dur
		_i = (_i + 1) % list.size()
		_apply()


func frame_count() -> int:
	return animations.size()


func has_anim(anim: String) -> bool:
	return animations.has(anim)
