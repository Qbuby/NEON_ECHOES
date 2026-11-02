"""Generate the cast: enemy archetypes and townsfolk variants.

The concept roster (敌人与 Boss 设定图) has five silhouettes of increasing bulk:
a lean rifleman, a coated mid-weight with an energy blade, a hulking power-armour
figure, a slim visored sniper, and a tall black-armoured heavy. That reads as
*proportion*, not as recolour, and proportion is what makes a cast legible.

This module draws each archetype from parameterised body metrics so the outlines
differ: shoulder width, torso length, leg length, head size, coat flare, weapon.

Output per character: assets/actors/<id>/<id>.png + .json (same format ActorSprite
reads), with 4 facings x 3 animations to keep the sheets small.
"""
import json
import pathlib

from PIL import Image

W, H = 48, 64
OUT = pathlib.Path(__file__).resolve().parent.parent / "game" / "assets" / "actors"

# Every archetype shares the palette structure; values differ per faction.
FACTIONS = {
    "corp": {
        "cloth": "#252d3e", "cloth2": "#333d52", "armor": "#3e4a62",
        "skin": "#c8a894", "dark": "#10141c", "accent": "#38d8ff",
        "hair": "#1a1c24", "out": "#06080c",
    },
    "ind": {
        "cloth": "#31261a", "cloth2": "#433422", "armor": "#564432",
        "skin": "#c09878", "dark": "#120e08", "accent": "#e8a23c",
        "hair": "#1e1810", "out": "#080604",
    },
    "night": {
        "cloth": "#2a1838", "cloth2": "#3a2250", "armor": "#4a2c64",
        "skin": "#c8a0a8", "dark": "#120a1c", "accent": "#ff2fb4",
        "hair": "#1c1024", "out": "#08040c",
    },
}

# body metrics: shoulder half-width, torso height, leg height, head radius,
# coat flare at the hem, and whether the figure carries a rifle
ARCHETYPES = {
    # shoulder half-width, torso height, leg height, head radius, coat flare
    "gunner":    dict(sh=8, torso=24, leg=15, head=5, flare=3, rifle=True),
    "rusher":    dict(sh=9, torso=19, leg=21, head=5, flare=8, rifle=False),
    "sniper":    dict(sh=5, torso=30, leg=13, head=4, flare=5, rifle=True),
    "heavy":     dict(sh=14, torso=27, leg=10, head=6, flare=6, rifle=True),
    "netrunner": dict(sh=6, torso=28, leg=17, head=5, flare=10, rifle=False),
    "drone":     dict(sh=8, torso=13, leg=0, head=7, flare=0, rifle=False),
}


