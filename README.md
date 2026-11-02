# NEON ECHOES

A top-down/2.5D isometric pixel-art cyberpunk action RPG built in Godot 4.

Original world, story, characters, art and audio. Inspired by the *feel* of
CD Projekt Red's *Cyberpunk 2077*; no copyrighted content is reproduced.

## Layout

```
game/            Godot project (open game/project.godot)
  src/systems/   Pure gameplay logic (RefCounted, engine-independent, unit-tested)
  src/world/     Scene construction and rendering
  src/ui/        HUD and screens
  src/autoload/  Cross-cutting services (log, state, audio, playtest, ux probe)
  data/          Authored content: weapons, enemies, skills, quests, dialogue…
  tests/         Headless acceptance suite, playthroughs, perf, soak
assets/          Art and audio sources + generated output
tools/           Asset pipeline and automation
evidence/        Test reports, screenshots, review records
docs/            Architecture decisions, art direction, workflow
asserts/mind_map Reference concept art (visual direction only)
```

## Status

See `evidence/STATUS.md` for the current measured state of every acceptance
requirement. Nothing is marked complete without a test result and an artifact.
