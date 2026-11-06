"""Recolor the Yellow River channel in the packaged seasonal tiles.

No artwork is generated here. Each season panel is stitched back from its level-3
tiles, the channel is recovered by edge-aware region growing from a hand-traced
centerline, and only the water pixels get a new hue before the pyramid is re-cut.
Autumn/winter foliage shares the river's ochre palette, so the other three seasons
grow inside the corridor found on the spring panel.

    python tools/recolor_river.py --debug     # 只看掩膜与试色，不写资源
    python tools/recolor_river.py             # 写回 seasons/ 瓦片与 atlas.png
"""
from PIL import Image
import argparse
import numpy as np
from pathlib import Path
import cv2

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'entry/src/main/resources/rawfile/experience'
DEBUG = ROOT / '.tmp/river-recolor'
SEASONS = ('spring', 'summer', 'autumn', 'winter')
LOGICAL = (1024, 1536)
TILE, MAX_LEVEL = 256, 3
TARGET_HUE = 0.53
GROW = dict(hue=(0.060, 0.170), sat=0.28, val=0.55, std=0.10)
WATER = dict(hue=(0.060, 0.180), sat=0.26, val=0.52)
CORRIDOR, SEED_SHRINK = 14, 5

CENTER = [
    (0.440, 0.075), (0.455, 0.100), (0.470, 0.125), (0.500, 0.155), (0.520, 0.180),
    (0.500, 0.210), (0.475, 0.235), (0.470, 0.260), (0.480, 0.290), (0.500, 0.315),
    (0.490, 0.345), (0.460, 0.365), (0.440, 0.385), (0.445, 0.410), (0.450, 0.440),
    (0.460, 0.465), (0.475, 0.490), (0.490, 0.515), (0.500, 0.545), (0.510, 0.575),
    (0.520, 0.605), (0.530, 0.640), (0.545, 0.675), (0.560, 0.710), (0.575, 0.745),
    (0.590, 0.780), (0.600, 0.815), (0.610, 0.850), (0.615, 0.885), (0.610, 0.920),
    (0.600, 0.955), (0.590, 0.990),
]

