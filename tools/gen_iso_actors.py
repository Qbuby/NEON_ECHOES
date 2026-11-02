"""Generate isometric-facing character sprites.

Drawn at 48x64 on a 2:1 grid: a 3/4 front figure with a head, long coat and a
mechanical right arm, matching 主角 RIN 角色设计图. Four facings (s, e, n, w),
because an isometric game reads direction from the sprite's 3/4 turn.

Each sheet is a horizontal strip; the JSON beside it gives frame rects, frame
durations and the anchor (feet centre).
"""
import json
import pathlib

from PIL import Image

W, H = 48, 64
OUT = pathlib.Path(__file__).resolve().parent.parent / "game" / "assets" / "actors"

RIN = {
    "hair":   "#1a1622",
    "hair2":  "#2a2436",
    "skin":   "#d8b8a8",
    "skin2":  "#b89484",
    "coat":   "#14161f",
    "coat2":  "#1e2230",
    "cyan":   "#38d8ff",
    "pink":   "#ff2fb4",
    "steel":  "#c8d4e0",
    "steel2": "#8a99aa",
    "boot":   "#0e1018",
    "out":    "#080a10",
}


def rgba(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def draw_figure(px, pal, facing, phase, pose="idle"):
    def put(x, y, key):
        if 0 <= x < W and 0 <= y < H:
            px[x, y] = rgba(pal[key])

    def rect(x0, y0, w, h, key):
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                put(x, y, key)

    cx = 24
    swing = 0
    if pose == "walk":
        swing = 1 if phase % 2 == 0 else -1
    elif pose == "run":
        swing = 2 if phase % 2 == 0 else -2

    rect(cx - 6 + swing, 50, 4, 12, "boot")
    rect(cx + 2 - swing, 50, 4, 12, "boot")

    for i in range(26):
        y = 32 + i
        half = 8 + int(i * 0.28)
        for x in range(cx - half, cx + half):
            put(x, y, "coat")
        for x in range(cx + half - 3, cx + half):
            put(x, y, "coat2")

    rect(cx - 7, 26, 14, 8, "coat")
    rect(cx - 7, 26, 3, 8, "coat2")
    rect(cx - 6, 25, 12, 2, "cyan")
    rect(cx - 5, 14, 10, 12, "skin")
    rect(cx - 5, 14, 3, 12, "skin2")
    rect(cx - 6, 11, 12, 5, "hair")
    rect(cx - 7, 14, 4, 10, "hair")
    rect(cx + 4, 14, 2, 7, "hair2")
    put(cx + 3, 12, "pink")
    put(cx + 4, 13, "pink")
    rect(cx - 3, 19, 3, 2, "cyan")
    put(cx + 2, 19, "hair")

    if pose in ("attack", "shoot"):
        rect(cx + 7, 27, 9, 3, "steel")
        rect(cx + 15, 26, 4, 5, "steel2")
        if pose == "shoot":
            put(cx + 19, 27, "cyan")
            put(cx + 20, 27, "cyan")
    else:
        rect(cx + 7, 28, 4, 11, "steel")
        rect(cx + 7, 38, 4, 3, "steel2")
    rect(cx - 10, 28, 4, 10, "coat2")

    if facing == "n":
        rect(cx - 5, 14, 10, 12, "hair")
        rect(cx - 4, 16, 8, 3, "cyan")
        rect(cx - 3, 24, 6, 8, "coat2")
    elif facing in ("e", "w"):
        shift = 2 if facing == "e" else -2
        for y in range(11, 26):
            for x in range(cx - 8, cx + 8):
                px[x, y] = (0, 0, 0, 0)
        rect(cx - 4 + shift, 14, 8, 12, "skin")
        rect(cx - 5 + shift, 11, 9, 5, "hair")
        rect(cx - 5 + shift, 16, 3, 8, "hair")
        rect(cx + 1 + shift, 19, 2, 2, "cyan")
        if facing == "w":
            for y in range(H):
                for x in range(W // 2):
                    a = px[x, y]
                    b = px[W - 1 - x, y]
                    px[x, y] = b
                    px[W - 1 - x, y] = a

    for y in range(H):
        for x in range(W):
            if px[x, y][3] == 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < W and 0 <= ny < H) or px[nx, ny][3] == 0:
                    px[x, y] = rgba(pal["out"])
                    break


POSES = {
    "idle":   [("idle", 0), ("idle", 1)],
    "walk":   [("walk", i) for i in range(6)],
    "run":    [("run", i) for i in range(6)],
    "attack": [("attack", 0), ("attack", 1)],
    "shoot":  [("shoot", 0), ("shoot", 1)],
}
DUR = {"idle": 500, "walk": 110, "run": 80, "attack": 90, "shoot": 70}

FACINGS = ["s", "e", "n", "w"]


def build(name, pal):
    frames = []
    for facing in FACINGS:
        for anim, items in POSES.items():
            for i, (pose, phase) in enumerate(items):
                img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
                draw_figure(img.load(), pal, facing, phase, pose)
                frames.append((f"{anim}_{facing}_{i}", img, DUR[anim]))
    sheet = Image.new("RGBA", (W * len(frames), H), (0, 0, 0, 0))
    rects = {}
    for i, (fname, im, dur) in enumerate(frames):
        sheet.paste(im, (i * W, 0), im)
        rects[fname] = {"x": i * W, "y": 0, "w": W, "h": H, "duration": dur}
    d = OUT / name
    d.mkdir(parents=True, exist_ok=True)
    sheet.save(d / f"{name}.png")
    anims = {}
    for facing in FACINGS:
        for anim, items in POSES.items():
            anims[f"{anim}_{facing}"] = [f"{anim}_{facing}_{i}" for i in range(len(items))]
    (d / f"{name}.json").write_text(json.dumps({
        "sheet": f"res://assets/actors/{name}/{name}.png",
        "anchor": [W // 2, H - 2],
        "frames": rects, "animations": anims,
    }, indent=1), encoding="utf-8")
    print(f"{name}: {len(frames)} frames -> {sheet.size}")


if __name__ == "__main__":
    build("rin", RIN)
