# Visual review rounds — NEON ECHOES rebuild

Each round is one independent review of a real in-engine frame. The reviewer is
a separate agent given the image and a fixed scoring format; its verdict is
recorded as returned, including when it is wrong.

## Why earlier dispatches failed (diagnosed, not guessed)

Nine reviewer dispatches returned `Volcengine Ark: A parameter specified in the
request is not valid` with no verdict. Isolated by controlled test:

| Request | Result |
|---|---|
| text only | ok |
| text + one image, descriptive | ok |
| text + two images, descriptive | intermittently ok |
| text + one image, **asking for a 1–5 score** | fails |
| structured output with score fields | fails |
| resuming an agent that has already seen images | fails |

Two hypotheses were tested and eliminated: CJK filenames (ASCII copies failed
identically) and file size (downscaling to 480px and 270px still failed). Text
scoring without an image also succeeded.

**Conclusion, refined after four successful rounds:** the trigger is the
subagent *route*, not the prompt. `general-purpose` + image + quantitative
scoring is rejected by the gateway every time. The **`Explore`** route with the
same prompt and the same image returns a verdict reliably — it was used for
rounds 1–4 below, and succeeded every time.

One further failure mode: giving `Explore` an open-ended *measurement* task
("inspect the lattice and report the ratio") made it run 24 tool calls over 17
minutes and return nothing. It answers a scoring question well; it does not
survive an open-ended investigation prompt.

## Round 1 — after the isometric rebuild

Reviewer: Explore route, one image (480×270 combat frame).

```
projection: 3
depth: 2
art_direction: 3
finish: 2
biggest_gap: no lighting model — street lamps cast nothing, no contact shadows
             or AO, skyline same value as the floor
severity: POLISH
```

Acted on: the light node was drawing **under** the world, its additive pools
were never visible, and the first-frame redraw was dropped because `setup()`
ran before the node entered the tree.

## Round 2 — after fixing lighting draw order

```
projection: 3
depth: 2
art_direction: 3
finish: 2
biggest_gap: character sprites are placeholder-level flat silhouettes
severity: POLISH
```

Acted on: added lit/shadow sides, rim light, brow/eye/jaw separation, chest seam
and strap to the sprite pass; raised the camera from 1.35 to 1.7 so a 64px
character occupies ~20% of frame height, matching the concept.

## Round 3 — after lighting + camera

```
projection: 4
depth: 2
art_direction: 2
finish: 2
biggest_gap: no value or hue hierarchy — 90% of pixels one narrow blue band,
             additive pools produce no visible falloff
severity: STRUCTURAL
```

**This finding was correct**, and measurement confirmed it: floor mean
luminance 31.4, only 0.8% of floor pixels above 60. The light node existed with
41 lights at the right positions but `IsoWorld.sort_now()` re-appended every
managed sprite after it, so it painted behind them.

Acted on: light z_index above the sorted sprites; floors raised from near-black
to lit stone; light spill tuned. Combat frame went:
mean 35.1 → 73.8, p95 62 → 163, highlights 0.3% → 3.4%.

## Round 4 — after the lighting fix

```
projection: 2
depth: 2
art_direction: 3
finish: 2
biggest_gap: the isometric rules are never enforced — the ground is a
             screen-aligned square grid, actors are unshaded placeholder blocks
severity: STRUCTURAL
```

**The projection claim is false, and it is measurable.** A 2D autocorrelation of
a floor-only patch reports the tile lattice period as **dx = 54, dy = 27, ratio
2.00** — exactly the 2:1 isometric lattice, and impossible for a square grid,
which would give 1.00. `tests/test_iso_grid.gd` independently asserts 18
properties of the projection including the 64×32 diamond and its 2:1 symmetry.

The likely cause is the review image: a 480-wide Lanczos downscale of a 960-wide
frame blurs the diamond seams into a blur the reviewer read as square. That is a
**methodology error in my review pipeline**, not a fault in the renderer.

## Honest state

The reviewer has been wrong about projection (measurably) and right about
lighting (measurably). Both rounds are kept above rather than deleting the
unflattering verdicts.

Visual acceptance is **not passed**. No reviewer has scored the frame at 4/5.

## Round 5 — projection check, native detail

Dispatched on `Explore` with a 2x nearest-neighbour crop of the frame centre and
a single yes/no-plus-ratio question. The agent ran 24 tool calls for 17 minutes
and returned **no output**. Recorded as a failed dispatch, not a verdict.

The projection claim from round 4 was nevertheless settled directly, without a
reviewer: a 2D autocorrelation of a floor-only patch gives a lattice period of
`dx = 54, dy = 27`, ratio **2.00**. That is the 2:1 isometric lattice; a square
grid would give 1.00. The renderer is correct and the round-4 finding was an
artefact of reviewing a Lanczos-downscaled thumbnail.

## What the next round must do

1 Hand the reviewer the **native 960×540** frame, not a downscale — the grid
  and sprite detail do not survive Lanczos reduction.
2 Ask about one dimension per dispatch; multi-dimension scoring prompts are the
  ones the gateway rejects.
3 Use the **Explore** route. It is the only route that has ever returned an
   image verdict; `general-purpose` is rejected by the gateway for exactly this
   kind of request.
4 Ask one question per dispatch and keep it a judgement, not an investigation —
   an open-ended measurement prompt made the agent hang and return nothing.
