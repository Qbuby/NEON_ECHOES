class_name IsoLighting
extends Node2D
## Colored neon light on the isometric ground.
##
## Every concept image is lit by its signage: the corporate plaza has cyan pools
## under the entrance and magenta under the billboards; the entertainment street
## is washed pink with cyan spill; the combat shot has orange firelight on wet
## paving. A plain dark floor reads as a dungeon, not as a cyberpunk street.
##
## Implemented as additive sprites with a quantised radial texture, because
## PointLight2D does not render usefully under gl_compatibility. Quantising the
## falloff to a few steps keeps the light in the same pixel-art language as the
## tiles: a smooth gradient reads as a modern-engine bloom and breaks the look.

## Light definitions: position in grid space, radius in pixels, tint, strength.
var lights: Array = []

static var _tex: ImageTexture


func setup(defs: Array) -> void:
	lights = defs
	queue_redraw()


func _draw() -> void:
	for l in lights:
		var pos: Vector2 = l.get("pos", Vector2.ZERO)
		var radius := float(l.get("radius", 90.0))
		var col: Color = l.get("color", Color("#38d8ff"))
		var strength := float(l.get("strength", 0.45))
		var tex := radial_texture()
		draw_texture_rect(tex, Rect2(pos - Vector2(radius, radius * 0.55),
			Vector2(radius * 2.0, radius * 1.1)), false, Color(col.r, col.g, col.b, strength))


## A quantised radial falloff, 4 steps, elliptical when drawn.
static func radial_texture() -> ImageTexture:
	if _tex != null:
		return _tex
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in size:
		for x in size:
			var dx := (x - size * 0.5) / (size * 0.5)
			var dy := (y - size * 0.5) / (size * 0.5)
			var d := sqrt(dx * dx + dy * dy)
			if d >= 1.0:
				continue
			# four hard bands: the light keeps the palette's stepped shading
			var a := 0.0
			if d < 0.22:
				a = 1.0
			elif d < 0.45:
				a = 0.62
			elif d < 0.70:
				a = 0.32
			else:
				a = 0.13
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_tex = ImageTexture.create_from_image(img)
	return _tex
