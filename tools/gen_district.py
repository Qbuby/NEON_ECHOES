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
        "wall_h": 2.0,
    },
    "ind_belt": {
        "name": "工业贫民区",
        "tiles": "ind",
        "w": 34, "h": 34,
        "street": "vertical",
        "wall_h": 2.0,
    },
    "night_row": {
        "name": "娱乐地下区",
        "tiles": "night",
        "w": 34, "h": 34,
        "street": "vertical",
        "wall_h": 2.0,
    },
}


def build(spec):
    """A street canyon, not a plaza.

    The concept shots frame roughly 13 tiles across. A 5-tile street with
    buildings tight to both kerbs therefore fills the view with architecture
    from any position on the street, which is what the reference images do. The
    earlier 8-tile street plus a 12x11 plaza left the frame almost entirely
    empty floor.
    """
    w, h = spec["w"], spec["h"]
    g = [["#" for _ in range(w)] for _ in range(h)]
    sx0, sx1 = w // 2 - 2, w // 2 + 2          # 5-tile street
    for y in range(2, h - 2):
        for x in range(sx0, sx1 + 1):
            g[y][x] = "."
    # one cross street so the district reads as a junction, not a corridor
    cy = h // 2
    for y in range(cy - 2, cy + 3):
        for x in range(2, w - 2):
            g[y][x] = "."
    # side alleys: 1 tile wide, break the building mass and give routes
    for ay in (h // 4, (3 * h) // 4):
        for y in range(ay, ay + 2):
            for x in range(2, sx0):
                g[y][x] = "."
            for x in range(sx1 + 1, w - 2):
                g[y][x] = "."
    # a small paved pocket where the streets meet (2 tiles, not 12)
    for y in range(cy, cy + 2):
        for x in range(sx0, sx1 + 1):
            g[y][x] = "P"

    props = []
    # street furniture along both kerbs: lamps every 4 tiles, alternating with
    # bins, vending machines, terminals and crates so the street edge is busy
    edge = ["prop_lamp", "prop_bin", "prop_vending", "prop_crate",
            "prop_terminal", "prop_barrel", "prop_lamp", "prop_crate2"]
    for i, y in enumerate(range(3, h - 3, 2)):
        props.append({"id": edge[i % len(edge)], "cell": [sx0 - 1, y]})
        props.append({"id": edge[(i + 4) % len(edge)], "cell": [sx1 + 1, y + 1]})
    # barriers and planters around the junction
    for i, (x, y) in enumerate([(sx0 - 1, cy - 3), (sx1 + 1, cy + 3),
                                (sx0 - 1, cy + 3), (sx1 + 1, cy - 3)]):
        props.append({"id": "prop_barrier" if i % 2 == 0 else "prop_planter",
                      "cell": [x, y]})
    props.append({"id": "prop_bench", "cell": [sx0, cy + 1]})
    props.append({"id": "prop_kiosk", "cell": [sx1, cy - 1]})
    # signage on the facades: the frame's bright pixels come from these, and
    # the concept art always has a lit sign in view
    signs = ["sign_a", "sign_b", "sign_c"]
    for i, y in enumerate(range(4, h - 6, 6)):
        props.append({"id": signs[i % 3], "cell": [sx0 - 2, y],
                      "anchor": "mount", "lift": 28.0})
        props.append({"id": signs[(i + 1) % 3], "cell": [sx1 + 2, y + 3],
                      "anchor": "mount", "lift": 28.0})
    # set-pieces: clusters that read as a place rather than as scattered props
    for cy2 in range(6, h - 6, 9):
        # a vending nook
        props.append({"id": "prop_vending", "cell": [sx0 - 1, cy2]})
        props.append({"id": "prop_bin", "cell": [sx0 - 1, cy2 + 1]})
        props.append({"id": "prop_crate2", "cell": [sx0, cy2 + 1]})
        # a kiosk with a lamp and a bench
        props.append({"id": "prop_kiosk", "cell": [sx1 + 1, cy2 + 2]})
        props.append({"id": "prop_lamp", "cell": [sx1, cy2 + 3]})
        props.append({"id": "prop_bench", "cell": [sx1 - 1, cy2 + 3]})
        # a crate stack against the far kerb
        props.append({"id": "prop_stack", "cell": [sx1 + 1, cy2 + 5]})
        props.append({"id": "prop_crate", "cell": [sx1, cy2 + 5]})
        props.append({"id": "prop_barrel", "cell": [sx1 + 1, cy2 + 6]})
    # ground clutter: small items that break the empty paving
    for y in range(4, h - 4, 3):
        props.append({"id": "prop_crate2", "cell": [sx0 + 1, y]})
        props.append({"id": "prop_bin", "cell": [sx1 - 1, y + 1]})
    # AC units and roof clutter against the building fronts
    for y in range(4, h - 4, 5):
        props.append({"id": "prop_ac", "cell": [sx0 - 2, y]})
        props.append({"id": "prop_ac", "cell": [sx1 + 2, y + 2]})

    return {
        "name": spec["name"], "tiles": spec["tiles"],
        "w": w, "h": h,
        "floor": ["".join(r) for r in g],
        "legend": {
            ".": {"floor": "floor_b"},
            "#": {"floor": "floor_concrete", "wall": spec["wall_h"],
                  "wall_tile": "wall_h32"},
            "P": {"floor": "floor_marble"},
        },
        "props": props,
        "actors": [{"id": "player", "cell": [w // 2, h // 2 - 6]}],
    }


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for did, spec in DISTRICTS.items():
        d = build(spec)
        (OUT / f"{did}.iso.json").write_text(json.dumps(d, indent=1), encoding="utf-8")
        print(f"{did}: {d['w']}x{d['h']} props={len(d['props'])}")
