# NEON ECHOES — measured status

Last measured: 2026-11-02, after the isometric renderer rebuild.

**Overall: IN PROGRESS.** The renderer and asset pipeline are rebuilt and
verified. Content has not yet been re-authored for the new pipeline, so most
content assertions currently fail. Nothing below is marked complete without a
command that produced it.

## Passing now

| Gate | Command | Result |
|---|---|---|
| Projection maths | `gd --headless -s tests/test_iso_grid.gd` | **18 / 18** |
| Gameplay systems (logic layer) | `gd --headless -s tests/run_suite.gd` | **59 / 73** |
| Isometric renderer | `gd -s tests/shot_iso.gd` | boots, 1920×1080 |
| Frame lighting signature | `python tools/measure_frame.py` | **ok** |

Frame signature vs the concept art:

| | mean | p95 | bright>180 | dark<25 |
|---|---|---|---|---|
| concept range | 56–80 | 158–184 | 3–6% | 14–27% |
| current render | 67.6 | 162 | 3.2% | 20.4% |

## The 14 failing assertions, and why

They test the **old level format** — `assets/levels/*.json` with an 80×80
character map, 4+ doors and 5+ secrets per district, and 12 interior files. The
isometric pipeline replaced that format with `data/districts/*.iso.json`.

| Failure | Cause | Fix |
|---|---|---|
| 3 districts: 80×80 maps, doors, secrets | old level format | re-author as iso districts at spec size |
| 15+ secrets total | secrets not yet placed in the iso format | add secret entities to the district generator |
| 12 interior files exist | interiors not yet authored | generate interiors in the iso format |

These are **not** passing tests that were hidden; they are requirements that are
genuinely unbuilt in the new pipeline.

## Structural state

| Layer | State |
|---|---|
| Systems (combat, AI, stealth, hacking, progression, quests, endings, saves) | complete, untouched by the render change, 921 LOC |
| Content data (weapons, enemies, skills, cyberware, items, quests, dialogue, endings) | authored, still valid — projection-agnostic |
| Renderer | **rebuilt** as isometric 2:1, verified |
| Asset pipeline | **rebuilt**: deterministic Python, tiles / props / actors / districts |
| UI | **not rebuilt** — still the old button-list screens |
| Districts | 3 layouts at 34×34, needs to reach 80×80 with interiors |
| Character cast | 1 (RIN, 4 facings × 5 animations) |
| Playtest / recording | harness migrated, not yet re-wired to the iso scene |

## Next, in dependency order

1. Re-author the three districts at 80×80 in the iso format, with 4 interiors
   each and the required secret / interactable / NPC counts.
2. Expand the actor pipeline to the enemy and NPC casts.
3. Rebuild the HUD and the 16 screens to the concept UI language.
4. Re-point the playtest harness at the iso scene and re-run the full suite.
5. Visual acceptance with an independent reviewer.
