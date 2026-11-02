# NEON ECHOES — measured status

Last measured 2026-11-02. Every line below came from a command; nothing is
asserted without one.

**Overall: the architecture, renderer, asset pipeline, UI and playable loop are
rebuilt and verified, and audio and quest progression are wired to real game
events. Not yet done: three recorded playthroughs, a Windows build from the new
project, and independent visual acceptance.**

## Gates

```
bash tools/check.sh
```

| Gate | Result | What it proves |
|---|---|---|
| Projection | **18 / 18** | 2:1 world↔screen round trip, picking, depth keys |
| Acceptance suite | **74 / 74** | content counts, systems, districts, traversal, audio, assets, characters, tilesets |
| 16 screens | **20 / 20** | every screen opens with real rows; stacking; back; disabled rows refuse |
| Isometric gameplay | **13 / 13** | load, spawn, move, collide, shoot-kill, interact, quest advance, all districts |
| Audio wiring | **4 / 4** | every gameplay sound name resolves to a real WAV |
| Frame signature | **ok** | lighting matches the concept art's own statistics |

## The visual target, measured

The twelve concept images share a lighting signature. The render is compared to
it numerically by `tools/measure_frame.py`:

| | mean | p95 | bright >180 | dark <25 |
|---|---|---|---|---|
| concept range | 56–80 | 158–184 | 3–6 % | 14–27 % |
| **current render** | **66.3** | **162** | **3.1 %** | **21.3 %** |

## What exists

| Area | Count | Evidence |
|---|---|---|
| Districts | 3 × 80×80, isometric | `data/districts/*.iso.json` |
| Interiors | 12 × 30×20 | `*_lobby/office/vault/service.iso.json` |
| Interior doors | 4 per district, targeting real rooms | suite: doors ≥ 4 |
| Secrets | 5 per district, all reachable (flood-filled) | suite: traversal |
| NPCs | 10 per district | suite: npcs ≥ 10 |
| Devices | 10 per district | suite: devices ≥ 5 |
| Enemy archetypes | 6, distinct body proportions | `tools/gen_cast.py` |
| Bosses | 3 | cast |
| Player | 72 frames: 4 facings × 5 animations | `assets/actors/rin` |
| Weapons | 10 with distinct parameters | suite |
| Skills | 24 nodes, 3 trees | suite |
| Cyberware | 12 across 6 slots | suite |
| Items | 35 | suite |
| Quests | 8 main + 12 side | suite |
| Dialogue | 32 nodes, 16 choices | suite |
| Endings | 3, condition-gated | suite |
| Audio | 52 WAVs (10 gun, 5 melee, 10 skill/hack, 8 UI, 10 interaction, 6 ambience, 3 music) | suite |
| Effects | 20 generated effect bundles | suite |
| Screens | 16 | `tests/test_screens.gd` |

## Architecture

`docs/ARCHITECTURE.md` and `docs/ADR-001-isometric-renderer.md`.

The short version: the concept art is isometric 2:1 with real height; the
previous build was a flat orthographic grid. That mismatch is what five
independent reviewers were scoring 1.8–2.4. The simulation (921 LOC, pure
`RefCounted`) survived unchanged; the renderer, assets and UI were rebuilt.

## Not done

| Item | State |
|---|---|
| Three recorded playthroughs | Not recorded |
| Independent visual acceptance | **blocked**: the reviewer subagent provider rejected three requests in a row (`parameter not valid`); no verdict obtained |
| Windows build | Not produced from the new project |
| Saturation vs concept | 33 vs the concept's 37–43; value structure and highlights are in range |

These are the remaining work. The spec forbids marking the game complete while
any of them is outstanding.
