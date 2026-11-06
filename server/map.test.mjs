import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import fs from 'node:fs';

const base = new URL('../entry/src/main/resources/rawfile/experience/', import.meta.url);
const read = name => fs.readFileSync(new URL(name, base), 'utf8');

class El {
  constructor(tag) { this.tag = tag; this.children = []; this.parentNode = null; this.dataset = {}; this.style = {}; this.attrs = {}; this.isConnected = true; this.text = ''; }
  set className(v) { this.attrs.class = v; } get className() { return this.attrs.class || ''; }
  set textContent(v) { this.text = String(v); } get textContent() { return this.text; }
  setAttribute(k, v) { this.attrs[k] = String(v); }
  getAttribute(k) { return this.attrs[k] ?? null; }
  append(n) { n.parentNode = this; this.children.push(n); return n; }
  appendChild(n) { return this.append(n); }
  remove() { this.isConnected = false; const p = this.parentNode; if (p) p.children = p.children.filter(c => c !== this); }
  *walk() { for (const c of this.children) { yield c; yield* c.walk(); } }
  simple(sel) {
    if (sel.startsWith('#')) return this.attrs.id === sel.slice(1);
    const attr = /^\[data-tile="(.+)"\]$/.exec(sel);
    if (attr) return this.dataset.tile === attr[1];
    return this.className.split(/\s+/).includes(sel.replace(/^\./, ''));
  }
  match(sel) {
    const parts = sel.split('>').map(s => s.trim());
    if (!this.simple(parts[parts.length - 1])) return false;
    let node = this.parentNode;
    for (let i = parts.length - 2; i >= 0; i--) {
      while (node && !node.simple(parts[i])) node = node.parentNode;
      if (!node) return false;
      node = node.parentNode;
    }
    return true;
  }
  querySelector(sel) { for (const n of this.walk()) if (n.match(sel)) return n; return null; }
  querySelectorAll(sel) { return [...this.walk()].filter(n => n.match(sel)); }
}

function setup(seed = {}) {
  const store = new Map(seed ? Object.entries(seed) : []);
  const frames = [];
  const created = [];
  const root = new El('root');
  const head = new El('head'); root.append(head);
  const body = new El('body'); root.append(body);
  const app = new El('div'); app.setAttribute('id', 'app'); body.append(app);
  let html = '';
  Object.defineProperty(app, 'innerHTML', {
    get() { return html; },
    set(v) {
      html = String(v); app.children = [];
      const byId = new Map();
      for (const m of html.matchAll(/id="([^"]+)"/g)) {
        if (byId.has(m[1])) continue;
        const node = new El('div');
        node.setAttribute('id', m[1]);
        node.parentNode = app;
        byId.set(m[1], node);
        app.children.push(node);
      }
      for (const m of html.matchAll(/<g class="pin([^"]*)"\s+transform="translate\(([-\d.]+),([-\d.]+)\)"\s+data-id="([^"]+)"/g)) {
        const scene = byId.get('mapScene');
        if (!scene) continue;
        const pin = new El('g');
        pin.className = 'pin' + m[1];
        pin.dataset.id = m[4];
        pin.append(newscale());
        scene.append(pin);
      }
    }
  });
  function newscale() { const g = new El('g'); g.className = 'pin-scale'; return g; }
  const document = {
    head, body,
    createElement: tag => new El(tag),
    createElementNS: (ns, tag) => { const n = new El(tag); created.push(n); return n; },
    querySelector: sel => root.querySelector(sel),
    querySelectorAll: sel => root.querySelectorAll(sel)
  };
  const context = {
    console, document, head,
    localStorage: { getItem: k => store.get(k) ?? null, setItem: (k, v) => store.set(k, String(v)) },
    requestAnimationFrame: cb => { frames.push(cb); return frames.length; },
    cancelAnimationFrame: id => { frames[id - 1] = null; },
    setTimeout: () => 0, clearTimeout() {}, matchMedia: () => ({ matches: false }),
    app, cats: ['发现', '建筑', '展览', '打卡', '餐饮', '文创', '卫生间', '游客服务'],
    esc: s => String(s), toast() {}, sheet() {}, closeSheet() {}, show() {}, back() {}
  };
  context.window = context;
  vm.createContext(context);
  const prelude = 'var scale=1,offset={x:0,y:0},map=null,mode="map",category="建筑",city="全部",selectedRoute=-1,records=[],favorites=[];';
  vm.runInContext([prelude, read('atlas-data.js'), read('season-layout.js'), read('atlas.js'), read('offline-tiles.js')].join('\n;\n'), context);
  return {
    context, store, created, document, app,
    flush() { const pending = frames.splice(0); for (const cb of pending) if (cb) cb(); },
    tiles() { const host = document.querySelector('#rasterTiles'); return host ? host.children.map(n => n.attrs) : []; },
    hrefs() { const host = document.querySelector('#rasterTiles'); return host ? host.children.map(n => n.attrs.href) : []; },
    live() { const host = document.querySelector('#rasterTiles'); return host ? host.children.filter(n => n.isConnected).length : 0; }
  };
}

