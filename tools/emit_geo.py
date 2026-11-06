"""把 .tmp/geo_*.json（bake_terrain.py 的产物）转成 index.html 里的 GEO 常量块。

写死在 HTML 里而不是运行时 fetch，是为了让沙盘在 ArkWeb 里少一次异步、少一处失败面；
重新烘焙地形后跑一遍本脚本，把 .tmp/geo_block.js 整段替换进 index.html 的 GEO 段即可。

投影必须和 bake_terrain.py 的 px_of() 一致：DEM 栅格是按 Web Mercator 瓦片行列号拼的，
所以行号线性于 mercY 而不是纬度，用等距圆柱近似会南北向错位几十公里。
"""
import argparse
import io
import json
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TMP = os.path.join(ROOT, '.tmp')

Z, X0, Y0, COLS, ROWS = 9, 412, 200, 11, 10
N = 2.0 ** Z

def merc_x(lon):
    return (lon + 180.0) / 360.0 * N

def merc_y(lat):
    s = math.sin(math.radians(lat))
    return (1.0 - math.log((1.0 + s) / (1.0 - s)) / (2.0 * math.pi)) / 2.0 * N

def ux(lon):
    return (merc_x(lon) - X0) / COLS * 100.0

def uy(lat):
    return (merc_y(lat) - Y0) / COLS * 100.0

def pts(seq):
    return '[' + ','.join('[%.2f,%.2f]' % (ux(p[0]), uy(p[1])) for p in seq) + ']'

def city_js(t):
    n, lon, lat, k = t[0], t[1], t[2], t[3]
    extra = ",a:'%s'" % t[4] if len(t) > 4 else ''
    return "{n:'%s',p:[%.2f,%.2f],k:'%s'%s}" % (n, ux(lon), uy(lat), k, extra)

CITIES = [
    ('洛阳',   112.45, 34.62, 'big'),
    ('开封',   114.35, 34.79, 'big'),
    ('三门峡', 111.20, 34.68, 'small'),
    ('郑州',   113.65, 34.70, 'small'),
    ('濮阳',   115.03, 35.76, 'small', 'top'),
    ('商丘',   115.64, 34.44, 'small'),
]
ANNO = [
    (0, '积石',        110.70, 34.95),
    (0, '疏浚河道',    113.15, 35.05),
    (1, '汴口',        113.72, 35.28),
    (1, '汴渠（通济渠）', 115.30, 34.02),
    (2, '商胡之决',    115.18, 35.28),
    (2, '夺淮河道',    116.02, 34.12),
    (2, '沙土地',      114.72, 34.20),
    (3, '三门峡枢纽',  111.22, 35.14),
    (3, '小浪底',      112.40, 35.00),
    (3, '沿黄生态廊道', 114.55, 35.02),
]
TITLE = ('河 南 省', 114.95, 33.15)

TRIM_HEAD = 9

HTML = os.path.join(ROOT, 'entry', 'src', 'main', 'resources', 'rawfile', 'sandtable', 'index.html')
MARK_A = '  /* >>> GEO 由 tools/emit_geo.py 生成，勿手改 >>> */'
MARK_B = '  /* <<< GEO <<< */'

def splice(body):
    """把 GEO 段写回 index.html 的两道标记之间；标记不在就拒绝，免得静默插歪。"""
    s = io.open(HTML, encoding='utf-8').read()
    a, b = s.index(MARK_A) + len(MARK_A), s.index(MARK_B)
    s = s[:a] + '\n' + body + '\n' + s[b:]
    io.open(HTML, 'w', encoding='utf-8', newline='\n').write(s)
    print('已写回 %s（%d 字节）' % (os.path.relpath(HTML, ROOT), len(s.encode('utf-8'))))

def main():
    geo = json.load(open(os.path.join(TMP, 'geo_boundary.json'), encoding='utf-8'))
    riv = json.load(open(os.path.join(TMP, 'geo_rivers.json'), encoding='utf-8'))
    ring = geo['rings'][0]
    lines = []
    lines.append('  var MAP = { z: %d, x0: %d, y0: %d, cols: %d, rows: %d };' % (Z, X0, Y0, COLS, ROWS))
    lines.append('  var MH = MAP.rows / MAP.cols * 100;   // 图框高（单位），terrain.jpg 的宽高比')
    lines.append("  var HENAN = %s;" % pts(ring))
    for k in ('dayu', 'jin', 'duohuai'):
        lines.append("  var RIV_%s = %s;" % (k.upper(), pts(riv['spines'][k][TRIM_HEAD:])))
    lines.append('  var CANAL = %s;' % pts(riv['canal']))
    m = ', '.join("{n:'%s',p:[%.2f,%.2f]}" % (n, ux(lon), uy(lat)) for n, (lon, lat) in riv['mountains'].items())
    lines.append('  var MOUNTAINS = [%s];' % m)
    c = ', '.join(city_js(t) for t in CITIES)
    lines.append('  var CITIES = [%s];' % c)
    a = ', '.join("{s:%d,t:'%s',p:[%.2f,%.2f]}" % (s, t, ux(lon), uy(lat)) for s, t, lon, lat in ANNO)
    lines.append('  var ANNO = [%s];' % a)
    lines.append("  var TITLE = { t: '%s', p: [%.2f, %.2f] };" % (TITLE[0], ux(TITLE[1]), uy(TITLE[2])))
    xs = [ux(a) for a, b in ring]
    ys = [uy(b) for a, b in ring]
    fx0, fx1 = min(xs) - 2.5, max(xs) + 2.5
    fy0, fy1 = min(ys) - 2.5, max(ys) + 2.5
    lines.append('  var FRAME = { x0: %.2f, y0: %.2f, x1: %.2f, y1: %.2f };' % (fx0, fy0, fx1, fy1))
    lines.append('  /* 四段脊柱索引一一对应：上游共用、下游各自摆动，逐点加权就是"整条河搬走" */')
    lines.append('  var SPINE = [RIV_DAYU, RIV_JIN, RIV_DUOHUAI, RIV_JIN];')
    body = '\n'.join(lines)
    open(os.path.join(TMP, 'geo_block.js'), 'w', encoding='utf-8').write(body + '\n')
    print('... %d 行 / %d 字节，已写 .tmp/geo_block.js' % (len(lines), len(body)))
    ap = argparse.ArgumentParser()
    ap.add_argument('--write-html', action='store_true', help='整段替换 index.html 里两道标记之间的 GEO 数据')
    args, _ = ap.parse_known_args()
    if args.write_html:
        splice(body)
    print('MH = %.3f' % (ROWS / float(COLS) * 100))
    print('省界包围盒单位 x %.1f..%.1f  y %.1f..%.1f'
          % (min(ux(a_) for a_, b_ in ring), max(ux(a_) for a_, b_ in ring),
             min(uy(b_) for a_, b_ in ring), max(uy(b_) for a_, b_ in ring)))
    for t in CITIES:
        print('  %-4s %8.2f,%7.2f -> %6.2f,%6.2f  %s'
              % (t[0], t[1], t[2], ux(t[1]), uy(t[2]), t[4] if len(t) > 4 else 'bottom'))

if __name__ == '__main__':
    main()
