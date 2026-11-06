"""黄河沙盘实景地形底图烘焙。

数据源（全部公开、可离线随包）：
  - 高程：AWS Open Terrain Tiles / Nextzen terrarium（SRTM 派生，公有领域）
  - 省界：阿里 DataV GeoJSON（民政部标准区划口径）
产物：
  - entry/src/main/resources/rawfile/sandtable/terrain.jpg  晕渲底图（不含透明通道，省界在 Canvas 里 clip）
  - shots/terrain_preview.png                               自检用预览
  - .tmp/geo_boundary.json                                  简化后的省界经纬度环
  - .tmp/geo_rivers.json                                    四段黄河脊柱（已做山区谷地吸附）

用法： python tools/bake_terrain.py [--zoom 9] [--refresh]
"""
import argparse
import io
import json
import math
import os
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(os.path.expanduser('~'), 'demcache')
SHOTS = os.path.join(ROOT, 'shots')
TMP = os.path.join(ROOT, '.tmp')
RAWFILE = os.path.join(ROOT, 'entry', 'src', 'main', 'resources', 'rawfile', 'sandtable')

BBOX = (110.10, 116.90, 31.20, 36.55)
TILE = 256

def xy(lon, lat, z):
    n = 2.0 ** z
    x = (lon + 180.0) / 360.0 * n
    r = math.radians(lat)
    y = (1.0 - math.log(math.tan(r) + 1.0 / math.cos(r)) / math.pi) / 2.0 * n
    return x, y

def lonlat_of(px, py, z, x0, y0):
    """栅格像素 -> 经纬度（等距圆柱 Web Mercator 反算）"""
    n = 2.0 ** z
    lon = (x0 + px / TILE) / n * 360.0 - 180.0
    yy = (y0 + py / TILE) / n
    lat = math.degrees(math.atan(math.sinh(math.pi * (1.0 - 2.0 * yy))))
    return lon, lat

def fetch_tile(args):
    z, x, y, refresh = args
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, 'z%d_%d_%d.png' % (z, x, y))
    if not os.path.exists(path) or refresh:
        url = 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/%d/%d/%d.png' % (z, x, y)
        data = urllib.request.urlopen(url, timeout=30).read()
        with open(path, 'wb') as f:
            f.write(data)
    return path

def load_dem(z, refresh):
    x0 = int(math.floor(xy(BBOX[0], BBOX[3], z)[0]))
    x1 = int(math.floor(xy(BBOX[1], BBOX[3], z)[0]))
    y0 = int(math.floor(xy(BBOX[0], BBOX[3], z)[1]))
    y1 = int(math.floor(xy(BBOX[1], BBOX[2], z)[1]))
    jobs = [(z, x, y, refresh) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)]
    print('tiles: %d cols x %d rows = %d' % (len(range(x0, x1 + 1)), len(range(y0, y1 + 1)), len(jobs)))
    with ThreadPoolExecutor(8) as ex:
        paths = list(ex.map(fetch_tile, jobs))
    total = sum(os.path.getsize(p) for p in paths)
    print('downloaded bytes: %.1f MB' % (total / 1048576.0))
    ncols = x1 - x0 + 1
    nrows = y1 - y0 + 1
    w = ncols * TILE
    h = nrows * TILE
    elev = np.zeros((h, w), np.float32)
    for (tz, tx, ty, _), p in zip(jobs, paths):
        gx, gy = tx - x0, ty - y0
        a = np.asarray(Image.open(p).convert('RGB')).astype(np.int32)
        d = a[:, :, 0] * 256 + a[:, :, 1] + a[:, :, 2] / 256.0 - 32768
        elev[gy * TILE:(gy + 1) * TILE, gx * TILE:(gx + 1) * TILE] = d
    from scipy import ndimage
    bad = elev < -100
    if bad.any():
        _, nn = ndimage.distance_transform_edt(bad, return_indices=True)
        elev[bad] = elev[(nn[0][bad], nn[1][bad])]
        print('no-data %d px (%.3f%%) 最近合法值填充' % (int(bad.sum()), 100.0 * bad.mean()))
    lat_top = lonlat_of(0, 0, z, x0, y0)[1]
    lon_left = lonlat_of(0, 0, z, x0, y0)[0]
    lon_right = lonlat_of(w, 0, z, x0, y0)[0]
    lat_bottom = lonlat_of(0, h, z, x0, y0)[1]
    m_per_px = 40075016.8 * math.cos(math.radians((lat_top + lat_bottom) / 2)) / (TILE * 2.0 ** z)
    print('grid %dx%d  lon %.4f..%.4f  lat %.4f..%.4f  %.0f m/px' % (w, h, lon_left, lon_right, lat_bottom, lat_top, m_per_px))
    print('elev m: min %.0f p50 %.0f p99 %.0f max %.0f' % (elev.min(), np.percentile(elev, 50), np.percentile(elev, 99), elev.max()))
    sm = ndimage.gaussian_filter(elev.astype(np.float64), 3.0).astype(np.float32)
    return dict(elev=elev, sm=sm, z=z, x0=x0, y0=y0, w=w, h=h, lon_left=lon_left, lat_top=lat_top,
                lon_right=lon_right, lat_bottom=lat_bottom, m_per_px=m_per_px)

