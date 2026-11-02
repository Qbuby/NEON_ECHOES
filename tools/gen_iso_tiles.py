"""Generate 2:1 isometric tiles: diamond floor tiles and extruded wall prisms.

The concept art is isometric with real height. A wall is a vertical prism on a
64x32 diamond footprint, so its silhouette is:

    y in [0, 16]          half-width 32*y/16      (the top diamond, widening)
    y in [16, 16+H]       half-width 32            (the extruded sides)
    y in [16+H, 32+H]     half-width tapering back in (the bottom edge)

with the left half of the body one shade darker than the right, and the top face
lighter than both. That is what reads as a solid building rather than a decal.

Outputs per district:
  <district>_iso.png     the atlas sheet
  <district>_iso.json    atlas rects for the renderer

Run:  python tools/gen_iso_tiles.py
"""
import json
import math
import pathlib
import random

from PIL import Image, ImageDraw

W, H = 64, 32          # diamond
HW, HH = 32, 16        # half extents
OUT = pathlib.Path(__file__).resolve().parent.parent / "game" / "assets" / "tiles"

# Per-district palettes, taken from the concept images.
PALETTES = {
    "corp": {
        "asphalt":  ("#151c29", "#1e2738", "#2a3549"),
        "plaza":    ("#101724", "#19222f", "#27334a"),
        "marble":   ("#0d1320", "#19202e", "#2e3d55"),
        "concrete": ("#1a2231", "#25304a", "#36445f"),
        "wall_lit": ("#25324a", "#33445f", "#465e80"),
        "wall_drk": ("#0e1420", "#161f2e", "#1f2a3c"),
        "neon":     ("#38d8ff", "#5ee0ff", "#b8f4ff"),
        "accent":   ("#ff2fb4", "#ff8ad8", "#ffd0f0"),
    },
    "ind": {
        "asphalt":  ("#1a1611", "#241d16", "#302619"),
        "plaza":    ("#171310", "#211b14", "#2c2418"),
        "marble":   ("#141009", "#1e1710", "#2b2318"),
        "concrete": ("#1c1812", "#29231a", "#372e21"),
        "wall_lit": ("#3a2f20", "#4d3f2a", "#63523a"),
        "wall_drk": ("#100c08", "#1a140e", "#241b12"),
        "neon":     ("#e8a23c", "#ffc86a", "#ffe6a8"),
        "accent":   ("#d8622a", "#ff8a44", "#ffc09a"),
    },
    "night": {
        "asphalt":  ("#150e1e", "#1f1529", "#2a1b38"),
        "plaza":    ("#120c1a", "#1b1225", "#271832"),
        "marble":   ("#0e0816", "#181021", "#251630"),
        "concrete": ("#191022", "#251631", "#322040"),
        "wall_lit": ("#3a2350", "#4d2f68", "#66417f"),
        "wall_drk": ("#0b0710", "#150d1d", "#1f1429"),
        "neon":     ("#ff2fb4", "#ff8ad8", "#ffd4ef"),
        "accent":   ("#2fb4c8", "#6ee0f0", "#c8faff"),
    },
}


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def diamond_mask():
    """(x, y) pairs inside the 64x32 diamond."""
    out = set()
    for y in range(H):
        half = int(round((W / 2) * (1.0 - abs(y - (H / 2 - 0.5)) / (H / 2 - 0.5))))
        for x in range(W):
            if abs(x - (W / 2 - 0.5)) <= half:
                out.add((x, y))
    return out


DMASK = diamond_mask()