def stitch(season, level=MAX_LEVEL):
    factor = 2 ** (MAX_LEVEL - level)
    size = (LOGICAL[0] // factor, LOGICAL[1] // factor)
    canvas = Image.new('RGB', size)
    for tx in range((size[0] + TILE - 1) // TILE):
        for ty in range((size[1] + TILE - 1) // TILE):
            p = OUT / 'seasons' / season / str(level) / str(tx) / f'{ty}.jpg'
            canvas.paste(Image.open(p).convert('RGB'), (tx * TILE, ty * TILE))
    return canvas

def fields(rgb):
    a = np.asarray(rgb).astype(np.float32) / 255.0
    mx, mn = a.max(2), a.min(2)
    d = np.maximum(mx - mn, 1e-9)
    sat = np.where(mx > 0, d / np.maximum(mx, 1e-9), 0)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) / 6.0
    L = a.mean(2)
    mean = cv2.boxFilter(L, -1, (9, 9))
    sq = cv2.boxFilter(L * L, -1, (9, 9))
    return np.mod(h, 1.0), sat, mx, np.sqrt(np.maximum(sq - mean * mean, 0))

def window(h, sat, mx, std, spec):
    ok = (h >= spec['hue'][0]) & (h <= spec['hue'][1]) & (sat >= spec['sat']) & (mx >= spec['val'])
    return ok if 'std' not in spec else ok & (std < spec['std'])

def grow_from(seed, allowed, max_iter=1500):
    mask = seed & allowed
    for it in range(max_iter):
        nxt = cv2.dilate(mask, np.ones((5, 5), np.uint8)) & allowed
        if not (nxt & ~mask).any():
            break
        mask = nxt | mask
    return mask, it

def finish(raw, h, sat, mx):
    raw = cv2.morphologyEx(raw, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    flood = np.zeros((raw.shape[0] + 2, raw.shape[1] + 2), np.uint8)
    cv2.floodFill(flood, None, (0, 0), 255)
    filled = np.where((flood[1:-1, 1:-1] == 0) | (raw > 0), 255, 0).astype(np.uint8)
    water = window(h, sat, mx, np.zeros_like(sat), WATER).astype(np.uint8) * 255
    water = cv2.bitwise_and(filled, water)
    return cv2.morphologyEx(water, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))

def channel_mask(rgb, corridor=None):
    """河道掩膜：春季由中心线长出来，其余季节沿春季走廊在自己画面里收边。"""
    h, sat, mx, std = fields(rgb)
    allowed = (window(h, sat, mx, std, GROW).astype(np.uint8)) * 255
    if corridor is None:
        seed = np.zeros(LOGICAL[::-1], np.uint8)
        cv2.polylines(seed, [np.array([(int(fx * LOGICAL[0]), int(fy * LOGICAL[1])) for fx, fy in CENTER])],
                      False, 255, 18, cv2.LINE_AA)
    else:
        seed = cv2.erode(corridor, np.ones((SEED_SHRINK, SEED_SHRINK), np.uint8))
        allowed = cv2.bitwise_and(allowed, cv2.dilate(corridor, np.ones((CORRIDOR, CORRIDOR), np.uint8)))
    raw, _ = grow_from(seed, allowed)
    return finish(raw, h, sat, mx)

def recolor(rgb, alpha):
    hsv = np.asarray(rgb.convert('HSV')).astype(np.float32) / 255.0
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    keep = 1.0 - alpha
    out = np.stack([h * keep + TARGET_HUE * alpha,
                    s * keep + np.clip(s * 0.92 + 0.06, 0, 1) * alpha,
                    v * keep + np.clip(v * 0.99 + 0.01, 0, 1) * alpha], -1)
    return Image.fromarray(np.uint8(np.clip(out * 255.0, 0, 255)), 'HSV').convert('RGB')

def cut_pyramid(season, panel):
    for level in range(MAX_LEVEL + 1):
        factor = 2 ** (MAX_LEVEL - level)
        size = (LOGICAL[0] // factor, LOGICAL[1] // factor)
        reduced = panel.resize(size, Image.Resampling.LANCZOS)
        for tx in range((size[0] + TILE - 1) // TILE):
            for ty in range((size[1] + TILE - 1) // TILE):
                p = OUT / 'seasons' / season / str(level) / str(tx) / f'{ty}.jpg'
                reduced.crop((tx * TILE, ty * TILE, min(size[0], (tx + 1) * TILE),
                              min(size[1], (ty + 1) * TILE))).save(p, quality=92)

def overlay(rgb, mask, color=(255.0, 0.0, 160.0)):
    out = np.asarray(rgb).astype(np.float32).copy()
    sel = mask > 127
    out[sel] = out[sel] * 0.3 + np.array(color) * 0.7
    return Image.fromarray(np.uint8(out))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--debug', action='store_true')
    args = ap.parse_args()
    panels = {s: stitch(s) for s in SEASONS}
    masks = {}
    for season in SEASONS:
        corridor = masks.get('spring')
        masks[season] = channel_mask(panels[season], corridor)
        alpha = cv2.GaussianBlur(masks[season], (0, 0), 1.6).astype(np.float32) / 255.0
        trial = recolor(panels[season], alpha)
        print('%s channel %.1f%%' % (season, (masks[season] > 127).mean() * 100))
        if args.debug:
            DEBUG.mkdir(parents=True, exist_ok=True)
            strip = Image.new('RGB', (LOGICAL[0], LOGICAL[1] * 2 + 6), '#111')
            strip.paste(overlay(panels[season], masks[season]), (0, 0))
            strip.paste(trial, (0, LOGICAL[1] + 6))
            strip.resize((LOGICAL[0] // 2, (LOGICAL[1] * 2 + 6) // 2), Image.Resampling.LANCZOS
                         ).save(DEBUG / f'{season}-final.png')
            continue
        cut_pyramid(season, trial)
        if season == 'spring':
            trial.save(OUT / 'atlas.png')
    if not args.debug:
        print('tiles and atlas.png rewritten with the blue channel')

if __name__ == '__main__':
    main()
