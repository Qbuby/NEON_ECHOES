# Agent development workflow

How to work on this project without re-deriving it each session.

## 1. Orient (30 seconds)

```
docs/ARCHITECTURE.md     layering, geometry constraints, depth-sort rules
evidence/STATUS.md       what passes, what fails, and why
docs/ADR-*.md            decisions already made and their reasons
```

Do not re-litigate an ADR without evidence that it is wrong.

## 2. The loop

Every change runs the same five steps. Skipping any one is how the previous
build accumulated five failed visual reviews.

| Step | Command | What it proves |
|---|---|---|
| 1 build assets | `python tools/gen_iso_tiles.py` (or props/cast/ui) | the change is generated, not hand-patched |
| 2 unit-test | `gd --headless -s tests/test_iso_grid.gd` | projection still correct |
| 3 suite | `gd --headless -s tests/run_suite.gd` | nothing regressed |
| 4 screenshot | `gd -s tests/shot_iso.gd` | it renders |
| 5 measure | `python tools/measure_frame.py game/evidence/iso_probe.png` | it matches the concept's lighting |

Screens: `gd -s tests/test_screens.gd` (20 assertions + three screenshots).

## 3. Rules that have already cost time

**GDScript**
* `var x := expr` fails on Variant. Annotate: `var x: Dictionary = ...`.
* A parameter and a member with the same name silently mis-assign. Never name a
  parameter after a member.
* `const` arrays on a script are not visible to other scripts; add a
  `static func` accessor.
* There is no `//`; use `int(a / b)`. `String(x)` is `str(x)`.
* A method that returns a callable must not shadow a member of the same type.

**Isometric geometry**
* A wall face is a parallelogram. Drawing it as a rectangle gives triangular
  artefacts.
* Only south and east faces are visible. Level layout must put detailed walls
  where the camera can see them.
* Facades are flat-topped; the roof tile supplies the diamond. Otherwise the
  roofline sawtooths.
* Every sprite must be a child of one node, or the sorted z-order is ignored.

**Assets**
* Never check in a binary without the recipe that made it.
* Palette values are the contract across tiles, props, actors and UI.
* Measure, don't judge: `tools/measure_frame.py` reports mean, p95, bright and
  dark percentages against the concept art's own numbers.

## 4. Git

Commit per coherent change, with a message that records *why* and what was
measured. Do not commit without a green suite. Push to
`github.com/Qbuby/NEON_ECHOES` through the local proxy:
`git -c http.proxy=http://127.0.0.1:7890 push`.

## 5. Where things live

```
game/            Godot project
  data/          content + district layouts
  src/systems/   pure logic (no rendering)
  src/world/     iso renderer
  src/ui/        HUD + screens
  tests/         every gate
tools/           asset generators (Python, deterministic)
evidence/        reports and screenshots
docs/            these documents
asserts/mind_map/ reference art — the visual target
```
