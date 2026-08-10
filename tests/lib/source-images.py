"""Source photographs by measurement, not by eye.

Every image I picked from a contact sheet this session made the set less
coherent. This searches, downloads a thumbnail, measures mean luminance,
mean saturation and a saturation-weighted circular mean hue, and only
reports the ones inside the brief.
"""
import colorsys, io, json, math, os, pathlib, sys, urllib.parse, urllib.request
from PIL import Image

LUM = (62, 118)
SAT = (0.22, 0.48)
HUE = (18, 46)

def measure(data):
    im = Image.open(io.BytesIO(data)).convert('RGB')
    im.thumbnail((140, 140))
    px = list(im.getdata())
    n = len(px)
    lum = sum(0.2126 * r + 0.7152 * g + 0.0722 * b for r, g, b in px) / n
    hs = [colorsys.rgb_to_hsv(r / 255, g / 255, b / 255) for r, g, b in px]
    sat = sum(h[1] for h in hs) / n
    sx = sum(math.cos(h[0] * 2 * math.pi) * h[1] for h in hs)
    sy = sum(math.sin(h[0] * 2 * math.pi) * h[1] for h in hs)
    hue = (math.degrees(math.atan2(sy, sx)) + 360) % 360
    return lum, sat, hue

def access_key():
    """The Unsplash access key, from the environment.

    Never hardcoded. A key that lives in a source file is a key that ends up in
    a public git history, which is what happened to the last one.
    """
    key = os.environ.get('UNSPLASH_ACCESS_KEY')
    if not key:
        print('Set UNSPLASH_ACCESS_KEY to an Unsplash API access key. '
              'Create one at https://unsplash.com/oauth/applications.',
              file=sys.stderr)
        raise SystemExit(2)
    return key

def search(q, per=10):
    u = ('https://api.unsplash.com/search/photos?query=%s&per_page=%d'
         % (urllib.parse.quote(q), per))
    r = urllib.request.Request(u, headers={'Authorization': 'Client-ID ' + access_key()})
    return json.load(urllib.request.urlopen(r)).get('results', [])

hits = []
for q in sys.argv[1:]:
    for p in search(q):
        try:
            thumb = urllib.request.urlopen(p['urls']['thumb']).read()
            lum, sat, hue = measure(thumb)
        except Exception:
            continue
        ok = (LUM[0] <= lum <= LUM[1] and SAT[0] <= sat <= SAT[1]
              and HUE[0] <= hue <= HUE[1])
        if ok:
            hits.append((q, p['id'], round(lum, 1), round(sat, 2), round(hue),
                         (p.get('alt_description') or '')[:44], p['urls']['raw']))
print('%-30s %-12s %6s %5s %5s  %s' % ('query', 'id', 'lum', 'sat', 'hue', 'alt'))
for h in hits:
    print('%-30s %-12s %6.1f %5.2f %5d  %s' % (h[0][:30], h[1], h[2], h[3], h[4], h[5]))
print('\nin brief: %d' % len(hits))
out = pathlib.Path(__file__).resolve().parent / 'harvest' / 'hits.json'
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(hits, indent=2))
print('\nwrote %s' % out)
