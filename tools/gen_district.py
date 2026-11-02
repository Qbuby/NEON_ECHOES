"""Compose one playable isometric district: street, buildings, props, lamps.

Writes game/data/districts/<id>.iso.json, the level description IsoWorld reads:

    {"w":.., "h":.., "floor":[row strings], "legend":{...},
     "props":[{"id":"prop_vending","cell":[x,y]}],
     "actors":[{"id":"player","cell":[x,y]}]}

The generator is rule-based, not random: a street runs through the district,
buildings line both sides at a chosen height, and street furniture is placed
where a city would actually put it (lamps at intervals, bins by doors,
vending machines at storefronts, barriers at crossings).
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "game" / "data" / "districts"

DISTRICTS = {
    "corp_core": {
        "name": "企业核心区",
        "tiles": "corp",
        "w": 34, "h": 34,
        "street": "vertical",       # a north-south street through the middle
        "wall_h": 5.0,
    },
    "ind_belt": {
        "name": "工业贫民区",
        "tiles": "ind",
        "w": 34, "h": 34,
        "street": "vertical",
        "wall_h": 5.0,
    },
    "night_row": {
        "name": "娱乐地下区",
        "tiles": "night",
        "w": 34, "h": 34,
        "street": "vertical",
        "wall_h": 5.0,
    },
}


def build(spec):
    """A plaza with a detailed building wall on one side, matching the reference.

    In a 2:1 isometric view only the south and east faces of a block are
    visible. A north-south street therefore shows facades on its west side only:
    buildings east of it turn their hidden west side to the street and present a
    bare roof. Every concept image handles this the same way -- 企业核心区街道
    has detailed facades on the left and back with an open walkway to the right,
    工业贫民区 has the wall on the left and roofline clutter on the right.

    So: tall buildings along the west edge and the north edge (their east and
    south faces are both visible and face the open space), and a low-roofed
    service strip with AC units and containers along the east edge.
    """
    w, h = spec["w"], spec["h"]
    g = [["." for _ in range(w)] for _ in range(h)]
    # open plaza: everything walkable by default
    # tall building mass: west band, and the north band
    for y in range(h):
        for x in range(0, 7):
            g[y][x] = "#"
    for y in range(0, 7):
        for x in range(0, w):
            g[y][x] = "#"
    # a second tower footprint, detached, so the skyline has a gap and a corner
    for y in range(9, 20):
        for x in range(0, 5):
            g[y][x] = "#"
    # low service strip along the east edge (roofs + clutter, no tall wall)
    for y in range(7, h - 3):
        for x in range(w - 5, w):
            g[y][x] = "#"
    # south edge: a low wall so the plaza is enclosed
    for y in range(h - 3, h):
        for x in range(5, w - 5):
            g[y][x] = "#"

    props = []
    # street furniture across the open plaza, clustered into set-pieces
    for i, y in enumerate(range(9, h - 6, 5)):
        props.append({"id": "prop_lamp", "cell": [8, y]})
        props.append({"id": "prop_bench", "cell": [9, y]})
        props.append({"id": "prop_planter", "cell": [10, y]})
        props.append({"id": "prop_bin", "cell": [11, y + 1]})
        props.append({"id": "prop_vending", "cell": [w - 6, y]})
        props.append({"id": "prop_terminal", "cell": [w - 6, y + 2]})
        props.append({"id": "prop_crate", "cell": [w - 7, y + 1]})
        props.append({"id": "prop_barrel", "cell": [w - 7, y + 3]})
    # a kiosk cluster in the middle of the plaza
    props.append({"id": "prop_kiosk", "cell": [16, 16]})
    props.append({"id": "prop_lamp", "cell": [15, 17]})
    props.append({"id": "prop_bench", "cell": [17, 17]})
    props.append({"id": "prop_barrier", "cell": [16, 15]})
    # signage mounted on the west wall, facing the plaza (east face is visible)
    signs = ["sign_a", "sign_b", "sign_c"]
    for i, y in enumerate(range(8, h - 6, 6)):
        props.append({"id": signs[i % 3], "cell": [7, y],
                      "anchor": "mount", "lift": 40.0})
    # rooftop clutter on the low east strip
    for y in range(8, h - 4, 3):
        props.append({"id": "prop_ac", "cell": [w - 3, y], "anchor": "roof"})
        props.append({"id": "prop_ac", "cell": [w - 4, y + 1], "anchor": "roof"})
    # rooftop clutter on the tall towers
    for y in range(1, 6, 2):
        for x in range(1, 6, 2):
            props.append({"id": "prop_ac", "cell": [x, y], "anchor": "roof"})

    return {
        "name": spec["name"], "tiles": spec["tiles"],
        "w": w, "h": h,
        "floor": ["".join(r) for r in g],
        "legend": {
            ".": {"floor": "floor_b"},
            "#": {"floor": "floor_concrete", "wall": 5.0},
        },
        "props": props,
        "actors": [{"id": "player", "cell": [9, 9]}],
    }


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for did, spec in DISTRICTS.items():
        d = build(spec)
        (OUT / f"{did}.iso.json").write_text(json.dumps(d, indent=1), encoding="utf-8")
        print(f"{did}: {d['w']}x{d['h']} props={len(d['props'])}")
