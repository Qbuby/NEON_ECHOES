# ADR-001 — Isometric 2:1 renderer instead of a flat tile grid

**Status:** accepted · 2026-11-02
**Supersedes:** the `TileMapLayer` + `set_cells_terrain_connect` world rendering
in the original `playable_area.gd`.

## Context

The twelve concept images in `asserts/mind_map` are all isometric with real
vertical extent:

| Image | View | Height cues |
|---|---|---|
| 城市世界总览 | iso 2:1 aerial | towers, elevated roads, seen from above-side |
| 企业核心区街道 | iso 2:1 | glass facades 4+ storeys, angled entrance canopy |
| 工业贫民区 | iso 2:1 | elevated rail on trusses, extruded shanties, chimneys |
| 娱乐地下区 | iso 2:1 | shell-roof venue, awning depth, standing lamp posts |
| 地下黑市 | iso 2:1 | ceiling ducts, stall volumes, aisles between rows |
| 潜行与黑客 | iso 2:1 | server racks with visible front faces, turret on a dais |
| 实际战斗 | iso 2:1 | containers with two lit faces, puddles reflecting signage |

The previous build rendered a **flat orthographic top-down** grid: 32×32
square tiles, no height, 3/4-view sprites on a straight-down floor plan.

Five independent reviewers scored that build 1.8–2.4 out of 4.0, and every one
named composition and depth as the cause — not tile detail. They were
describing a camera mismatch, and no amount of repainting tiles could fix it.

## Decision

Render the world isometrically at 2:1.

* `IsoGrid` — 64×32 diamond projection, world↔screen round trip, cursor picking
  with occlusion by wall height, painter's-algorithm depth key. Unit-tested
  (`tests/test_iso_grid.gd`, 18 assertions).
* `IsoWorld` — builds floor diamonds, extruded wall prisms, props and actors
  into one globally sorted draw order.
* `tools/gen_iso_tiles.py` — generates the atlas: floor diamonds in four
  material variants per district, wall prisms at three heights with lit window
  bands, extruded props. Geometry is exact pixel maths, not a general-purpose
  image tool, because a wall face is a parallelogram and drawing it as a
  rectangle produces triangular artefacts (observed, fixed, re-verified).

## Why not Godot's TileMapLayer

`TileMapLayer` is a square-grid structure. Its isometric support is at the
tile-shape level only: it gives no per-cell height, no single cross-object draw
order, and no occlusion-aware picking. Using it means fighting the engine's
sorting for every wall and actor. The custom path is ~300 lines and fully under
control.

## Consequences

* **Kept unchanged:** all gameplay logic (`src/systems`, 921 LOC) is
  projection-agnostic `RefCounted`. Content JSON, the test suite and the
  playtest harness are unaffected.
* **Replaced:** world construction and rendering.
* **New constraint:** every character, prop and wall is authored to the 2:1
  grid. Sprites face one of four isometric directions, not eight compass
  directions — the concept art shows a single 3/4-facing cast.
* **Performance:** floor tiles are individual `Sprite2D`s. At 40×40 that is
  1,600 draw items, measured fine; beyond ~80×80 a chunked renderer or
  `MultiMesh` will be required. Tracked as a scaling task, not a blocker.

## Evidence

* `evidence/iso-renderer-proof.png` — first working capture: 400 floor
  diamonds, 408 wall prism sprites, depth-sorted actors, neon props.
* `tests/test_iso_grid.gd` — 18/18 passing.
