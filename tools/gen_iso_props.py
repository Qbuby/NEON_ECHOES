"""Generate isometric street furniture: bins, barriers, lamps, terminals,
crates, planters, AC units, signage and barrel stacks.

Each prop is a small extruded prism with a lit detail, drawn to the same 2:1
grid as the walls so it sits on a diamond correctly. Sizes are in tile units
(1.0 = one 64x32 diamond footprint).
"""
import json
import pathlib
import random

from PIL import Image

W, H = 64, 32
HW, HH = 32, 16
OUT = pathlib.Path(__file__).resolve().parent.parent / "game" / "assets" / "tiles"

PAL = {
    "corp": {
        "body":  ("#1c2432", "#2a3548", "#3c4a63"),
        "dark":  ("#0c1119", "#141b26", "#1e2836"),
        "neon":  ("#38d8ff", "#6ee4ff", "#c0f6ff"),
        "accent": ("#ff2fb4", "#ff8ad8", "#ffd4ef"),
        "metal": ("#5c6a80", "#8b9ab0", "#c8d6e6"),
    },
    "ind": {
        "body":  ("#241c12", "#33291b", "#463824"),
        "dark":  ("#100c08", "#191309", "#231a0f"),
        "neon":  ("#e8a23c", "#ffc86a", "#ffe6a8"),
        "accent": ("#d8622a", "#ff8a44", "#ffc09a"),
        "metal": ("#5a5248", "#847a6c", "#b6ac9c"),
    },
    "night": {
        "body":  ("#241432", "#33204a", "#452c60"),
        "dark":  ("#0c0712", "#160e1e", "#20132c"),
        "neon":  ("#ff2fb4", "#ff8ad8", "#ffd4ef"),
        "accent": ("#2fb4c8", "#6ee0f0", "#c8faff"),
        "metal": ("#5e4a70", "#8a72a0", "#c0aad4"),
    },
}


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def shade(c, m):
    return tuple(max(0, min(255, int(v * m))) for v in c)


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def prism(pal, w_units, h_units, seed, detail=None):
    """A box: w_units wide, h_units tall, footprint on the 2:1 diamond."""
    rng = random.Random(seed)
    cw = max(8, int(W * w_units))
    ch = max(6, int(HH * w_units))
    height = max(4, int(HH * h_units))
    out_w, out_h = cw, ch + height
    img = Image.new("RGBA", (out_w, out_h), (0, 0, 0, 0))
    px = img.load()
    top_b, top_c = rgb(pal["body"][1]), rgb(pal["body"][2])
    side_l, side_r = rgb(pal["dark"][0]), rgb(pal["body"][0])
    for y in range(out_h):
        if y < ch:
            half = int(round((cw / 2) * (1.0 - abs(y - (ch / 2 - 0.5)) / (ch / 2 - 0.5))))
        elif y < ch + height:
            half = cw // 2
        else:
            half = 0
        for x in range(out_w):
            if abs(x - (cw / 2 - 0.5)) > half:
                continue
            if y < ch:
                t = (x / max(1, cw)) * 0.45 + (y / max(1, ch)) * 0.55
                px[x, y] = (*mix(top_b, top_c, t), 255)
            else:
                px[x, y] = (*shade(side_l if x < cw / 2 else side_r,
                                   1.0 - 0.22 * (y - ch) / max(1, height)), 255)
    if detail == "panel":
        # a lit screen or vending face on the front
        col = rgb(pal["neon"][1])
        for y in range(ch + 2, out_h - 2):
            for x in range(max(1, cw // 5), min(out_w - 1, cw - cw // 5)):
                if px[x, y][3] and rng.random() > 0.12:
                    px[x, y] = (*shade(col, 0.75 + 0.25 * rng.random()), 255)
    elif detail == "stripes":
        # hazard striping along the front face
        for y in range(ch + 1, out_h - 1):
            for x in range(out_w):
                if px[x, y][3] and (x + y) % 6 < 3:
                    px[x, y] = (*rgb(pal["accent"][1]), 255)
    elif detail == "windows":
        col = rgb(pal["neon"][1])
        for ry in range(ch + 3, out_h - 3, 5):
            for rx in range(3, out_w - 3, 6):
                for dy in range(2):
                    for dx in range(3):
                        if 0 <= rx + dx < out_w and 0 <= ry + dy < out_h and px[rx + dx, ry + dy][3]:
                            px[rx + dx, ry + dy] = (*shade(col, 0.8), 255)
    elif detail == "lid":
        for x in range(out_w):
            if ch - 1 < out_h and px[x, ch - 1][3]:
                px[x, ch - 1] = (*rgb(pal["metal"][1]), 255)
    # silhouette outline
    edge = rgb(pal["dark"][0])
    for y in range(out_h):
        for x in range(out_w):
            if px[x, y][3] == 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < out_w and 0 <= ny < out_h) or px[nx, ny][3] == 0:
                    px[x, y] = (*shade(edge, 0.85), 255)
                    break
    return img


PROPS = {
    # name: (width tiles, height tiles, detail)
    "prop_crate":  (0.9, 1.0, None),
    "prop_crate2": (0.7, 0.7, None),
    "prop_barrel": (0.6, 1.1, "lid"),
    "prop_bin":    (0.8, 1.2, "lid"),
    "prop_vending": (0.9, 2.0, "panel"),
    "prop_terminal": (0.8, 1.4, "panel"),
    "prop_barrier": (1.4, 0.7, "stripes"),
    "prop_planter": (1.0, 0.8, "lid"),
    "prop_ac":     (1.0, 1.2, "windows"),
    "prop_kiosk":  (1.2, 1.8, "panel"),
    "prop_stack":  (0.8, 1.6, None),
    "prop_bench":  (1.4, 0.35, "lid"),
}


def lamp(pal, seed):
    """A street lamp: a tapered post with a glowing head on a short arm.

    The post must reach the head: the first version left a gap and the glow
    read as a diamond floating in the air.
    """
    cw, ch = 16, 8
    height = 58
    out_w, out_h = cw, ch + height
    img = Image.new("RGBA", (out_w, out_h), (0, 0, 0, 0))
    px = img.load()
    post = rgb(pal["metal"][0])
    post_hi = rgb(pal["metal"][1])
    # base: a small diamond foot on the tile
    for y in range(ch - 4, ch):
        half = int(round(6 * (1.0 - abs(y - (ch - 4)) / 4.0)))
        for x in range(8 - half, 8 + half):
            px[x, y] = (*rgb(pal["dark"][1]), 255)
    # post, 2px wide with a lit edge, from the foot to the head
    for y in range(6, ch + 2):
        px[7, y] = (*post, 255)
        px[8, y] = (*post_hi, 255)
    # head: a lamp housing on an arm at the top
    for y in range(2, 10):
        for x in range(4, 13):
            if abs(x - 8) + abs(y - 5) <= 5:
                px[x, y] = (*rgb(pal["dark"][1]), 255)
    glow = rgb(pal["neon"][2])
    for y in range(6, 12):
        for x in range(5, 12):
            d = abs(x - 8) + abs(y - 8)
            if d <= 3:
                px[x, y] = (*shade(glow, 1.0 - d * 0.13), 255)
    edge = rgb(pal["dark"][0])
    for y in range(out_h):
        for x in range(out_w):
            if px[x, y][3] == 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < out_w and 0 <= ny < out_h) or px[nx, ny][3] == 0:
                    px[x, y] = (*shade(edge, 0.9), 255)
                    break
    return img