def px_of(dem, lon, lat):
    """经纬度 -> 原始 DEM 栅格像素（线性）"""
    fx, _ = xy(lon, lat, dem['z'])
    _, fy = xy(lon, lat, dem['z'])
    return (fx - dem['x0']) * TILE, (fy - dem['y0']) * TILE

def load_boundary():
    path = os.path.join(CACHE, '410000.json')
    if not os.path.exists(path):
        url = 'https://geo.datav.aliyun.com/areas_v3/bound/410000.json'
        with open(path, 'wb') as f:
            f.write(urllib.request.urlopen(url, timeout=30).read())
    d = json.load(open(path, encoding='utf-8'))
    polys = []
    for poly in d['features'][0]['geometry']['coordinates']:
        for ring in poly:
            if len(ring) >= 8:
                polys.append([(c[0], c[1]) for c in ring])
    print('boundary rings: %s pts' % [len(p) for p in polys])
    return polys

def dp(points, eps):
    """Douglas-Peucker 简化"""
    if len(points) < 3:
        return points
    a, b = points[0], points[-1]
    dx, dy = b[0] - a[0], b[1] - a[1]
    L = math.hypot(dx, dy)
    if L < 1e-12:
        d = [math.hypot(p[0] - a[0], p[1] - a[1]) for p in points]
    else:
        d = [abs(dy * (p[0] - a[0]) - dx * (p[1] - a[1])) / L for p in points]
    i = int(np.argmax(d))
    if d[i] > eps:
        return dp(points[:i + 1], eps)[:-1] + dp(points[i:], eps)
    return [a, b]

def simplify(polys, eps):
    out = []
    for p in polys:
        s = dp(p, eps)
        if len(s) >= 6:
            out.append(s)
    return out

def draw_mask(shape, polys, dem, scale):
    """省界 -> 目标尺寸二值掩膜（scale = 目标像素 / 原始像素）"""
    h, w = shape
    m = Image.new('L', (w, h), 0)
    dr = ImageDraw.Draw(m)
    for p in polys:
        pts = []
        for lon, lat in p:
            x, y = px_of(dem, lon, lat)
            pts.append((x * scale, y * scale))
        dr.polygon(pts, fill=255)
    return np.asarray(m, np.float32) / 255.0

def hillshade(elev, m_per_px, azimuth, altitude, exaggeration):
    dzdx, dzdy = np.gradient(elev.astype(np.float64), m_per_px * 1.0)
    dzdx *= exaggeration
    dzdy *= exaggeration
    slope = np.arctan(np.hypot(dzdx, dzdy))
    aspect = np.arctan2(dzdy, -dzdx)
    az = math.radians(azimuth)
    al = math.radians(altitude)
    out = (np.cos(al) * np.cos(slope) + np.sin(al) * np.sin(slope) * np.cos(aspect - az)).astype(np.float32)
    return np.clip(out, 0, 1)

