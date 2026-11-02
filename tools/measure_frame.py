"""Report the frame statistics the concept art is judged by.

The twelve reference images share a lighting signature: 3-6% of pixels above
luminance 180, p95 near 175, mean 56-80. A render that is "too dark" or "too
flat" is then a number, not an argument.

Usage:  python tools/measure_frame.py <png> [<png> ...]
"""
import sys

import numpy as np
from PIL import Image

CONCEPT = {
    "combat": (61.1, 158, 3.1, 20.0),
    "corp": (79.5, 184, 5.7, 14.3),
    "night": (56.3, 176, 4.5, 27.5),
}


def stats(path):
    im = np.array(Image.open(path).convert("RGB")).astype(int)
    lum = im.mean(2)
    mx, mn = im.max(2), im.min(2)
    return {
        "mean": lum.mean(),
        "p50": float(np.percentile(lum, 50)),
        "p95": float(np.percentile(lum, 95)),
        "bright": 100.0 * (lum > 180).mean(),
        "dark": 100.0 * (lum < 25).mean(),
        "sat": float((mx - mn).mean()),
        "colors": int(len(np.unique(im.reshape(-1, 3), axis=0))),
    }


def main(paths):
    print("%-34s %6s %5s %5s %7s %7s %5s" %
          ("frame", "mean", "p50", "p95", "b>180%", "dark%", "sat"))
    print("-" * 76)
    for name, (mean, p95, bright, dark) in CONCEPT.items():
        print("%-34s %6.1f %5s %5.0f %7.1f %7.1f %5s  (concept)" %
              ("concept " + name, mean, "-", p95, bright, dark, "-"))
    print("-" * 76)
    for p in paths:
        s = stats(p)
        ok_b = 3.0 <= s["bright"] <= 6.5
        ok_p = s["p95"] >= 150
        flag = "ok" if (ok_b and ok_p) else "LOW"
        print("%-34s %6.1f %5.0f %5.0f %7.1f %7.1f %5.0f  %s" %
              (p.split("/")[-1][:34], s["mean"], s["p50"], s["p95"],
               s["bright"], s["dark"], s["sat"], flag))


if __name__ == "__main__":
    main(sys.argv[1:] or ["game/evidence/iso_probe.png"])
