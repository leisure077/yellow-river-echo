// Local raster pyramid: no external map engine, geographic tiles or AK requests.
loadBaidu=function(){};
const baseMapPage=mapPage;
mapPage=function(){baseMapPage();refreshTiles();mountSeason();};
const rasterSvg=svgMap;
svgMap=function(night,mini){return rasterSvg(night,mini).replace('<image href="atlas.png" width="1024" height="1536"/>','<g id="rasterTiles"></g>');};
const rasterTransform=applyTransform;
applyTransform=function(animated){offset.x=Math.max(1024*(1-scale),Math.min(0,offset.x));offset.y=Math.max(1536*(1-scale),Math.min(0,offset.y));rasterTransform(animated);refreshTiles();layoutAtlasPins();};
function layoutAtlasPins(){
 const boxes=[];
 for(const node of document.querySelectorAll('#mapScene > .pin')){
  const p=getPOI(node.dataset.id);if(!p)continue;
  const x=p.x*scale+offset.x,y=p.y*scale+offset.y,w=Math.max(138,p.name.length*24+30);
  const hidden=p.id!==selectedPOI&&boxes.some(b=>Math.abs(b.x-x)<(b.w+w)/2+10&&Math.abs(b.y-y)<110);
  node.style.visibility=hidden?'hidden':'visible';
  node.querySelector('.pin-scale')?.setAttribute('transform',`scale(${1/scale})`);
  if(!hidden)boxes.push({x,y,w});
 }
}
let tileFrame=0;
function refreshTiles(){cancelAnimationFrame(tileFrame);tileFrame=requestAnimationFrame(()=>{
 const host=document.querySelector('#rasterTiles');if(!host)return;
 const level=Math.max(0,Math.min(3,Math.ceil(Math.log2(Math.max(.125,scale)))+2));
 const factor=2**(3-level),step=256*factor,w=Math.ceil(1024/factor),h=Math.ceil(1536/factor);
 const minX=Math.max(0,Math.floor(-offset.x/scale/step)-1),maxX=Math.min(Math.ceil(w/256)-1,Math.floor((1024-offset.x)/scale/step)+1);
 const minY=Math.max(0,Math.floor(-offset.y/scale/step)-1),maxY=Math.min(Math.ceil(h/256)-1,Math.floor((1536-offset.y)/scale/step)+1);
 const keep=new Set();
 for(let x=minX;x<=maxX;x++)for(let y=minY;y<=maxY;y++){
 const id=`${atlasSeason}-${level}-${x}-${y}`;keep.add(id);if(host.querySelector(`[data-tile="${id}"]`))continue;
 const im=document.createElementNS('http://www.w3.org/2000/svg','image');im.dataset.tile=id;im.setAttribute('href',`seasons/${atlasSeason}/${level}/${x}/${y}.jpg`);im.setAttribute('x',x*step);im.setAttribute('y',y*step);im.setAttribute('width',Math.min(step,1024-x*step));im.setAttribute('height',Math.min(step,1536-y*step));host.append(im);
 }
 for(const im of [...host.children])if(!keep.has(im.dataset.tile))im.remove();
 layoutAtlasPins();
 });}
let atlasSeason=localStorage.getItem('hh-atlas-season')||'spring';
const seasonNames={spring:'春',summer:'夏',autumn:'秋',winter:'冬'};
if(!seasonNames[atlasSeason])atlasSeason='spring';
function mountSeason(){
 const host=document.querySelector('#map');if(!host)return;
 host.dataset.season=atlasSeason;
 const button=document.createElement('button');button.className='season-button';button.setAttribute('aria-label','切换春夏秋冬');button.textContent=seasonNames[atlasSeason];button.onclick=()=>{
  const names=Object.keys(seasonNames);atlasSeason=names[(names.indexOf(atlasSeason)+1)%4];
  localStorage.setItem('hh-atlas-season',atlasSeason);host.dataset.season=atlasSeason;button.textContent=seasonNames[atlasSeason];refreshTiles();paintWeather(host);
 };host.append(button);paintWeather(host);
}
function paintWeather(host){host.querySelector('.season-weather')?.remove();const layer=document.createElement('div');layer.className='season-weather';layer.setAttribute('aria-hidden','true');
 if(atlasSeason!=='summer')for(let i=0;i<14;i++){let flake=document.createElement('i');flake.style.cssText=`left:${(i*37)%100}%;animation-delay:-${i*.8}s;animation-duration:${8+i%5}s`;layer.append(flake)}host.append(layer);
}
const seasonStyle=document.createElement('style');seasonStyle.textContent=`
.season-button{position:absolute;left:12px;bottom:15px;width:60px;height:60px;padding:0;border-radius:50%;background:#fff9e9ed;color:#725733;border:2px solid #d5c39b;box-shadow:0 3px 14px #463b3430;z-index:6;font-size:12px}
.atlas-map .map-caption{left:83px;bottom:18px}.atlas-map .zoom-tools{bottom:90px}
#rasterTiles{transition:filter .8s ease}
#mapScene .pin-scale{transform-origin:0 0}
.atlas-title{display:none!important}
.season-weather{position:absolute;inset:0;overflow:hidden;pointer-events:none;z-index:2}
.season-weather i{position:absolute;top:-10px;width:6px;height:9px;border-radius:70% 10% 70% 10%;background:#f2b7c6;animation:seasonFall linear infinite}
[data-season=autumn] .season-weather i{background:#d69935}
[data-season=winter] .season-weather i{background:#fff;width:4px;height:4px;border-radius:50%}
@keyframes seasonFall{to{transform:translate(35px,850px) rotate(260deg);opacity:.1}}
@media(prefers-reduced-motion:reduce){.season-weather{display:none}#rasterTiles{transition:none}}
`;document.head.append(seasonStyle);
