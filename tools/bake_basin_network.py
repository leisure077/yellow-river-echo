"""Extract the connected Yellow River network from HydroRIVERS v1 (offline app asset).

Public ArcGIS mirror of HydroRIVERS Asia; MAIN_RIV=40417973 is the Yellow River outlet.
No synthetic tributaries. Main stem follows greatest upstream distance at each junction.
"""
import json, urllib.request, urllib.parse, pathlib, time
from concurrent.futures import ThreadPoolExecutor

ROOT = pathlib.Path(__file__).resolve().parents[1]
CACHE = ROOT / '.tmp/basin-network'
CACHE.mkdir(exist_ok=True)
URL = 'https://services1.arcgis.com/7DRakJXKPEhwv0fM/ArcGIS/rest/services/Rivers/FeatureServer/0/query'

def query(**kw):
    for attempt in range(4):
        try:
            u = URL + '?' + urllib.parse.urlencode(dict(f='json', **kw))
            with urllib.request.urlopen(u, timeout=90) as r:
                d = json.load(r)
            if 'error' in d: raise RuntimeError(d['error'])
            return d
        except Exception:
            if attempt == 3: raise
            time.sleep(2)

def batch(ids):
    p = CACHE / f'{ids[0]}.json'
    if not p.exists():
        d = query(where=f'MAIN_RIV=40417973 AND FID>={ids[0]} AND FID<={ids[-1]}', outFields='HYRIV_ID,NEXT_DOWN,MAIN_RIV,DIST_UP_KM,ORD_STRA,UPLAND_SKM', outSR=4326, returnGeometry='true', geometryPrecision=5)
        p.write_text(json.dumps(d), encoding='utf-8')
    return json.loads(p.read_text())['features']

ids = sorted(query(where='MAIN_RIV=40417973', returnIdsOnly='true')['objectIds'])
print('Reaches:', len(ids), flush=True)
features = []
with ThreadPoolExecutor(max_workers=5) as pool:
    for fs in pool.map(batch, [ids[i:i+500] for i in range(0,len(ids),500)]):
        features.extend(fs)
        print('Fetched:', len(features), flush=True)
byid = {f['attributes']['HYRIV_ID']: f for f in features}
up = {}
for f in features:
    up.setdefault(f['attributes']['NEXT_DOWN'], []).append(f)
main_ids = set()
cur = byid[40417973]
stem = []
while cur:
    rid = cur['attributes']['HYRIV_ID']
    assert rid not in main_ids
    main_ids.add(rid)
    stem.append(cur)
    cur = max(up.get(rid, []), key=lambda f:f['attributes']['DIST_UP_KM'], default=None)
main = []
for f in reversed(stem):
    for path in f['geometry']['paths']:
        for pt in path:
            if not main or pt != main[-1]: main.append(pt)

def simplify(pts, eps=0.003):
    if len(pts)<3:return pts
    a,b=pts[0],pts[-1]; dx=b[0]-a[0];dy=b[1]-a[1];den=dx*dx+dy*dy
    best=0; idx=0
    for i,p in enumerate(pts[1:-1],1):
        t=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/den)) if den else 0
        d=(p[0]-a[0]-t*dx)**2+(p[1]-a[1]-t*dy)**2
        if d>best:best=d;idx=i
    return simplify(pts[:idx+1],eps)[:-1]+simplify(pts[idx:],eps) if best>eps*eps else [a,b]

reaches=[]
for f in features:
    a=f['attributes']
    if a['HYRIV_ID'] in main_ids:continue
    for pts in f['geometry']['paths']:
        pts=simplify(pts)
        reaches.append(dict(order=a['ORD_STRA'], pts=[v for p in pts for v in p]))
out=dict(source='HydroRIVERS v1 / Lehner & Grill (2013)', outlet=40417973, main=[v for p in simplify(main,0.0015) for v in p], reaches=reaches)
p=ROOT/'entry/src/main/resources/rawfile/basin-network.json'
p.write_text(json.dumps(out,separators=(',',':')),encoding='utf-8')
print('Saved',p,'bytes',p.stat().st_size,'main vertices',len(out['main'])//2,'tributary reaches',len(reaches),flush=True)
