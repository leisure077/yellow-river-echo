const ATLAS_W = 1024, ATLAS_H = 1536;
let selectedPOI = '', focusTimer = 0, flatMap = false;
const routes = [
  {name:'快速文化巡游',desc:'三处文化地标 · 长卷浏览顺序',ids:['hangu','longmen','emperors']},
  {name:'五城文明长卷',desc:'五城串联 · 文化主题展示，非步行线路',ids:['hangu','longmen','emperors','iron-tower','qicheng']},
  {name:'无障碍路线',desc:'入口 → 坡道 → 商都文化入口',ids:['entry-demo','ramp-demo','shangdu'],demo:true},
  {name:'亲子博物馆之旅',desc:'三个博物馆文化入口 · 非实时展讯',ids:['miaodigou','erlitou','shangdu']},
  {name:'古建与石刻',desc:'函谷关、龙门与铁塔 · 主题阅读线路',ids:['hangu','longmen','iron-tower']}
];
function getPOI(id) { return mapPOIs.find(p => p.id === id); }
function pois() {
  if (selectedRoute >= 0) return routes[selectedRoute].ids.map(getPOI).filter(Boolean);
  return mapPOIs.filter(p => (city === '全部' || city === p.city) &&
    (['发现','打卡'].includes(category) ? p.cat === '建筑' : p.cat === category));
}
function switchCategory(c) {
  clearTimeout(focusTimer); selectedPOI = ''; selectedRoute = -1; category = c;
  closeSheet(); mapPage();
  document.querySelector('.tabs .active')?.scrollIntoView({behavior:'smooth',block:'nearest',inline:'center'});
}
function marker(p, i) {
  const symbol = {建筑:'⌂',展览:'▤',餐饮:'♨',文创:'▣',卫生间:'WC',游客服务:'i'}[p.cat];
  const label = p.name, width = Math.max(138, label.length * 24 + 30);
  return `<g class="pin ${p.demo?'service-pin':''}" transform="translate(${p.x},${p.y})" data-id="${p.id}" tabindex="0" role="button" aria-label="${esc(label)}" onclick="poi('${p.id}')" onkeydown="if(event.key==='Enter'||event.key===' ')poi('${p.id}')">
    <g class="pin-pop" style="animation-delay:${i*65}ms"><g class="pin-scale">
      <ellipse cy="13" rx="26" ry="8" fill="#3b4d4433"/>
      <path d="M-25-48 A32 32 0 1 1 50 0 L0 8Z" fill="${p.demo?'#648b80':'#aa8246'}" stroke="#fffaf0" stroke-width="6"/>
      <text x="0" y="-36" text-anchor="middle" fill="white" style="font-size:27px">${symbol}</text>
      <rect x="${-width/2}" y="14" width="${width}" height="39" rx="18" fill="#fffbee" stroke="#d6c5a6" stroke-width="2"/>
      <text x="0" y="41" text-anchor="middle" fill="#504637" style="font-size:23px;font-weight:600">${esc(label)}</text>
    </g></g></g>`;
}
function svgMap(night=false,mini=false) {
  const points = mini ? mapPOIs.filter(p=>p.cat==='建筑') : pois();
  const line = selectedRoute >= 0 ? pois().map(p=>`${p.x},${p.y}`).join(' ') : '';
  return `<svg id="atlasSvg" viewBox="0 0 ${ATLAS_W} ${ATLAS_H}" aria-label="黄河文化手绘长卷，艺术布局非地理坐标">
    <g id="mapScene" transform="translate(${offset.x},${offset.y}) scale(${scale})">
      <image href="atlas.png" width="${ATLAS_W}" height="${ATLAS_H}"/>
      ${flatMap?'<rect width="1024" height="1536" fill="#fff9ec" opacity=".72"/>':''}
      <polyline points="${line}" stroke="#fff8df" stroke-width="16" fill="none" stroke-linejoin="round"/>
      <polyline class="path" points="${line}" stroke="#a83b36" stroke-width="9" fill="none" stroke-linejoin="round"/>
      ${points.map(marker).join('')}
    </g></svg>`;
}
function captionText() {
  if (selectedRoute >= 0) return esc(routes[selectedRoute].name) + ' · ' + routes[selectedRoute].ids.length + ' 站';
  const unit = ['餐饮','文创','卫生间','游客服务'].includes(category) ? '服务点' : '文化标记';
  return category + ' · ' + pois().length + ' 个' + unit;
}
function mapPage() {
  map = null;
  app.innerHTML = `<div class="atlas-shell"><nav class="tabs" aria-label="地图分类">${cats.map(c=>`<button class="${c===category?'active':''}" onclick="switchCategory('${c}')">${c}</button>`).join('')}</nav>
    <div class="atlas-search"><select aria-label="选择城市" onchange="city=this.value;selectedRoute=-1;resetAtlas()">${['全部',...cities].map(c=>`<option ${c===city?'selected':''}>${c}</option>`).join('')}</select><input id="search" placeholder="寻一处文化地标" onkeydown="if(event.key==='Enter')searchPOI()"><button aria-label="搜索地点" onclick="searchPOI()">⌕</button></div>
    <div class="map atlas-map" id="map"><div class="badge">手绘文化长卷 · 艺术布局，非导航${selectedRoute>=0?' · '+routes[selectedRoute].name:''}</div>${svgMap()}
      <div class="atlas-title"><small>沿 河 而 行</small><b>黄河续响平台</b><span>五城 · 一脉文明</span></div>
      <div class="tools"><button onclick="atlasIntro()">简介</button><button onclick="flatMap=!flatMap;mapPage()">${flatMap?'手绘':'淡化'}</button><button onclick="show('footprints')">足迹</button><button onclick="saved()">收藏</button></div>
      <div class="zoom-tools"><button aria-label="放大地图" onclick="zoom(1.3)">＋</button><button aria-label="缩小地图" onclick="zoom(1/1.3)">－</button><button aria-label="复位地图" onclick="resetAtlas()">⌖</button></div>
      <button class="routeBtn" onclick="routeList()">游览<br>路线</button>
      <div class="map-caption" aria-live="polite">${captionText()}</div>
    </div><div id="results"></div>
    ${category==='发现'?'<div class="discover-strip"><button onclick="show(\'footprints\')"><b>黄河明信片</b><span>收藏旅行的片刻 ›</span></button></div>':''}</div>`;
  attachPan();
  if (!pois().length) document.querySelector('#results').innerHTML='<p class="empty-map">此城市暂无该类标记，试试“全部”或其他分类。</p>';

}
function applyTransform(animate=false) {
  const g=document.querySelector('#mapScene'); if(!g)return;
  g.style.transition=animate&&!matchMedia('(prefers-reduced-motion: reduce)').matches?'transform 650ms cubic-bezier(.22,.68,0,1)':'none';
  g.setAttribute('transform',`translate(${offset.x},${offset.y}) scale(${scale})`);
}
function resetAtlas() {
 clearTimeout(focusTimer);selectedPOI='';scale=1;offset={x:0,y:0};
 if(city!=='全部'){
  const points=mapPOIs.filter(p=>p.city===city&&!p.demo);
  if(points.length){const xs=points.map(p=>p.x),ys=points.map(p=>p.y),x0=Math.min(...xs),x1=Math.max(...xs),y0=Math.min(...ys),y1=Math.max(...ys);
   scale=Math.min(4,Math.max(1,Math.min(850/(x1-x0+180),1100/(y1-y0+220))));offset={x:512-(x0+x1)*scale/2,y:768-(y0+y1)*scale/2};}
 }
 mapPage();applyTransform();
}
function zoom(n) {
  if(map){map.setZoom(map.getZoom()+(n>1?1:-1));return;}
  const next=Math.max(1,Math.min(6,scale*n)),ratio=next/scale;
  offset={x:ATLAS_W/2-(ATLAS_W/2-offset.x)*ratio,y:ATLAS_H/2-(ATLAS_H/2-offset.y)*ratio};
  scale=next;applyTransform(true);
}
function attachPan() {
  const el=document.querySelector('#atlasSvg'); if(!el)return;
  const pointers=new Map();let drag=null,pinch=null;
  const pos=e=>{const pt=new DOMPoint(e.clientX,e.clientY);return pt.matrixTransform(el.getScreenCTM().inverse());};
  el.onpointerdown=e=>{if(e.target.closest('.pin'))return;clearTimeout(focusTimer);let p=pos(e);pointers.set(e.pointerId,p);el.setPointerCapture(e.pointerId);drag={p,offset:{...offset}};if(pointers.size===2){let [a,b]=[...pointers.values()];pinch={distance:Math.hypot(a.x-b.x,a.y-b.y),scale,offset:{...offset},mid:{x:(a.x+b.x)/2,y:(a.y+b.y)/2}}}};
  el.onpointermove=e=>{if(!pointers.has(e.pointerId))return;let p=pos(e);pointers.set(e.pointerId,p);if(pointers.size===2&&pinch){let[a,b]=[...pointers.values()],mid={x:(a.x+b.x)/2,y:(a.y+b.y)/2};scale=Math.max(1,Math.min(6,pinch.scale*Math.hypot(a.x-b.x,a.y-b.y)/pinch.distance));let ratio=scale/pinch.scale;offset={x:mid.x-(pinch.mid.x-pinch.offset.x)*ratio,y:mid.y-(pinch.mid.y-pinch.offset.y)*ratio}}else if(drag){offset={x:drag.offset.x+p.x-drag.p.x,y:drag.offset.y+p.y-drag.p.y}}applyTransform()};
  el.onpointerup=el.onpointercancel=e=>{pointers.delete(e.pointerId);pinch=null;drag=null};
  el.onwheel=e=>{e.preventDefault();zoom(e.deltaY<0?1.1:1/1.1)};
}
function poi(id) {
  const p=getPOI(id);if(!p)return;
  clearTimeout(focusTimer);selectedPOI=id;scale=3.2;offset={x:ATLAS_W*.45-p.x*scale,y:ATLAS_H*.36-p.y*scale};applyTransform(true);
  focusTimer=setTimeout(()=>{if(mode!=='map'||selectedPOI!==id)return;poiDetail(p)},matchMedia('(prefers-reduced-motion: reduce)').matches?0:420);
}
function poiDetail(p) {
  const source=mapSources[p.source];
  sheet(`<div class="poi-heading"><small>${esc(p.city)} / ${esc(p.cat)} ${p.demo?'· 服务点':'· 文化地标'}</small><h2>${esc(p.name)}</h2></div>
    <p>${esc(p.intro||'该服务点由平台标注，营业信息以现场为准。')}</p>
    <p class="muted">${p.demo?'':'地标名称与简介依据公开资料整理；插画与位置经过艺术编排。'}</p>
    <div class="row"><button onclick="toggleFavorite('${p.id}')">${favorites.includes(p.id)?'取消收藏':'收藏地标'}</button><button onclick="checkin('${p.id}')">记录足迹</button></div>
    ${source?`<details><summary>资料来源</summary><p>${esc(source.name)}<br><span class="source-url">${esc(source.url)}</span><br>核对日期：2026-10-29</p></details>`:''}`);
}
function toggleFavorite(id){favorites=favorites.includes(id)?favorites.filter(x=>x!==id):[...favorites,id];persist();poiDetail(getPOI(id))}
function saved(){sheet('<h2>收藏地标</h2>'+favorites.map(getPOI).filter(Boolean).map(p=>`<button class="saved-place" onclick="closeSheet();city='全部';category='${p.cat}';mapPage();poi('${p.id}')">${esc(p.city)} · ${esc(p.name)} ›</button>`).join('')+(!favorites.map(getPOI).filter(Boolean).length?'<p>还没有收藏地标。</p>':''))}
function searchPOI(){const q=document.querySelector('#search').value.trim();if(map){new BMapGL.LocalSearch(map,{renderOptions:{map,autoViewport:true}}).search((city==='全部'?'河南':city)+' '+q);return}const found=mapPOIs.filter(p=>(city==='全部'||p.city===city)&&(p.name+p.city).includes(q));sheet('<h2>寻找文化地标</h2>'+found.map(p=>`<button class="saved-place" onclick="closeSheet();category='${p.cat}';selectedRoute=-1;mapPage();poi('${p.id}')">${esc(p.city)} · ${esc(p.name)} ›</button>`).join('')+(!found.length?'<p>没有匹配地点，试试其他关键词。</p>':''))}
function routeList(){
  const cards = routes.map((r,i)=>{
    const stops = r.ids.map(getPOI).filter(Boolean);
    const on = i === selectedRoute;
    return `<div class="route-card${on?' on':''}">
      <div class="route-head"><b>${esc(r.name)}</b><span class="route-tag">${stops.length} 站</span></div>
      <p class="muted">${esc(r.desc)}</p>
      <div class="route-stops">${stops.map((p,k)=>`<span><i>${k+1}</i>${esc(p.name)}</span>`).join('<em>›</em>')}</div>
      <div class="route-acts"><button class="ghost" onclick="viewRouteInAtlas(${i})">长卷查看</button>
        <button class="${on?'ghost':'primary'}" onclick="selectRoute(${i})">${on?'使用中':'开始浏览'}</button></div>
    </div>`;
  }).join('');
  sheet('<h2>游览路线</h2><small>按文化长卷的浏览顺序串联，不代表实地道路或距离。</small>'+cards+
    '<button class="route-new" onclick="if(window.Native)Native.journey();else toast(\'在鸿蒙应用中创建行程\')">＋ 创建我的行程</button>');
}
// 「长卷查看」= 切回离线手绘长卷并按线路镜头放大，与真实底图各走各的动线。
function viewRouteInAtlas(i){localStorage.setItem('hh-map-mode','offline');selectRoute(i);}
function selectRoute(i){if(!routes[i])return;selectedRoute=i;selectedPOI='';category='建筑';city='全部';scale=1;offset={x:0,y:0};closeSheet();show('map');if(routes[i].demo){scale=2.3;offset={x:ATLAS_W/2-350*scale,y:ATLAS_H*.44-880*scale};applyTransform(true)}}
function atlasIntro(){sheet('<h2>一卷看见黄河文明</h2><p>函谷关、龙门石窟、炎黄二帝塑像、开封铁塔与戚城遗址，在山水手绘中串联起五城记忆。</p><p>点分类，标记依次浮现；点地标，地图居中放大。</p><p class="muted">山水与建筑外形经艺术化处理，可用于行前的文化浏览与路线构思。</p><button onclick="closeSheet()">开始探索</button>')}
function travel(){category='发现';city='全部';mapPage()}
function footprintMap(){
 const ids=['hangu','longmen','qicheng','emperors','iron-tower'];
 return `<svg class="footprint-map" viewBox="0 0 1024 1536" aria-label="黄河文化地点足迹"><image href="atlas.png" width="1024" height="1536" opacity=".4"/><rect width="1024" height="1536" fill="#061f30" opacity=".3"/>${ids.map(getPOI).filter(Boolean).map(p=>{
 const lit=records.some(r=>r.city===p.city&&r.name===p.name);
 return `<g role="button" tabindex="0" aria-label="记录${esc(p.name)}足迹" onclick="footprintPlace('${p.id}')" onkeydown="if(event.key==='Enter'||event.key===' ')footprintPlace('${p.id}')"><circle cx="${p.x}" cy="${p.y}" r="${lit?24:16}" fill="${lit?'#5df1df':'#607780'}" stroke="#c7e0da" stroke-width="3"/><rect x="${Math.max(8,Math.min(744,p.x-130))}" y="${p.y+32}" width="260" height="56" rx="14" fill="#09212bd9"/><text x="${Math.max(138,Math.min(874,p.x))}" y="${p.y+70}" text-anchor="middle" fill="white" font-size="30">${esc(p.name)}</text></g>`}).join('')}</svg>`;
}
function footprintPlace(id){const p=getPOI(id);if(!p)return;city=p.city;addRecord();document.querySelector('#recName').value=p.name;document.querySelector('#recCity').value=p.city;}
function footprintPlaces(){return '<div class="footprint-places">'+cities.map(c=>'<details><summary>'+esc(c)+' · 选择具体地点</summary>'+mapPOIs.filter(p=>p.city===c&&!p.demo).map(p=>'<button class="saved-place" onclick="footprintPlace(\''+p.id+'\')">'+(records.some(r=>r.city===p.city&&r.name===p.name)?'● ':'○ ')+esc(p.name)+'</button>').join('')+'</details>').join('')+'</div>';}
function loadBaidu(){}