def build(district, pal):
    tiles = []
    for i, (name, (wu, hu, det)) in enumerate(PROPS.items()):
        tiles.append((name, prism(pal, wu, hu, 900 + i, det)))
    tiles.append(("prop_lamp", lamp(pal, 1)))
    tiles.append(("prop_lamp2", lamp(pal, 2)))

    pad = 2
    cols = 6
    max_h = max(im.height for _, im in tiles) + pad
    cell_w = max(im.width for _, im in tiles) + pad
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell_w, rows * max_h), (0, 0, 0, 0))
    rects = {}
    for i, (name, im) in enumerate(tiles):
        cx = (i % cols) * cell_w + (cell_w - pad - im.width) // 2
        cy = (i // cols) * max_h + max_h - pad - im.height
        sheet.paste(im, (cx, cy), im)
        rects[name] = [cx, cy, im.width, im.height]

    d = OUT / f"{district}_props"
    d.mkdir(parents=True, exist_ok=True)
    sheet.save(d / f"{district}_props.png")
    (d / f"{district}_props.json").write_text(json.dumps({
        "sheet": f"res://assets/tiles/{district}_props/{district}_props.png",
        "tile_w": W, "tile_h": H, "tiles": rects,
    }, indent=1), encoding="utf-8")
    print(f"{district}: {len(tiles)} props -> {sheet.size}")


if __name__ == "__main__":
    for district, pal in PAL.items():
        build(district, pal)