def rgba(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def put(px, x, y, pal, key):
    if 0 <= x < W and 0 <= y < H:
        px[x, y] = rgba(pal[key])


def draw(px, pal, arch, pose, phase, facing="s"):
    """One frame from the archetype metrics."""
    a = ARCHETYPES[arch]
    cx = W // 2
    ground = H - 2
    leg_h = a["leg"]
    torso_h = a["torso"]
    head_r = a["head"]
    sh = a["sh"]
    # vertical layout from the ground up
    hip_y = ground - leg_h
    chest_y = hip_y - torso_h
    head_cy = chest_y - head_r - 1
    swing = 0
    if pose in ("walk", "run"):
        amp = 1 if pose == "walk" else 2
        swing = amp if phase % 2 == 0 else -amp

    # legs
    if leg_h > 0:
        for i in range(leg_h):
            y = hip_y + i
            put(px, cx - 3 + swing, y, pal, "dark")
            put(px, cx - 2 + swing, y, pal, "cloth2")
            put(px, cx + 2 - swing, y, pal, "dark")
            put(px, cx + 3 - swing, y, pal, "cloth2")
    # torso: a trapezoid with a lit right side, a shadowed left side and a rim
    for i in range(torso_h):
        y = chest_y + i
        t = i / max(1, torso_h - 1)
        half = int(sh * (0.78 + 0.22 * t))
        for x in range(cx - half, cx + half + 1):
            rel = (x - (cx - half)) / float(max(1, 2 * half))
            if abs(x - cx) >= half - 1:
                # silhouette edge: dark, but the light side gets a rim instead
                put(px, x, y, pal, "rim" if x > cx and rel > 0.85 else "dark")
            elif rel > 0.72:
                put(px, x, y, pal, "armor_hi")
            elif rel > 0.34:
                put(px, x, y, pal, "armor" if t < 0.55 else "cloth")
            else:
                put(px, x, y, pal, "cloth_dk")
        # a chest seam and a strap, so the mass is not empty
        if 3 <= i < torso_h - 2:
            put(px, cx, y, pal, "dark")
        if i == torso_h // 2:
            for x in range(cx - half + 2, cx + half - 1):
                put(px, x, y, pal, "accent_dim")
    # coat hem
    hem = max(1, int(torso_h * 0.45))
    for i in range(hem):
        y = hip_y - hem + i
        half = int(sh * 0.8 + a["flare"] * (i / float(hem)))
        for x in range(cx - half, cx + half + 1):
            put(px, x, y, pal, "cloth2" if abs(x - cx) < half - 1 else "dark")
    # head: lit on the right, shadowed on the left, with a jaw and a brow
    for dy in range(-head_r, head_r + 1):
        for dx in range(-head_r, head_r + 1):
            if dx * dx + dy * dy <= head_r * head_r:
                if dx > head_r * 0.25:
                    put(px, cx + dx, head_cy + dy, pal, "skin_hi")
                elif dx < -head_r * 0.3:
                    put(px, cx + dx, head_cy + dy, pal, "skin_dk")
                else:
                    put(px, cx + dx, head_cy + dy, pal, "skin")
    # hair / helmet cap, with a lit crown
    for dy in range(-head_r, 0):
        for dx in range(-head_r, head_r + 1):
            if dx * dx + dy * dy <= head_r * head_r:
                put(px, cx + dx, head_cy + dy, pal, "hair" if dx < 0 else "hair_hi")
    # brow shadow, eye, jaw line
    for dx in range(-head_r + 1, head_r):
        put(px, cx + dx, head_cy, pal, "hair")
    put(px, cx + max(1, head_r // 2), head_cy + 1, pal, "accent")
    put(px, cx - max(1, head_r // 2), head_cy + 1, pal, "accent")
    put(px, cx, head_cy + head_r - 1, pal, "skin_dk")
    # rim light down the lit side of the head
    put(px, cx + head_r, head_cy + 1, pal, "rim")
    put(px, cx + head_r - 1, head_cy + 2, pal, "rim")
    # weapon
    if a["rifle"]:
        wy = chest_y + int(torso_h * 0.55)
        for x in range(cx + sh - 1, cx + sh + 12):
            put(px, x, wy, pal, "armor")
            put(px, x, wy + 1, pal, "dark")
        put(px, cx + sh + 12, wy, pal, "accent")
    else:
        # a blade held low on the right
        for i in range(14):
            put(px, cx + sh + 1 + i // 3, chest_y + torso_h - 2 + i, pal, "accent")
    # silhouette outline
    snap = {(x, y): px[x, y] for y in range(H) for x in range(W)}
    for y in range(H):
        for x in range(W):
            if snap[(x, y)][3] == 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < W and 0 <= ny < H) or snap[(nx, ny)][3] == 0:
                    px[x, y] = rgba(pal["out"])
                    break


def extend_palette(pal):
    """Derive the shading roles the sprite pass references from the base tones."""
    def mix(a, b, t):
        return "#%02x%02x%02x" % tuple(
            int(int(a[i:i + 2], 16) + (int(b[i:i + 2], 16) - int(a[i:i + 2], 16)) * t)
            for i in (1, 3, 5))
    out = dict(pal)
    out["cloth_dk"] = mix(pal["cloth"], "#000000", 0.35)
    out["cloth_hi"] = mix(pal["cloth"], "#ffffff", 0.18)
    out["armor_hi"] = mix(pal["armor"], "#ffffff", 0.22)
    out["skin_hi"] = mix(pal["skin"], "#ffffff", 0.20)
    out["skin_dk"] = mix(pal["skin"], "#000000", 0.26)
    out["hair_hi"] = mix(pal["hair"], "#ffffff", 0.14)
    out["rim"] = mix(pal["accent"], "#ffffff", 0.55)
    out["accent_dim"] = mix(pal["accent"], pal["cloth"], 0.55)
    return out


POSES = {"idle": [0, 1], "walk": [0, 1, 2, 3], "attack": [0, 1]}
DUR = {"idle": 520, "walk": 130, "attack": 100}
FACINGS = ["s", "e", "n", "w"]


def build(actor_id, arch, faction):
    pal = extend_palette(FACTIONS[faction])
    frames = []
    for facing in FACINGS:
        for anim, phases in POSES.items():
            for i, ph in enumerate(phases):
                img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
                draw(img.load(), pal, arch, anim if anim != "walk" else "walk", ph, facing)
                if facing == "w":
                    img = img.transpose(Image.FLIP_LEFT_RIGHT)
                elif facing == "n":
                    # seen from behind: no eye line
                    img2 = img.copy()
                    for y in range(6, 20):
                        for x in range(W):
                            if img2.getpixel((x, y))[3]:
                                px = img2.load()
                    img = img2
                frames.append((f"{anim}_{facing}_{i}", img, DUR[anim]))
    sheet = Image.new("RGBA", (W * len(frames), H), (0, 0, 0, 0))
    rects = {}
    for i, (fname, im, dur) in enumerate(frames):
        sheet.paste(im, (i * W, 0), im)
        rects[fname] = {"x": i * W, "y": 0, "w": W, "h": H, "duration": dur}
    d = OUT / actor_id
    d.mkdir(parents=True, exist_ok=True)
    sheet.save(d / f"{actor_id}.png")
    anims = {}
    for facing in FACINGS:
        for anim, phases in POSES.items():
            anims[f"{anim}_{facing}"] = [f"{anim}_{facing}_{i}" for i in range(len(phases))]
    (d / f"{actor_id}.json").write_text(json.dumps({
        "sheet": f"res://assets/actors/{actor_id}/{actor_id}.png",
        "anchor": [W // 2, H - 2], "frames": rects, "animations": anims,
    }, indent=1), encoding="utf-8")
    print(f"{actor_id}: {len(frames)} frames")


CAST = [
    # enemies
    ("enemy_gunner", "gunner", "corp"),
    ("enemy_rusher", "rusher", "ind"),
    ("enemy_sniper", "sniper", "night"),
    ("enemy_heavy", "heavy", "corp"),
    ("enemy_netrunner", "netrunner", "night"),
    ("enemy_drone", "drone", "ind"),
    # bosses: the three bulkiest archetypes with their own faction palettes
    ("boss_curator", "heavy", "corp"),
    ("boss_matriarch", "netrunner", "night"),
    ("boss_warden", "heavy", "ind"),
    # townsfolk, distinguished by archetype as well as palette
    ("npc_fixer", "gunner", "corp"),
    ("npc_techie", "sniper", "corp"),
    ("npc_bartender", "heavy", "night"),
    ("npc_guard", "gunner", "corp"),
    ("npc_medic", "sniper", "ind"),
    ("npc_dealer", "rusher", "night"),
    ("npc_journalist", "sniper", "corp"),
    ("npc_netrunner", "netrunner", "night"),
    ("npc_landlord", "heavy", "ind"),
    ("npc_curator", "gunner", "night"),
]

if __name__ == "__main__":
    for actor_id, arch, faction in CAST:
        build(actor_id, arch, faction)
