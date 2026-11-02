"""Generate the HUD art: portrait frame, bars, ability slots, minimap plate.

The concept combat image puts a portrait + red health bar + green bar top-left,
a minimap top-right, a second portrait + name + health bar bottom-left, an
ability bar bottom-centre with three glowing icons, and a currency counter
bottom-right. This module draws those pieces so the HUD is composed from art
rather than from engine rectangles.

Output: game/assets/ui/hud.png plus hud.json (rects).
"""
import json
import math
import pathlib
import random

from PIL import Image

OUT = pathlib.Path(__file__).resolve().parent.parent / "game" / "assets" / "ui"

# UI palette: near-black plates, cyan structure, magenta highlight, gold for
# currency. Kept small so the HUD never reads as a photograph.
PAL = {
    "void":   (7, 9, 14),
    "plate":  (16, 21, 30),
    "plate2": (24, 31, 44),
    "edge":   (42, 56, 76),
    "cyan":   (56, 216, 255),
    "cyan2":  (140, 236, 255),
    "pink":   (255, 47, 180),
    "red":    (198, 42, 62),
    "red2":   (240, 92, 110),
    "green":  (72, 200, 128),
    "gold":   (240, 200, 80),
    "white":  (238, 246, 255),
}


def plate(w, h, corner=3, accent=None):
    """A HUD plate: dark fill, 1px inner edge, clipped corners, optional accent rule."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for y in range(h):
        for x in range(w):
            cut = ((x < corner and y < corner and x + y < corner)
                   or (x >= w - corner and y < corner and (w - 1 - x) + y < corner)
                   or (x < corner and y >= h - corner and x + (h - 1 - y) < corner)
                   or (x >= w - corner and y >= h - corner
                       and (w - 1 - x) + (h - 1 - y) < corner))
            if cut:
                continue
            if x in (0, w - 1) or y in (0, h - 1):
                img.putpixel((x, y), (*PAL["void"], 255))
            elif x in (1, w - 2) or y in (1, h - 2):
                img.putpixel((x, y), (*PAL["edge"], 255))
            else:
                img.putpixel((x, y), (*PAL["plate"], 235))
    if accent:
        for x in range(2, w - 2):
            img.putpixel((x, 0), (*accent, 255))
            img.putpixel((x, 1), (*PAL["plate2"], 255))
    return img


def bar(w, h, fill, back, edge, pct=1.0, glow=None):
    """A horizontal meter: 1px frame, dark trough, gradient fill, bright cap."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for y in range(h):
        for x in range(w):
            if x in (0, w - 1) or y in (0, h - 1):
                img.putpixel((x, y), (*edge, 255))
            else:
                img.putpixel((x, y), (*back, 255))
    filled = max(0, int((w - 2) * pct))
    for y in range(1, h - 1):
        t = (y - 1) / max(1, h - 3)
        for x in range(1, 1 + filled):
            c = tuple(int(fill[i] + (back[i] - fill[i]) * t * 0.45) for i in range(3))
            img.putpixel((x, y), (*c, 255))
    if filled and glow:
        for y in range(1, h - 1):
            img.putpixel((filled, y), (*glow, 255))
    return img


def portrait(size=44):
    """A portrait frame with a character silhouette inside."""
    img = plate(size, size, corner=4, accent=PAL["pink"])
    for y in range(4, size - 4):
        for x in range(4, size - 4):
            img.putpixel((x, y), (*PAL["void"], 255))
    cx = size // 2
    for y in range(10, size - 5):
        for x in range(6, size - 6):
            dx = (x - cx) / 11.0
            dy = (y - (size - 4)) / 16.0
            if dx * dx + dy * dy <= 1.0:
                img.putpixel((x, y), (*PAL["plate2"], 255))
    for y in range(8, 21):
        for x in range(cx - 7, cx + 8):
            if (x - cx) ** 2 + (y - 14) ** 2 <= 36:
                img.putpixel((x, y), (216, 184, 168, 255))
    for y in range(7, 14):
        for x in range(cx - 8, cx + 9):
            if (x - cx) ** 2 + (y - 11) ** 2 <= 49:
                img.putpixel((x, y), (26, 22, 34, 255))
    for x in range(cx - 4, cx - 1):
        img.putpixel((x, 14), (*PAL["cyan"], 255))
    return img


