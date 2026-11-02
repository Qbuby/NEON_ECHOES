class_name IsoGrid
extends RefCounted
## Isometric 2:1 world <-> screen projection, and the depth key that makes it
## draw correctly.
##
## Every concept image in asserts/mind_map is a 2:1 isometric view with real
## building height: the city overview, the corporate plaza, the industrial slum
## and the black-market hall all show extruded walls and diamond floors. A flat
## orthographic grid cannot reproduce that, which is why the previous renderer
## read as "wallpaper" no matter how the tiles were authored.
##
## 2:1 means: one tile across (x+1) moves +TILE_W/2 px right and +TILE_H/2 px
## down; one tile away (y+1) moves -TILE_W/2 px right and +TILE_H/2 px down.
## With TILE_W = 64 and TILE_H = 32 a floor tile is a 64x32 diamond.
##
## Coordinates:
##   cell  = Vector2i grid position (x, y)
##   z     = height in tile units (a wall of height 2.0 is two tiles tall)
##   world = Vector3(cell.x, cell.y, z) — what gameplay and saving use
##   screen = Vector2 pixels, with the cell's diamond *centre* at that point

const TILE_W := 64
const TILE_H := 32

## Half-extents, precomputed for the hot path.
const HW := 32.0
const HH := 16.0


## Grid position (fractional allowed) to the screen point of that cell's centre
## at the given height.
static func project(gx: float, gy: float, z: float = 0.0) -> Vector2:
	return Vector2((gx - gy) * HW, (gx + gy) * HH - z * TILE_H)


## Inverse of project() at z = 0. Returns fractional grid coordinates, so the
## caller can floor() to get a cell or use the fraction for sub-cell picking.
static func unproject(screen: Vector2, z: float = 0.0) -> Vector2:
	var sx := screen.x / HW
	var sy := (screen.y + z * TILE_H) / HH
	return Vector2((sy + sx) * 0.5, (sy - sx) * 0.5)


## Screen point of a cell's diamond corner. corner 0 = north, 1 = east,
## 2 = south, 3 = west. Walls and props anchor on the south corner so they
## stand on the near edge of their tile.
static func cell_corner(cell: Vector2i, corner: int, z: float = 0.0) -> Vector2:
	var centre := project(float(cell.x), float(cell.y), z)
	match corner:
		0:
			return centre + Vector2(0, -HH)
		1:
			return centre + Vector2(HW, 0)
		2:
			return centre + Vector2(0, HH)
		_:
			return centre + Vector2(-HW, 0)


## Depth key for the painter's algorithm.
##
## Sorting by screen y alone is wrong for isometric: two cells on the same row
## can share a y, and a tall object behind a short one must still draw first.
## The correct order for an axis-aligned 2:1 world is: lower (x+y) in front of
## higher, and among equal (x+y) the taller object wins ties in its own favour
## only when it is nearer to the camera, so we use (x + y) ascending with a
## height term that lets a tall structure bulge toward the viewer.
##
## Returns a float; larger means drawn later (in front).
static func depth_key(cell: Vector2i, z: float = 0.0, footprint: float = 0.0) -> float:
	return float(cell.x + cell.y) + footprint * 0.5 + z * 0.001


## True when a screen point lies inside the tile's floor diamond at height z.
static func point_in_cell(screen: Vector2, cell: Vector2i, z: float = 0.0) -> bool:
	var c := project(float(cell.x), float(cell.y), z)
	var dx := absf(screen.x - c.x) / HW
	var dy := absf(screen.y - c.y) / HH
	return dx + dy <= 1.0


## The cell under a screen point, plus how far inside the diamond the point is
## (used to decide which of two overlapping candidates the cursor means).
static func pick(screen: Vector2) -> Vector2i:
	var g := unproject(screen)
	return Vector2i(floori(g.x + 0.5), floori(g.y + 0.5))


## Bounding box size of a w x d footprint tile block, for culling and for
## placing a floor mesh.
static func block_size(w: int, d: int) -> Vector2i:
	return Vector2i((w + d) * int(HW), (w + d) * int(HH))


## Nearest cell whose *top face* is under the cursor, searching from the front
## of the stack backwards. Walls occlude the floor behind them, so a click on a
## wall's face must resolve to the wall, not to the floor it hides.
static func pick_with_heights(screen: Vector2, heights: Dictionary) -> Vector2i:
	# Walk candidate heights from tall to short; the first cell whose diamond
	# at that height contains the point is what the player is looking at.
	var best := Vector2i(-99999, -99999)
	var best_z := -1.0
	for key in heights:
		var z := float(heights[key])
		if z <= best_z:
			continue
		if point_in_cell(screen, key, z):
			best = key
			best_z = z
	if best_z >= 0.0:
		return best
	return pick(screen)