test('offline atlas paints package tiles instead of the whole scroll image', () => {
  const x = setup();
  x.context.mapPage();
  x.flush();
  assert.equal(x.app.innerHTML.includes('href="atlas.png"'), false);
  assert.equal(x.tiles().length, 24);
  assert.deepEqual(new Set(x.tiles().map(t => t.href.split('/')[1])), new Set(['spring']));
  assert.equal(x.hrefs().some(h => /^https?:/.test(h) || h.startsWith('//')), false);
  assert.equal(x.hrefs().every(h => /^seasons\/spring\/3\/\d\/\d\.jpg$/.test(h)), true);
  assert.equal(x.hrefs().every((h, i, all) => all.indexOf(h) === i), true);
  assert.equal(x.context.map, null);
  x.context.loadBaidu();
  assert.equal(x.document.head.children.every(n => n.tag === 'style'), true);
});

test('panning clamps the scene inside the atlas bounds', () => {
  const x = setup();
  x.context.mapPage();
  x.flush();
  x.context.scale = 6;
  x.context.offset = { x: 800, y: -99999 };
  x.context.applyTransform(true);
  x.flush();
  assert.equal(x.context.offset.x, 0);
  assert.equal(x.context.offset.y, -7680);
  const scene = x.document.querySelector('#mapScene');
  assert.equal(scene.attrs.transform, 'translate(0,-7680) scale(6)');
  x.context.offset = { x: -99999, y: 40 };
  x.context.applyTransform(false);
  x.flush();
  assert.equal(x.context.offset.x, -5120);
  assert.equal(x.context.offset.y, 0);
});

test('moving the viewport retires off-screen tiles and reuses the rest', () => {
  const x = setup();
  x.context.mapPage();
  x.flush();
  assert.equal(x.created.length, 24);
  x.context.scale = 6;
  x.context.offset = { x: -5120, y: 0 };
  x.context.applyTransform(false);
  x.flush();
  const ids = x.tiles().map(t => t.href);
  assert.equal(ids.length, 6);
  assert.equal(x.created.length, 24);
  assert.equal(ids.every(h => /^seasons\/spring\/3\/[23]\/[012]\.jpg$/.test(h)), true);
  const before = new Set(ids);
  x.context.offset = { x: -4096, y: 0 };
  x.context.applyTransform(false);
  x.flush();
  const after = x.tiles().map(t => t.href);
  assert.equal(after.length, 9);
  assert.equal(after.filter(h => before.has(h)).length, 6);
  assert.equal(x.created.length, 27);
});

test('tile level follows the per-season cap from the manifest', () => {
  const x = setup();
  x.context.mapPage();
  x.flush();
  x.context.window.inkAtlasLevels = { spring: 1, summer: 1, autumn: 1, winter: 1 };
  x.context.scale = 4;
  x.context.refreshTiles();
  x.flush();
  const tiles = x.tiles();
  assert.deepEqual(tiles.map(t => t.href), ['seasons/spring/1/0/0.jpg', 'seasons/spring/1/0/1.jpg']);
  assert.deepEqual(tiles.map(t => t.width + 'x' + t.height), ['1024x1024', '1024x512']);
  assert.deepEqual(tiles.map(t => t.y), ['0', '1024']);
  x.context.window.inkAtlasLevels = { spring: 3 };
  x.context.refreshTiles();
  x.flush();
  assert.equal(x.tiles().length, 9);
  assert.equal(x.tiles().every(t => t.width + 'x' + t.height === '256x256'), true);
  assert.equal(x.tiles()[0].href, 'seasons/spring/3/0/0.jpg');
});

test('the season button repaints tiles and remembers the season', () => {
  const fresh = setup({ 'hh-atlas-season': 'monsoon' });
  fresh.context.mapPage();
  fresh.flush();
  assert.equal(fresh.hrefs().every(h => h.includes('/spring/')), true);

  const x = setup();
  x.context.mapPage();
  x.flush();
  const host = x.document.querySelector('#map');
  const button = host.children.find(n => n.className === 'season-button');
  const labels = [];
  for (let i = 0; i < 4; i++) {
    const season = host.dataset.season;
    labels.push(button.textContent);
    assert.equal(host.children.filter(n => n.className === 'season-button').length, 1);
    assert.equal(x.hrefs().every(h => h.includes('/' + season + '/')), true);
    const weather = host.children.find(n => n.className === 'season-weather');
    assert.equal(weather.children.length, season === 'summer' ? 0 : 14);
    button.onclick();
    x.flush();
  }
  assert.deepEqual(labels, ['春', '夏', '秋', '冬']);
  assert.equal(host.dataset.season, 'spring');
  assert.equal(x.store.get('hh-atlas-season'), 'spring');
  assert.equal(x.live(), 24);
});

test('labels keep their on-screen size and overlapping pins hide', () => {
  const x = setup();
  x.context.mapPage();
  x.flush();
  const pins = x.document.querySelectorAll('#mapScene > .pin');
  assert.equal(pins.length, 21);
  const shown = pins.filter(p => p.style.visibility === 'visible').map(p => p.dataset.id);
  assert.deepEqual(shown, ['hangu', 'longmen', 'emperors', 'iron-tower', 'qicheng', 'lm-xiangshan', 'kf-jieyin', 'zz-wulong']);
  assert.equal(pins.every(p => p.querySelector('.pin-scale').attrs.transform === 'scale(1)'), true);
  x.context.poi('longmen');
  x.flush();
  assert.equal(x.context.scale, 3.2);
  assert.equal(pins.every(p => p.querySelector('.pin-scale').attrs.transform === 'scale(0.3125)'), true);
  assert.equal(pins.find(p => p.dataset.id === 'longmen').style.visibility, 'visible');
  assert.equal(x.live(), 12);
});