RAMP = [
    (0, (126, 162, 96)),
    (150, (140, 172, 100)),
    (300, (172, 180, 108)),
    (600, (196, 172, 110)),
    (1000, (196, 148, 96)),
    (1500, (176, 120, 78)),
    (2000, (152, 96, 64)),
    (2600, (186, 166, 150)),
    (3100, (222, 216, 208)),
]

def colorize(elev):
    rgb = np.empty(elev.shape + (3,), np.float32)
    for i in range(3):
        rgb[:, :, i] = np.interp(elev, [r[0] for r in RAMP], [r[1][i] for r in RAMP])
    return rgb

def norm01(a):
    lo, hi = np.percentile(a, [1.0, 99.0])
    return np.clip((a - lo) / max(hi - lo, 1e-6), 0, 1)

def bake(dem, polys, out_w, paper=(245, 239, 228), knock=0.05):
    """实景晕渲：主光 315°/42° 出体积感，补光 160° 抬阴面，低地叠一层高频微起伏防"死平"。

    shade 以 1.0 为中性（= RAMP 本色），只在 0.58~1.38 之间摆动；上限刻意压住，
    超过 1.4 绿/红通道就会先后 clipped，整张图会往乳白洗掉（上一版 1.68 的教训）。
    """
    from scipy import ndimage
    elev = dem['elev']
    scale = out_w / float(dem['w'])
    out_h = int(round(dem['h'] * scale))
    small = ndimage.zoom(elev, (out_h / float(dem['h']), scale), order=1).astype(np.float32)
    small = small[:out_h, :out_w]
    mpp = dem['m_per_px'] / scale
    hs = hillshade(small, mpp, 315, 42, 3.6) * 0.80 + hillshade(small, mpp, 160, 28, 2.2) * 0.20
    hs = norm01(hs)
    fine = norm01(hillshade(small, mpp, 300, 30, 9.0))
    rgb = colorize(small)
    shade = 0.58 + 0.80 * hs
    plain = np.clip((220.0 - small) / 220.0, 0, 1).astype(np.float32)[:, :, None]
    shade = shade[:, :, None] * (1 - plain) + (shade[:, :, None] * (0.90 + 0.22 * fine[:, :, None])) * plain
    rgb = np.clip(rgb * shade, 0, 255)
    rgb = rgb * (1 - knock) + np.array(paper, np.float32)[None, None, :] * knock
    mask = draw_mask(small.shape, polys, dem, scale)
    bg = np.array(paper, np.float32)[None, None, :]
    img = rgb * mask[:, :, None] + bg * (1 - mask[:, :, None])
    return np.clip(img, 0, 255).astype(np.uint8), mask, scale

def sample(dem, lon, lat):
    x, y = px_of(dem, lon, lat)
    xi = min(max(int(round(x)), 0), dem['w'] - 1)
    yi = min(max(int(round(y)), 0), dem['h'] - 1)
    return float(dem['elev'][yi, xi])

RIVER_PROFILE = [(110.4, 340.0), (111.0, 305.0), (111.5, 285.0), (112.0, 240.0), (112.4, 200.0),
                 (112.9, 150.0), (113.4, 110.0), (113.9, 82.0), (114.4, 62.0), (114.9, 52.0),
                 (115.4, 46.0), (115.9, 42.0), (116.9, 38.0)]

def expected_elev(lon):
    return float(np.interp(lon, [p[0] for p in RIVER_PROFILE], [p[1] for p in RIVER_PROFILE]))

