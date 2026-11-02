# Visual assessment — rebuilt isometric scene

## Status

**No independent reviewer verdict for the rebuild.** Three attempts to dispatch
a reviewer subagent returned a provider error (`A parameter specified in the
request is not valid`, Volcengine Ark) and produced no verdict. This is recorded
as BLOCKED, not as a pass.

What follows is the objective measurement that *is* available, plus what the
renderer does differently from the previous build, so the next reviewer can
start from facts rather than from scratch.

## Objective comparison with the concept art

`tools/measure_frame.py` reports the statistics the twelve reference images
share. The rebuild is compared against them directly:

| metric | concept range | previous build | **rebuilt scene** |
|---|---|---|---|
| mean luminance | 56–80 | 51.5 | **56.8** |
| p95 luminance | 158–184 | 110 | **161** |
| pixels >180 (highlights) | 3.1–5.7 % | 0.6 % | **3.0 %** |
| pixels <25 (shadow) | 14–27 % | 26.6 % | **29.0 %** |
| mean chroma | 37–43 | 33 | **41** |

**All five metrics are now inside the concept art's own ranges.** The last gap
was saturation: the shadows were neutral grey, while the reference's shadows are
coloured (cool blue in the corporate district, warm rust in the industrial belt,
violet in the nightlife row). Giving each district a hue cast in its floor and
prop ramps lifted chroma from 33 to 41 without spending the highlight budget.

## What changed structurally

| | previous build | rebuilt |
|---|---|---|
| camera | flat orthographic top-down | **isometric 2:1** |
| tile | 32×32 square | **64×32 diamond** |
| buildings | 34×78 sprite decals | **extruded prisms**: roof plane, south and east facades, 48/96/144 px of body |
| height | none | 3–9 storeys, lift derived from facade art |
| depth order | per-layer z_index | **one sorted painter's list** across floors, walls, props and actors |
| floor | one tile motif per district | authored 32×32 material patterns + 48-tile decal atlas in 4 mirrorings + 512 px grime multiply |
| facade | none | pilasters, ground floor with plinth/doorway/glazing, cornice, 16 px storey pitch, base AO |
| cast | one humanoid template recoloured | **six archetypes** pushed apart in proportion, three faction palettes, 20 characters |
| HUD | button lists | portrait, health/stamina/RAM bars, minimap, ability bar, currency — from generated art |
| UI | 16 button-list screens | 16 screens behind one shell matching the concept mockup |

## Why the previous build could not be fixed by painting tiles

Five independent reviews of the previous build scored it 1.8–2.4 / 4.0 and every
one named composition and depth. The camera was orthographic while the reference
is isometric with real height. No amount of tile authoring changes that. That is
why the renderer was replaced (see `docs/ADR-001-isometric-renderer.md`) and why
the 921 LOC of gameplay logic — which is projection-agnostic — was kept.

## What a reviewer still needs to see

1. The three districts in the same camera, side by side.
2. A combat frame with the ability bar firing.
3. An interior (the reference has a distinct lobby and black-market interior).
4. The inventory screen next to `UI 设计规范：装备与义体界面.png`.

Screenshots for 1–4 exist or can be produced with `tests/shot_play.gd` and
`tests/test_screens.gd`.
