"""从 Natural Earth 10m 河流中心线（公有领域）里抽河南境内的黄河、淮河、洛、沁等干流折线。

不引 GDAL/pyshp：shapefile 的 PolyLine 记录和 dbf 的字符字段都是定长的，手写解析 ~50 行。
产物 .tmp/geo_ne_rivers.json：{name: [[lon, lat], ...]}
"""
import json
import os
import struct
import sys
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(os.path.expanduser('~'), 'demcache')
TMP = os.path.join(ROOT, '.tmp')
URL = 'https://naturalearth.s3.amazonaws.com/10m_physical/ne_10m_rivers_lake_centerlines.zip'
BBOX = (110.0, 31.0, 117.5, 36.6)
WANT = {'Huang': '黄河', 'Wei': '渭河', 'Huangshui': '湟水', 'Qin': '沁河', 'Huai': '淮河',
        'Hudi': '沣河', 'Ying': '颍河', 'Zhang': '漳河'}

def ensure_zip():
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, 'ne_10m_rivers.zip')
    if not os.path.exists(path) or os.path.getsize(path) < 1000000:
        print('downloading %s' % URL)
        with open(path, 'wb') as f:
            f.write(urllib.request.urlopen(URL, timeout=120).read())
    print('zip %.1f MB' % (os.path.getsize(path) / 1048576.0))
    return path

def read_dbf_names(z):
    """返回 {记录序号: name 字段值}"""
    with z.open('ne_10m_rivers_lake_centerlines.dbf') as f:
        head = f.read(32)
        nrec = struct.unpack('<I', head[4:8])[0]
        hlen = struct.unpack('<H', head[8:10])[0]
        nfield = (hlen - 32 - 1) // 32
        fields = []
        for _ in range(nfield):
            d = f.read(32)
            fname = d[:11].split(b'\x00')[0].decode('latin1')
            flen = d[16]
            fields.append((fname, flen))
        f.read(1)
        out = {}
        for i in range(nrec):
            rec = f.read(1 + sum(l for _, l in fields))
            if len(rec) < 2:
                break
            off = 1
            vals = {}
            for fname, flen in fields:
                vals[fname] = rec[off:off + flen].decode('latin1').strip().rstrip('\x00')
                off += flen
            out[i] = vals.get('name') or vals.get('NAME') or ''
        return out

def read_shp_polylines(z):
    with z.open('ne_10m_rivers_lake_centerlines.shp') as f:
        data = f.read()
    total = struct.unpack('>I', data[24:28])[0] * 2
    pos, out = 100, []
    while pos < total:
        num, clen = struct.unpack('>II', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + clen * 2]
        pos += 8 + clen * 2
        st = struct.unpack('<I', body[:4])[0]
        if st != 3:
            out.append([])
            continue
        nparts, npoints = struct.unpack('<II', body[36:44])
        parts = struct.unpack('<%di' % nparts, body[44:44 + 4 * nparts])
        pts = struct.unpack('<%dd' % (2 * npoints), body[44 + 4 * nparts:44 + 4 * nparts + 16 * npoints])
        coords = [(pts[i], pts[i + 1]) for i in range(0, len(pts), 2)]
        lines = []
        bounds = list(parts) + [len(coords)]
        for i in range(nparts):
            lines.append(coords[bounds[i]:bounds[i + 1]])
        out.append(lines)
    return out

def main():
    sys.stdout.reconfigure(encoding='utf-8')
    z = zipfile.ZipFile(ensure_zip())
    names = read_dbf_names(z)
    shapes = read_shp_polylines(z)
    print('records %d / shapes %d' % (len(names), len(shapes)))
    hits = {}
    for i, lines in enumerate(shapes):
        nm = names.get(i, '')
        target = None
        for k, v in WANT.items():
            if nm.strip().lower() == k.lower():
                target = v
        if not target:
            continue
        kept = []
        for ln in lines:
            if len(ln) > 3:
                kept.append(ln)
                inside = sum(1 for p in ln if BBOX[0] <= p[0] <= BBOX[2] and BBOX[1] <= p[1] <= BBOX[3])
                print('  %-10s (%s)  %d 点，河南范围内 %d 点' % (target, nm, len(ln), inside))
        if kept:
            hits.setdefault(target, []).extend(kept)
    os.makedirs(TMP, exist_ok=True)
    json.dump(hits, open(os.path.join(TMP, 'geo_ne_rivers.json'), 'w', encoding='utf-8'), ensure_ascii=False)
    print('wrote .tmp/geo_ne_rivers.json keys=%s' % list(hits))

if __name__ == '__main__':
    main()