def snap(dem, lon, lat, radius_deg=0.06, min_relief=120.0, elev_w=1.0, dist_w=25.0, max_drift_km=8.0):
    """山区段：按"河床高程先验 + 距离罚"吸附到与水位相符的谷底。
    平原段（±0.04° 窗口起伏 <120m）不动——那里没有山脊可穿帮，人工走向更可信。"""
    deg_px = (dem['lon_right'] - dem['lon_left']) / dem['w']
    km_px = dem['m_per_px'] / 1000.0
    x = min(max(px_of(dem, lon, lat)[0], 1.0), dem['w'] - 2.0)
    y = min(max(px_of(dem, lon, lat)[1], 1.0), dem['h'] - 2.0)
    r_small = 0.04 / deg_px
    yi0, yi1 = int(max(0, y - r_small)), int(min(dem['h'], y + r_small))
    xi0, xi1 = int(max(0, x - r_small)), int(min(dem['w'], x + r_small))
    win = dem['elev'][yi0:yi1, xi0:xi1]
    relief = float(win.max() - win.min()) if win.size else 0.0
    if relief < min_relief:
        return lon, lat, relief, 0.0, 'plain'
    r_px = radius_deg / deg_px
    yi0, yi1 = int(max(0, y - r_px)), int(min(dem['h'], y + r_px))
    xi0, xi1 = int(max(0, x - r_px)), int(min(dem['w'], x + r_px))
    if yi1 - yi0 < 2 or xi1 - xi0 < 2:
        return lon, lat, relief, 0.0, 'edge'
    yy, xx = np.mgrid[yi0:yi1, xi0:xi1]
    lonc = dem['lon_left'] + (xi0 + xx + 0.5) * deg_px
    expc = np.interp(lonc, [p[0] for p in RIVER_PROFILE], [p[1] for p in RIVER_PROFILE])
    dkm = np.hypot((xx - x) * km_px, (yy - y) * km_px)
    cost = elev_w * np.abs(dem['sm'][yi0:yi1, xi0:xi1] - expc) + dist_w * dkm
    iy, ix = np.unravel_index(int(np.argmin(cost)), cost.shape)
    nlon, nlat = lonlat_of(xi0 + ix + 0.5, yi0 + iy + 0.5, dem['z'], dem['x0'], dem['y0'])
    drift = math.hypot((nlon - lon) * math.cos(math.radians(lat)), nlat - lat) * 111.0
    if drift > max_drift_km:
        return lon, lat, relief, round(drift, 2), 'capped'
    return float(nlon), float(nlat), relief, round(drift, 2), 'valley'

