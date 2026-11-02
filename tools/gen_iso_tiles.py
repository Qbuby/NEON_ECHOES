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
        "asphalt":  ("#080b12", "#111722", "#1d2736"),
        "plaza":    ("#060910", "#0e1420", "#1a2432"),
        "marble":   ("#070a12", "#101724", "#1f2a3c"),
        "concrete": ("#0b1018", "#161f2c", "#26334a"),
        # roof (brightest) / south face (mid) / east face (darkest)
        "wall_lit": ("#5a7699", "#7492b4", "#93b2d0"),
        "wall_drk": ("#2e4160", "#3d5578", "#4e6a92"),
        "neon":     ("#18c8f0", "#8cf0ff", "#ffffff"),
        "accent":   ("#ff1493", "#ff5cc0", "#ffc4ea"),
    },
    "ind": {
        "asphalt":  ("#0a0806", "#14100b", "#211a12"),
        "plaza":    ("#080605", "#110e0a", "#1d1710"),
        "marble":   ("#080605", "#120e09", "#1e1811"),
        "concrete": ("#0d0a07", "#18130d", "#281f15"),
        "wall_lit": ("#8a7050", "#a98a62", "#c4a67c"),
        "wall_drk": ("#4a3a26", "#5e4a30", "#755c3c"),
        "neon":     ("#f08a10", "#ffc040", "#fff8e0"),
        "accent":   ("#e04a10", "#ff7028", "#ffb080"),
    },
    "night": {
        "asphalt":  ("#08050c", "#110a18", "#1c1226"),
        "plaza":    ("#060409", "#0d0813", "#181022"),
        "marble":   ("#060409", "#0e0915", "#1a1124"),
        "concrete": ("#0a0610", "#140d1c", "#22172e"),
        "wall_lit": ("#7a5598", "#986db8", "#b58cd2"),
        "wall_drk": ("#3a2450", "#4c3068", "#603f80"),
        "neon":     ("#ff1090", "#ff70c8", "#ffffff"),
        "accent":   ("#10c0e0", "#50dcf4", "#b8f6ff"),
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


def noise(rng, cells):
    """Smooth value noise sampled over the 64x32 diamond, keyed by (x, y)."""
    lat = [[rng.random() for _ in range(cells)] for _ in range(cells)]
    out = {}
    for y in range(H):
        for x in range(W):
            fx, fy = x * cells / W, y * cells / H
            ix, iy = int(fx), int(fy)
            vx, vy = fx - ix, fy - iy
            vx = vx * vx * (3 - 2 * vx)
            vy = vy * vy * (3 - 2 * vy)
            a = lat[iy % cells][ix % cells]
            b = lat[iy % cells][(ix + 1) % cells]
            c = lat[(iy + 1) % cells][ix % cells]
            d = lat[(iy + 1) % cells][(ix + 1) % cells]
            out[(x, y)] = (a * (1 - vx) + b * vx) * (1 - vy) + (c * (1 - vx) + d * vx) * vy
    return out


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


# ---- wall pieces ---------------------------------------------------------------------

def roof_tile(pal, rng, windows=False):
    """The top diamond of a building: a flat roof with parapet detail."""
    lit, drk = pal["wall_lit"], pal["wall_drk"]
    c_a, c_b, c_c = (rgb(c) for c in lit)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    n = noise(rng, 4)
    for (x, y) in DMASK:
        t = max(0.0, min(1.0, (x * 0.35 + y * 0.65) / 40.0))
        c = mix(c_c, c_b, t * 1.6) if t < 0.6 else mix(c_b, c_a, (t - 0.6) / 0.4)
        if n[(x, y)] > 0.80:
            c = shade(c, 0.88)
        px[x, y] = (*c, 255)
    # parapet: a 1px darker rim all the way round the roof
    for (x, y) in DMASK:
        if (x + 1, y) not in DMASK or (x - 1, y) not in DMASK or            (x, y + 1) not in DMASK or (x, y - 1) not in DMASK:
            px[x, y] = (*shade(rgb(lit[1]), 0.72), 255)
    return img


def south_face(pal, rng, height=32, windows=True):
    """The face that hangs from the diamond's two lower edges (the near side)."""
    lit, drk = pal["wall_lit"], pal["wall_drk"]
    # south face sits between the bright roof and the shadowed east face
    body = rgb(mix(rgb(drk[2]), rgb(lit[0]), 0.55)) if False else rgb(drk[2])
    body_l = rgb(drk[1])
    img = Image.new("RGBA", (W, H + height), (0, 0, 0, 0))
    px = img.load()
    # The face is bounded above by the diamond's lower half and below by the
    # same shape shifted down by `height`. Row y in [16, 16+height] spans the
    # full 64 px; the top 16 rows only fill the widening lower V of the diamond.
    # Flat-topped facade: rows 0..H are the *lower* half of the diamond only,
    # so the tile's own silhouette is a rectangle topped by a V. The roof tile
    # supplies the upper half, and adjacent facades then meet in a straight line
    # instead of a sawtooth.
    for y in range(H + height):
        if y < H:
            half = int(round(HW * (y / float(HH - 1))))
            x0, x1 = HW - half - 1, HW + half
            if y < HH:
                continue
        else:
            x0, x1 = 0, W - 1
        k = min(1.0, max(0.0, (y - HH) / float(max(1, height)))) * 0.18
        for x in range(max(0, x0), min(W, x1 + 1)):
            c = body_l if x < HW else body
            px[x, y] = (*shade(c, 1.0 - k), 255)
    if windows and height >= 20:
        win = rgb(pal["neon"][1])
        rngw = random.Random(rng.randint(0, 1 << 20))
        # floor pitch: fixed 16px storeys measured from the base, so every
        # facade in the city shares a storey height
        floors = max(1, (height - 4) // 16)
        for f in range(floors):
            row_y = H + height - 20 - f * 16
            for col in range(5):
                if rngw.random() < 0.22:
                    continue
                x0 = 3 + col * 12
                for dy in range(7):
                    for dx in range(9):
                        xx, yy = x0 + dx, row_y + dy
                        if 0 <= xx < W and 0 <= yy < H + height and px[xx, yy][3]:
                            px[xx, yy] = (*shade(win, 0.58 + 0.42 * (dy / 5.0)), 255)
        # a thin bloom line just below each window row
        bloom = rgb(pal["neon"][2])
        for f in range(floors):
            row_y = H + height - 20 - f * 16
            for xx in range(3, W - 3):
                yy = row_y + 5
                if 0 <= yy < H + height and px[xx, yy][3]:
                    px[xx, yy] = (*mix(px[xx, yy][:3], bloom, 0.50), 255)
        # a lit shopfront band along the base
        band = rgb(pal["neon"][1])
        for x in range(2, W - 2):
            for yy in (H + height - 6, H + height - 5, H + height - 4, H + height - 3):
                if px[x, yy][3]:
                    px[x, yy] = (*band, 255)
    # base AO: buildings must meet the ground, not hover over it
    for k2 in range(3):
        yy = H + height - 1 - k2
        for x in range(W):
            if 0 <= yy < H + height and px[x, yy][3]:
                px[x, yy] = (*shade(px[x, yy][:3], 0.55 - k2 * 0.12), 255)
    _outline_partial(px, W, H + height, drk[0], top_open=True)
    return img


def east_face(pal, rng, height=32, windows=True):
    """The face on the right-hand edge: narrower, in shadow."""
    drk = pal["wall_drk"]
    body = rgb(drk[0])
    img = Image.new("RGBA", (W, H + height), (0, 0, 0, 0))
    px = img.load()
    for y in range(H + height):
        if y < H:
            # right side of the diamond: from the centre column out to E
            half = int(round(HW * (1.0 - abs(y - (HH - 0.5)) / (HH - 0.5))))
            x0, x1 = HW, HW + half
        else:
            x0, x1 = HW, W - 1
        k = min(1.0, max(0.0, (y - HH) / float(max(1, height)))) * 0.16
        for x in range(max(0, x0), min(W, x1 + 1)):
            px[x, y] = (*shade(body, 1.0 - k), 255)
    if windows and height >= 20:
        win = rgb(pal["neon"][1])
        rngw = random.Random(rng.randint(0, 1 << 20))
        for row_y in range(H - 4, H + height - 8, 10):
            for col in range(2):
                if rngw.random() < 0.45:
                    continue
                x0 = 36 + col * 12
                for dy in range(4):
                    for dx in range(6):
                        xx, yy = x0 + dx, row_y + dy
                        if 0 <= xx < W and 0 <= yy < H + height and px[xx, yy][3]:
                            px[xx, yy] = (*shade(win, 0.42 + 0.30 * (dy / 4.0)), 255)
    _outline_partial(px, W, H + height, drk[0], top_open=True)
    return img


def _outline_partial(px, w, h, dark, top_open=False):
    """Outline a face on its silhouette, skipping the top edge that meets the roof."""
    edge = rgb(dark)
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if top_open and dy < 0:
                    continue
                nx, ny = x + dx, y + dy
                if not (0 <= nx < w and 0 <= ny < h) or px[nx, ny][3] == 0:
                    px[x, y] = (*shade(edge, 0.85), 255)
                    break


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

def build(district, pal):
    rng = random.Random(1000 + len(district))
    tiles = []
    for name, kind in (("a", "plain"), ("b", "joints"), ("c", "grate"), ("d", "speckle")):
        tiles.append((f"floor_{name}", floor_diamond(pal["asphalt"], rng, kind)))
    for key in ("plaza", "marble", "concrete"):
        tiles.append((f"floor_{key}", floor_diamond(pal[key], rng, "joints")))
    # building pieces, composed by the renderer from the map's neighbour test
    tiles.append(("roof", roof_tile(pal, rng)))
    tiles.append(("face_s", south_face(pal, rng, 96, True)))
    tiles.append(("face_e", east_face(pal, rng, 96, True)))
    tiles.append(("face_s_low", south_face(pal, rng, 48, False)))
    tiles.append(("face_e_low", east_face(pal, rng, 48, False)))
    tiles.append(("face_s_tall", south_face(pal, rng, 144, True)))
    tiles.append(("face_e_tall", east_face(pal, rng, 144, True)))

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

    d = OUT / f"{district}_iso"
    d.mkdir(parents=True, exist_ok=True)
    sheet.save(d / f"{district}_iso.png")
    (d / f"{district}_iso.json").write_text(json.dumps({
        "sheet": f"res://assets/tiles/{district}_iso/{district}_iso.png",
        "tile_w": W, "tile_h": H, "tiles": rects,
    }, indent=1), encoding="utf-8")
    print(f"{district}: {len(tiles)} tiles -> {sheet.size}")


if __name__ == "__main__":
    for district, pal in PALETTES.items():
        build(district, pal)