def ability_slot(size=26, kind="blades"):
    """A square ability icon with a glowing glyph."""
    img = plate(size, size, corner=2, accent=PAL["cyan"])
    cx, cy = size // 2, size // 2
    if kind == "blades":
        col = PAL["cyan2"]
        for i in range(-6, 7):
            img.putpixel((cx + i, cy - 6 + abs(i) // 2), (*col, 255))
            img.putpixel((cx - i, cy + 6 - abs(i) // 2), (*col, 255))
    elif kind == "swirl":
        col = PAL["cyan"]
        for a in range(0, 360, 12):
            r = 7
            x = cx + int(r * math.cos(math.radians(a)) * 0.9)
            y = cy + int(r * math.sin(math.radians(a)) * 0.7)
            img.putpixel((x, y), (*col, 255))
    elif kind == "slash":
        col = PAL["red2"]
        for i in range(-7, 8):
            for d in (0, 1):
                y = cy + i // 3 + d
                if 0 <= y < size:
                    img.putpixel((cx + i, y), (*col, 255))
    return img


def minimap(w=68, h=52):
    """Minimap plate with a street grid and a player marker."""
    img = plate(w, h, corner=3, accent=PAL["cyan"])
    for y in range(4, h - 4):
        for x in range(4, w - 4):
            img.putpixel((x, y), (10, 26, 24, 255))
    for i in range(6, w - 6, 11):
        for y in range(4, h - 4):
            img.putpixel((i, y), (24, 62, 56, 255))
    for j in range(7, h - 6, 10):
        for x in range(4, w - 4):
            img.putpixel((x, j), (24, 62, 56, 255))
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            if abs(dx) + abs(dy) <= 2:
                img.putpixel((w // 2 + dx, h // 2 + dy), (*PAL["cyan2"], 255))
    return img


def currency_icon(size=12):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cx = size // 2
    for y in range(size):
        for x in range(size):
            if abs(x - cx) + abs(y - size // 2) <= size // 2 - 1:
                img.putpixel((x, y), (*PAL["gold"], 255))
    for y in range(3, size - 3):
        img.putpixel((cx, y), (140, 110, 30, 255))
    return img


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    tiles = [
        ("plate_small", plate(120, 34, accent=PAL["cyan"])),
        ("plate_bar", plate(150, 18, corner=2)),
        ("plate_wide", plate(300, 28, accent=PAL["pink"])),
        ("bar_hp", bar(120, 8, PAL["red"], (30, 12, 16), PAL["edge"], 1.0, PAL["red2"])),
        ("bar_hp_half", bar(120, 8, PAL["red"], (30, 12, 16), PAL["edge"], 0.55, PAL["red2"])),
        ("bar_stam", bar(120, 5, PAL["green"], (12, 30, 20), PAL["edge"], 1.0, (160, 240, 190))),
        ("bar_ram", bar(120, 5, PAL["cyan"], (10, 26, 34), PAL["edge"], 0.7, PAL["cyan2"])),
        ("portrait", portrait()),
        ("slot_blades", ability_slot(26, "blades")),
        ("slot_swirl", ability_slot(26, "swirl")),
        ("slot_slash", ability_slot(26, "slash")),
        ("minimap", minimap()),
        ("coin", currency_icon()),
    ]
    pad = 2
    cols = 5
    max_h = max(im.height for _, im in tiles) + pad
    cell_w = max(im.width for _, im in tiles) + pad
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell_w, rows * max_h), (0, 0, 0, 0))
    rects = {}
    for i, (name, im) in enumerate(tiles):
        cx = (i % cols) * cell_w
        cy = (i // cols) * max_h
        sheet.paste(im, (cx, cy), im)
        rects[name] = [cx, cy, im.width, im.height]
    sheet.save(OUT / "hud.png")
    (OUT / "hud.json").write_text(json.dumps({
        "sheet": "res://assets/ui/hud.png", "tiles": rects,
    }, indent=1), encoding="utf-8")
    print("hud: %d pieces -> %s" % (len(tiles), sheet.size))


if __name__ == "__main__":
    build()
