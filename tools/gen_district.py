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
        "stem": "corp_core",
        "tiles": "corp",
        "w": 80, "h": 80,
        "street": "vertical",       # a north-south street through the middle
        "wall_h": 5.0,
    },
    "ind_belt": {
        "name": "工业贫民区",
        "stem": "ind_belt",
        "tiles": "ind",
        "w": 80, "h": 80,
        "street": "vertical",
        "wall_h": 5.0,
    },
    "night_row": {
        "name": "娱乐地下区",
        "stem": "night_row",
        "tiles": "night",
        "w": 80, "h": 80,
        "street": "vertical",
        "wall_h": 5.0,
    },
}


def build(spec, did):
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
    # free-standing blocks inside the plaza: without these the middle of the map
    # is 60 tiles of empty floor and any camera there frames nothing
    # spread on a ~14-tile pitch so no camera position is more than a few tiles
    # from a facade, matching the density of the concept city overviews
    for bx, by, bw, bh in ((14, 12, 7, 8), (26, 14, 8, 9), (44, 12, 8, 8),
                           (58, 20, 7, 9), (22, 30, 8, 8), (40, 30, 9, 8),
                           (12, 34, 7, 9), (52, 44, 8, 7), (24, 46, 7, 10),
                           (40, 46, 8, 7), (14, 52, 8, 8), (34, 60, 9, 7),
                           (56, 58, 7, 8), (12, 66, 7, 8), (44, 66, 8, 7),
                           (64, 34, 7, 7), (60, 64, 8, 7), (28, 24, 6, 7)):
        for y in range(by, min(h - 4, by + bh)):
            for x in range(bx, min(w - 6, bx + bw)):
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
        "id": did,
        "doors": _doors(spec, did, w, h),
        "secrets": _secrets(spec, did, w, h),
        "npcs": _npcs(spec, did, w, h),
        "interactables": _interactables(spec, did, w, h),
    }


## ---- entity layer ------------------------------------------------------------
# Every district carries four enterable interiors, five secrets, ten NPCs and
# ten interactable devices. Positions are rule-based: secrets sit against the
# walls and in the alley mouths, NPCs along the plaza, devices against facades.

INTERIORS = ["lobby", "office", "vault", "service"]


def _doors(spec, did, w, h):
    """Four interior doors on the west wall, spread down the plaza."""
    out = []
    for i, kind in enumerate(INTERIORS):
        out.append({
            "id": f"{did}_{kind}",
            "cell": [7, 12 + i * 15],
            "target": f"{spec['stem']}_{kind}",
            "spawn": "entry",
            "prompt": kind.upper(),
        })
    return out


def _secrets(spec, did, w, h):
    """Five caches: alley mouths, wall corners, and the far end of the plaza."""
    # every cell below is verified walkable by the traversal test
    cells = [(8, h - 6), (w - 6, 20), (9, 30), (w - 7, h - 4), (12, h - 5)]
    return [{"id": f"{did}_cache_{i+1}", "cell": c,
             "item": "cred_medium" if i % 2 == 0 else "cred_small"}
            for i, c in enumerate(cells)]


def _npcs(spec, did, w, h):
    """Ten townsfolk standing along the plaza and beside the kiosks."""
    cells = [(9, 12), (10, 20), (12, 26), (14, 18), (16, 30),
             (18, 22), (20, 34), (22, 16), (w - 8, 20), (w - 8, 32)]
    names = ["npc_fixer", "npc_techie", "npc_bartender", "npc_guard",
             "npc_medic", "npc_dealer", "npc_journalist", "npc_netrunner",
             "npc_landlord", "npc_curator"]
    return [{"id": names[i], "cell": c} for i, c in enumerate(cells)]


def _interactables(spec, did, w, h):
    """Ten devices: terminals, vending, scanners and cameras along the facade."""
    kinds = ["terminal", "vending", "scanner_gate", "camera", "atm",
             "hack_terminal", "jukebox", "bar_counter", "server_rack", "alarm_panel"]
    cells = [(8, 10), (8, 16), (8, 22), (8, 28), (8, 34),
             (8, 40), (w - 6, 14), (w - 6, 22), (w - 6, 30), (w - 6, 38)]
    return [{"kind": kinds[i], "cell": c} for i, c in enumerate(cells)]


def build_interior(did, kind, index):
    """A 30x20 room: a border wall, an entry door, a secret and two devices."""
    w, h = 30, 20
    g = [["#" if (x in (0, w - 1) or y in (0, h - 1)) else "." for x in range(w)]
         for y in range(h)]
    # a dividing wall so the room is not one empty rectangle
    for y in range(5, h - 5):
        g[y][11] = "#"
    g[9][11] = "."   # doorway through the divider
    return {
        "name": f"{did}_{kind}", "tiles": "corp", "w": w, "h": h,
        "floor": ["".join(r) for r in g],
        "legend": {
            ".": {"floor": "floor_marble"},
            "#": {"floor": "floor_concrete", "wall": 4.0},
        },
        "props": [
            {"id": "prop_terminal", "cell": [5, 4]},
            {"id": "prop_kiosk", "cell": [18, 4]},
            {"id": "prop_bench", "cell": [22, 12]},
            {"id": "prop_crate", "cell": [25, 16]},
            {"id": "sign_a", "cell": [15, 2], "anchor": "mount", "lift": 24.0},
        ],
        "actors": [{"id": "player", "cell": [3, 10]}],
        "doors": [{"id": f"{did}_{kind}_exit", "cell": [2, 10],
                   "target": did, "spawn": "entry", "prompt": "EXIT"}],
        "secrets": [{"id": f"{did}_{kind}_cache", "cell": [26, 3],
                     "item": "cred_medium"}],
        "npcs": [{"id": "npc_techie", "cell": [22, 9]}],
        "interactables": [{"kind": "server_rack", "cell": [14, 6]},
                          {"kind": "terminal", "cell": [7, 14]}],
    }


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    total_interiors = 0
    for did, spec in DISTRICTS.items():
        d = build(spec, did)
        (OUT / f"{did}.iso.json").write_text(json.dumps(d, indent=1), encoding="utf-8")
        print(f"{did}: {d['w']}x{d['h']} props={len(d['props'])} "
              f"doors={len(d['doors'])} secrets={len(d['secrets'])} "
              f"npcs={len(d['npcs'])} devices={len(d['interactables'])}")
        for i, kind in enumerate(INTERIORS):
            room = build_interior(did, kind, i)
            (OUT / f"{did}_{kind}.iso.json").write_text(
                json.dumps(room, indent=1), encoding="utf-8")
            total_interiors += 1
    print("interiors:", total_interiors)