def hex_rgb(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def shade(rgb, mul):
    return tuple(max(0, min(255, int(c * mul))) for c in rgb)


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


# ---- floor diamond -----------------------------------------------------------------

def floor_diamond(pal, rng, kind="plain"):
    """One 64x32 diamond of paving."""
    base, mid, hi = (hex_rgb(c) for c in pal)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    for y in range(H):
        half = int(round(32 * (1.0 - abs(y - 15.5) / 15.5)))
        for x in range(W):
            if abs(x - 31.5) > half:
                continue
            # base tone with a light top-left to dark bottom-right gradient:
            # the concept floors are lit from one neon source, not flat
            g = (x * 0.35 + y * 0.65) / 48.0
            t = max(0.0, min(1.0, g))
            c = mix(hi, mid, t) if t < 0.5 else mix(mid, base, (t - 0.5) * 2.0)
            px[x, y] = (*c, 255)

    if kind == "joints":
        # slab joints: a cross through the diamond at the tile's own mid-points
        for i in range(W):
            if 14 <= i <= 49:
                y = int(round(15.5 + abs(i - 31.5) * 0.5))
                if 0 <= y < H:
                    px[i, y] = (*shade(mid, 0.55), 255)
            if 14 <= i <= 49:
                y = int(round(15.5 - abs(i - 31.5) * 0.5))
                if 0 <= y < H:
                    px[i, y] = (*shade(mid, 0.62), 255)
    elif kind == "grate":
        for i in range(W):
            for y in range(H):
                if px[i, y][3] == 0:
                    continue
                if (i + y * 2) % 8 == 0 or (i - y * 2) % 8 == 0:
                    px[i, y] = (*shade(mid, 0.5), 255)
    elif kind == "speckle":
        n = vnoise_disc(rng, 7, 22)
        for i in range(W):
            for y in range(H):
                if px[i, y][3] == 0:
                    continue
                if n[y][i] > 0.68:
                    px[i, y] = (*shade(mid, 1.22), 255)

    # edge darkening: every diamond gets a 1px darker rim so the grid reads
    # without a hard black line between tiles
    for y in range(H):
        half = int(round(32 * (1.0 - abs(y - 15.5) / 15.5)))
        for x in (31 - half, 32 + half):
            if 0 <= x < W and px[x, y][3]:
                px[x, y] = (*shade(px[x, y][:3], 0.55), 255)
    return img


def vnoise_disc(rng, cells, size):
    lat = [[rng.random() for _ in range(cells)] for _ in range(cells)]
    out = [[0.0] * W for _ in range(H)]
    for y in range(H):
        fy = y * cells / H
        iy, vy = int(fy), fy - int(fy)
        vy = vy * vy * (3 - 2 * vy)
        for x in range(W):
            fx = x * cells / W
            ix, vx = int(fx), fx - int(fx)
            vx = vx * vx * (3 - 2 * vx)
            a = lat[iy % cells][ix % cells]
            b = lat[iy % cells][(ix + 1) % cells]
            c = lat[(iy + 1) % cells][ix % cells]
            d = lat[(iy + 1) % cells][(ix + 1) % cells]
            out[y][x] = (a * (1 - vx) + b * vx) * (1 - vy) + (c * (1 - vx) + d * vx) * vy
    return out


# ---- wall prism --------------------------------------------------------------------

def wall_block(pal, rng, height=32, windows=True):
    """A complete wall: top diamond + both extruded faces, 64 x (32+height).

    The faces are parallelograms: the left face spans W(0,16) -> S(32,32) ->
    S+H(32,32+H) -> W+H(0,16+H), the right face spans S -> E -> E+H -> S+H.
    Drawing them as 64-wide rectangles produced triangular artefacts.
    """
    lit, drk = pal["wall_lit"], pal["wall_drk"]
    c_top_a, c_top_b, c_top_c = (rgb(c) for c in lit)
    c_side_l, c_side_r = rgb(drk[0]), rgb(drk[1])
    out_h = H + height
    img = Image.new("RGBA", (W, out_h), (0, 0, 0, 0))
    px = img.load()

    # top face, lit from the upper left
    for (x, y) in DMASK:
        t = max(0.0, min(1.0, (x * 0.3 + y * 0.7) / 34.0))
        c = mix(c_top_c, c_top_b, t) if t < 0.55 else mix(c_top_b, c_top_a, (t - 0.55) / 0.45)
        px[x, y] = (*c, 255)

    # left face
    for yy in range(HH, HH + 16 + height):
        if yy < 32:
            edge = yy - HH
            x0, x1 = 0, edge
        else:
            x0, x1 = 0, 31
        k = min(1.0, (yy - HH) / 16.0) * 0.32
        for x in range(int(x0), int(x1) + 1):
            px[x, yy] = (*shade(c_side_l, 1.0 - k), 255)

    # right face
    for yy in range(HH, HH + 16 + height):
        if yy < 32:
            edge = yy - HH
            x0, x1 = 63 - edge, 63
        else:
            x0, x1 = 32, 63
        k = min(1.0, (yy - HH) / 16.0) * 0.32
        for x in range(int(x0), int(x1) + 1):
            px[x, yy] = (*shade(c_side_r, 1.0 - k), 255)

    if windows and height >= 24:
        win = rgb(pal["neon"][1])
        rngw = random.Random(rng.randint(0, 1 << 20))
        for row_y in range(36, 28 + height, 9):
            for face in (0, 1):
                for col in range(3):
                    if rngw.random() < 0.40:
                        continue
                    x0 = 3 + col * 9 if face == 0 else 35 + col * 9
                    for dy in range(4):
                        for dx in range(6):
                            xx, yy = x0 + dx, row_y + dy
                            if 0 <= xx < W and 0 <= yy < out_h and px[xx, yy][3]:
                                px[xx, yy] = (*shade(win, 0.62 + 0.38 * (dy / 4.0)), 255)
        strip = rgb(pal["neon"][0])
        for x in range(2, 62):
            yy = 30 + height
            if 0 <= yy < out_h and px[x, yy][3]:
                px[x, yy] = (*strip, 255)

    _outline(px, W, out_h, drk[0])
    return img


def _outline(px, w, h, dark):
    edge = rgb(dark)
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < w and 0 <= ny < h) or px[nx, ny][3] == 0:
                    px[x, y] = (*shade(edge, 0.85), 255)
                    break


