#!/usr/bin/env python3
"""Measures every shipped photograph against the set's brief.

Nothing here judges whether a picture is good. It reports the three numbers
that decide whether a set of pictures looks like one commission or like a
folder of stock: mean luminance, mean saturation, and a saturation-weighted
circular mean hue. Grey pixels do not vote on hue, which is why the hue of a
near-monochrome frame reads as 0 rather than as noise.

The band is empirical, not aspirational. Warm workshop interiors sit around
60-120 luminance and 0.22-0.48 saturation; wood puts the hue between 18 and
46 degrees on its own. An image outside it is not necessarily bad -- it is
necessarily different from the rest, which on a page of six is the thing that
reads.

    tests/lib/measure-images.py content/file
"""
import colorsys
import math
import pathlib
import sys

from PIL import Image

LUM = (62, 118)
SAT = (0.22, 0.48)
HUE = (18, 46)


def measure(path):
    image = Image.open(path).convert('RGB')
    image.thumbnail((160, 160))
    pixels = list(image.getdata())
    count = len(pixels)
    luminance = sum(0.2126 * r + 0.7152 * g + 0.0722 * b for r, g, b in pixels) / count
    hsv = [colorsys.rgb_to_hsv(r / 255, g / 255, b / 255) for r, g, b in pixels]
    saturation = sum(p[1] for p in hsv) / count
    x = sum(math.cos(p[0] * 2 * math.pi) * p[1] for p in hsv)
    y = sum(math.sin(p[0] * 2 * math.pi) * p[1] for p in hsv)
    return luminance, saturation, (math.degrees(math.atan2(y, x)) + 360) % 360


def main(directory):
    rows = []
    for path in sorted(pathlib.Path(directory).iterdir()):
        if path.suffix.lower() not in ('.jpg', '.jpeg'):
            continue
        luminance, saturation, hue = measure(path)
        ok = (LUM[0] <= luminance <= LUM[1]
              and SAT[0] <= saturation <= SAT[1]
              and HUE[0] <= hue <= HUE[1])
        rows.append((path.name, luminance, saturation, hue, ok))

    print('%-40s %6s %6s %6s  %s' % ('file', 'lum', 'sat', 'hue', 'brief'))
    for name, luminance, saturation, hue, ok in sorted(rows, key=lambda r: r[1]):
        print('%-40s %6.1f %6.2f %6.0f  %s'
              % (name, luminance, saturation, hue, 'ok' if ok else 'out'))
    inside = sum(1 for r in rows if r[4])
    print('\n%d of %d inside the brief' % (inside, len(rows)))
    # Reported, not enforced: the shipped set does not meet this yet, and a
    # failing exit code here would only teach whoever runs it to pass --force.
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else 'content/file'))