def catmull(pts, segs=14):
    """Catmull-Rom 沿程采样，用来检查"线"而不是只检查"点"。"""
    P = [pts[0]] + list(pts) + [pts[-1]]
    out = []
    for i in range(1, len(P) - 3):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for t in range(segs):
            s = t / float(segs)
            s2, s3 = s * s, s * s * s
            def mix(k):
                return 0.5 * (2 * p1[k] + (-p0[k] + p2[k]) * s +
                              (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * s2 +
                              (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * s3)
            out.append((mix(0), mix(1)))
    out.append(pts[-1])
    return out

def floor_ratio(dem, pts, win_deg=0.02, tol=80.0):
    """沿程谷底率：每个采样点与 ±win_deg 窗口最低点的高差 <= tol 米，算"没骑山脊"。"""
    r_px = win_deg / ((dem['lon_right'] - dem['lon_left']) / dem['w'])
    bad, worst = 0, (0.0, 0.0, 0.0)
    for lon, lat in catmull(pts):
        x, y = px_of(dem, lon, lat)
        yi0, yi1 = int(max(0, y - r_px)), int(min(dem['h'], y + r_px))
        xi0, xi1 = int(max(0, x - r_px)), int(min(dem['w'], x + r_px))
        if win_size(dem, xi0, xi1, yi0, yi1) == 0:
            continue
        win = dem['elev'][yi0:yi1, xi0:xi1]
        d = float(dem['elev'][int(round(y)), int(round(x))]) - float(win.min())
        if d > tol:
            bad += 1
            if d > worst[2]:
                worst = (lon, lat, d)
    n = len(pts) * 14
    return round(100.0 * (n - bad) / max(n, 1), 1), worst

def win_size(dem, xi0, xi1, yi0, yi1):
    return max(0, xi1 - xi0) * max(0, yi1 - yi0)

FRAME = (110.20, 34.30, 116.80, 36.60)
N_SPINE = 40
DAYU_DIVERGE = 113.85
DUO_DIVERGE = 114.30
DAYU_BRANCH = [(114.05, 35.20), (114.35, 35.60), (114.75, 36.00), (115.15, 36.40), (115.50, 36.75)]
DUO_BRANCH = [(114.85, 34.72), (115.30, 34.52), (115.75, 34.28), (116.20, 34.05), (116.70, 33.85)]
CANAL = [(112.45, 34.63), (112.95, 34.72), (113.30, 34.90), (114.30, 34.79),
         (115.05, 34.48), (115.60, 34.30), (116.30, 33.98)]

MOUNTAINS = [('太行山', 113.55, 35.95), ('王屋山', 112.10, 35.26), ('崤山', 111.95, 34.34),
             ('小秦岭', 110.60, 34.28), ('熊耳山', 111.35, 34.10), ('外方山', 112.42, 33.90),
             ('伏牛山', 111.85, 33.75), ('嵩山', 112.99, 34.52), ('桐柏山', 113.26, 32.38),
             ('大别山', 115.10, 31.55)]

def load_ne():
    path = os.path.join(TMP, 'geo_ne_rivers.json')
    if not os.path.exists(path):
        import river_from_ne
        river_from_ne.main()
    return json.load(open(path, encoding='utf-8'))

def chain(lines, tol_km=12.0):
    """同一条河被切成的多段中心线按端点就近串成一条（顺序无所谓，最后统一按经度定向）。"""
    segs = [list(l) for l in lines if len(l) > 3]
    if not segs:
        return []
    out = segs.pop(0)

    def d(a, b):
        return math.hypot((a[0] - b[0]) * math.cos(math.radians(a[1])), a[1] - b[1]) * 111.0
    changed = True
    while segs and changed:
        changed = False
        for i, s in enumerate(segs):
            if d(s[0], out[-1]) <= tol_km:
                out += s[1:]
            elif d(s[-1], out[0]) <= tol_km:
                out = s[:-1] + out
            elif d(s[-1], out[-1]) <= tol_km:
                out += s[-2::-1]
            elif d(s[0], out[0]) <= tol_km:
                out = s[1:] + out
            else:
                continue
            segs.pop(i)
            changed = True
            break
    if out[0][0] > out[-1][0]:
        out.reverse()
    return out

def resample(pts, n):
    """按地面距离等弧长重采样成 n 个控制点。"""
    km = [0.0]
    for a, b in zip(pts, pts[1:]):
        km.append(km[-1] + math.hypot((b[0] - a[0]) * math.cos(math.radians(a[1])), b[1] - a[1]) * 111.0)
    total = km[-1]
    out = []
    j = 0
    for i in range(n):
        s = total * i / (n - 1.0)
        while j < len(km) - 2 and km[j + 1] < s:
            j += 1
        t = 0.0 if km[j + 1] == km[j] else (s - km[j]) / (km[j + 1] - km[j])
        a, b = pts[j], pts[j + 1]
        out.append((round(a[0] + (b[0] - a[0]) * t, 4), round(a[1] + (b[1] - a[1]) * t, 4)))
    return out

def build_spines(ne):
    """今道 = 真实中心线等弧长重采样；禹河 / 夺淮 = 与今道共用出山口以西的点，
    只把出山口以东的 index 换成手工分流（按弧长分配），保证逐点插值时"上游不动、下游摆动"。"""
    huang = [[p for p in ln if FRAME[0] <= p[0] <= FRAME[2] and FRAME[1] <= p[1] <= FRAME[3]]
             for ln in ne.get('黄河', [])]
    line = chain([s for s in huang if len(s) > 3])
    jin = resample(line, N_SPINE)

    def aligned(div_lon, branch):
        k = next((i for i, p in enumerate(jin) if p[0] > div_lon), len(jin) - 1)
        tail = resample([jin[k - 1]] + list(branch), N_SPINE - k + 1)
        return jin[:k - 1] + tail

    dayu = aligned(DAYU_DIVERGE, DAYU_BRANCH)
    duo = aligned(DUO_DIVERGE, DUO_BRANCH)
    print('中心线 %d 点 -> 脊柱 %d 点；今道枢轴 lon>%.2f 起于 index %d (%.2f,%.2f)'
          % (len(line), N_SPINE, DAYU_DIVERGE, k_of(jin, DAYU_DIVERGE), jin[k_of(jin, DAYU_DIVERGE)][0], jin[k_of(jin, DAYU_DIVERGE)][1]))
    return {'jin': jin, 'dayu': dayu, 'duohuai': duo}, line

def k_of(spine, lon):
    return next((i for i, p in enumerate(spine) if p[0] > lon), len(spine) - 1)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--zoom', type=int, default=9)
    ap.add_argument('--width', type=int, default=1500)
    ap.add_argument('--refresh', action='store_true')
    ap.add_argument('--no-write', action='store_true')
    args = ap.parse_args()
    for d in (CACHE, SHOTS, TMP, RAWFILE):
        os.makedirs(d, exist_ok=True)

    dem = load_dem(args.zoom, args.refresh)
    polys = load_boundary()
    img, mask, scale = bake(dem, polys, args.width)
    out_h = img.shape[0]
    print('output %dx%d' % (img.shape[1], out_h))

    Image.fromarray(img).save(os.path.join(SHOTS, 'terrain_preview.png'), optimize=True)
    jpg = os.path.join(RAWFILE, 'terrain.jpg')
    if not args.no_write:
        Image.fromarray(img).save(jpg, quality=86, optimize=True, progressive=True)
        print('wrote %s  %.0f KB' % (jpg, os.path.getsize(jpg) / 1024.0))

    simp = simplify(polys, 0.02)
    print('simplified rings: %s pts' % [len(r) for r in simp])
    json.dump(dict(rings=[[[round(x, 4), round(y, 4)] for x, y in r] for r in simp],
                   bbox=[round(v, 4) for v in BBOX],
                   grid=[dem['lon_left'], dem['lat_top'], dem['lon_right'], dem['lat_bottom']]),
              open(os.path.join(TMP, 'geo_boundary.json'), 'w', encoding='utf-8'), ensure_ascii=False)

    ne = load_ne()
    spines, full = build_spines(ne)
    out = {'spines': spines, 'canal': [list(p) for p in CANAL], 'huang_full': [[round(a, 4), round(b, 4)] for a, b in full]}
    for k, spine in spines.items():
        ratio, worst = floor_ratio(dem, spine)
        refined = [snap(dem, lon, lat)[:2] for lon, lat in spine]
        r2, w2 = floor_ratio(dem, refined)
        moved = sum(1 for a, b in zip(spine, refined) if a != b)
        print('%-9s 谷底率 %.1f%% -> 吸附后 %.1f%%（动了 %d/%d 个点）最差偏离 %.0fm @ (%.3f,%.3f)'
              % (k, ratio, r2, moved, len(spine), w2[2], w2[0], w2[1]))
        if r2 > ratio + 3.0:
            spines[k] = refined
    for k, spine in spines.items():
        out['spines'][k] = [[round(p[0], 4), round(p[1], 4)] for p in spine]
        print('%-9s 水位 %s' % (k, [int(sample(dem, p[0], p[1])) for p in spine]))
    marks = {}
    for name, lon, lat in MOUNTAINS:
        e = int(sample(dem, lon, lat))
        marks[name] = [lon, lat, e]
        print('  山名 %-6s %8.2f,%7.2f  DEM %dm%s' % (name, lon, lat, e, '  <-- 偏低，检查' if e < 600 else ''))
    out['mountains'] = {k: v[:2] for k, v in marks.items()}
    json.dump(out, open(os.path.join(TMP, 'geo_rivers.json'), 'w', encoding='utf-8'), ensure_ascii=False)
    print('wrote .tmp/geo_boundary.json .tmp/geo_rivers.json shots/terrain_preview.png')

if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    main()