def prop_block(pal, rng, w_units, h_units, kind="crate"):
    """A small extruded prop: crate, vending machine or sign post."""
    cw = int(W * w_units)
    ch = int(HH * w_units)
    height = int(HH * h_units)
    out_w, out_h = cw, ch + height
    img = Image.new("RGBA", (out_w, out_h), (0, 0, 0, 0))
    px = img.load()
    top_b, top_c = rgb(pal["wall_lit"][1]), rgb(pal["wall_lit"][2])
    side = rgb(pal["wall_drk"][1])
    face = rgb(pal["accent"][1]) if kind == "neon" else rgb(pal["wall_lit"][0])
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
                t = (x / max(1, cw)) * 0.5 + (y / max(1, ch)) * 0.5
                px[x, y] = (*mix(top_b, top_c, t), 255)
            else:
                px[x, y] = (*shade(side if x < cw / 2 else face,
                                   1.0 - 0.25 * (y - ch) / max(1, height)), 255)
    if kind == "neon":
        for y in range(ch + 3, out_h - 3):
            for x in range(cw // 4, cw - cw // 4):
                if px[x, y][3]:
                    px[x, y] = (*rgb(pal["neon"][1]), 255)
    _outline(px, out_w, out_h, pal["wall_drk"][0])
    return img


# ---- atlas assembly ------------------------------------------------------------------

def build(district, pal, out_dir):
    rng = random.Random(1000 + len(district))
    tiles = []
    # floors: four material variants per palette
    for name, kind in (("a", "plain"), ("b", "joints"), ("c", "grate"), ("d", "speckle")):
        tiles.append((f"floor_{name}", floor_diamond(pal["asphalt"], rng, kind)))
    for key in ("plaza", "marble", "concrete"):
        tiles.append((f"floor_{key}", floor_diamond(pal[key], rng, "joints")))
    # walls at three heights, with lit windows
    tiles.append(("wall_h16", wall_block(pal, rng, 16, windows=False)))
    tiles.append(("wall_h32", wall_block(pal, rng, 32, windows=True)))
    tiles.append(("wall_h48", wall_block(pal, rng, 48, windows=True)))
    tiles.append(("prop_crate", prop_block(pal, rng, 1, 1, "crate")))
    tiles.append(("prop_vend", prop_block(pal, rng, 1, 2, "neon")))
    tiles.append(("prop_sign", prop_block(pal, rng, 1, 3, "neon")))

    # lay out in a grid with 2px padding so bilinear-free sampling is safe
    pad = 2
    cols = 6
    cell_w = W + pad
    cell_h = (H + 48) + pad
    rows = math.ceil(len(tiles) / cols)
    sheet = Image.new("RGBA", (cols * cell_w, rows * cell_h), (0, 0, 0, 0))
    rects = {}
    for i, (name, im) in enumerate(tiles):
        cx = (i % cols) * cell_w
        cy = (i // cols) * cell_h
        # bottom-align every tile inside its cell so wall bases share a baseline
        sheet.paste(im, (cx, cy + cell_h - pad - im.height), im)
        rects[name] = [cx, cy + cell_h - pad - im.height, im.width, im.height]

    out_dir.mkdir(parents=True, exist_ok=True)
    sheet.save(out_dir / f"{district}_iso.png")
    (out_dir / f"{district}_iso.json").write_text(json.dumps(
        {"sheet": f"res://assets/tiles/{district}_iso/{district}_iso.png",
         "tile_w": W, "tile_h": H, "tiles": rects}, indent=1), encoding="utf-8")
    print(f"{district}: {len(tiles)} tiles -> {sheet.size}")


if __name__ == "__main__":
    for district, pal in PALETTES.items():
        build(district, pal, OUT / f"{district}_iso")
